import 'dart:async';

import 'bt_channel.dart';

class ElmTimeout implements Exception {
  final String cmd;
  ElmTimeout(this.cmd);
  @override
  String toString() => 'ELM327 timeout on "$cmd"';
}

/// Serialises commands to an ELM327 and returns the text before the '>' prompt.
/// Cheap clones cannot handle overlapping requests, so everything goes
/// through a single queue.
class Elm327 {
  final BtChannel bt;
  final _buffer = StringBuffer();
  Completer<String>? _pending;
  Future<void> _queue = Future.value();
  StreamSubscription<String>? _sub;

  /// Called when the native side reports the Bluetooth link dropped.
  void Function()? onDisconnected;

  Elm327(this.bt) {
    _sub = bt.data.listen(_onData);
  }

  void _onData(String chunk) {
    if (chunk == BtChannel.disconnectedMarker) {
      _failPending(StateError('disconnected'));
      onDisconnected?.call();
      return;
    }
    _buffer.write(chunk);
    final text = _buffer.toString();
    final idx = text.indexOf('>');
    if (idx < 0) return;
    final response = text.substring(0, idx);
    _buffer
      ..clear()
      ..write(text.substring(idx + 1));
    final p = _pending;
    _pending = null;
    if (p != null && !p.isCompleted) p.complete(response);
  }

  void _failPending(Object error) {
    final p = _pending;
    _pending = null;
    _buffer.clear();
    if (p != null && !p.isCompleted) p.completeError(error);
  }

  /// Sends [cmd] and returns the cleaned, upper-case response lines joined by '\n'.
  Future<String> send(String cmd,
      {Duration timeout = const Duration(milliseconds: 1500)}) {
    final result = Completer<String>();
    _queue = _queue.then((_) async {
      try {
        final pending = Completer<String>();
        _pending = pending;
        await bt.write('$cmd\r');
        final raw = await pending.future.timeout(timeout);
        result.complete(_clean(raw, cmd));
      } on TimeoutException {
        // Drop whatever partial answer arrived so it is not attributed
        // to the next command.
        _pending = null;
        await Future<void>.delayed(const Duration(milliseconds: 150));
        _buffer.clear();
        result.completeError(ElmTimeout(cmd));
      } catch (e) {
        _pending = null;
        _buffer.clear();
        if (!result.isCompleted) result.completeError(e);
      }
    });
    return result.future;
  }

  static String _clean(String raw, String cmd) {
    final lines = raw
        .replaceAll('\r', '\n')
        .split('\n')
        .map((l) => l.trim().toUpperCase())
        .where((l) => l.isNotEmpty)
        .where((l) => l != cmd.toUpperCase()) // echo, if ATE0 not applied yet
        .where((l) => !l.startsWith('SEARCHING'))
        .toList();
    return lines.join('\n');
  }

  /// Standard init sequence. Returns the adapter version string (from ATZ).
  Future<String> init() async {
    final version =
        await send('ATZ', timeout: const Duration(seconds: 3)).catchError((_) => '');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    for (final c in ['ATE0', 'ATL0', 'ATS0', 'ATH0', 'ATAT1', 'ATSP0']) {
      await send(c);
    }
    return version;
  }

  void dispose() {
    _sub?.cancel();
    _failPending(StateError('disposed'));
  }

  // ---------- response helpers ----------

  static const _errors = [
    'NO DATA',
    '?',
    'STOPPED',
    'UNABLE TO CONNECT',
    'CAN ERROR',
    'BUS ERROR',
    'BUS INIT',
    'ERROR',
    'BUFFER FULL',
    'DATA ERROR',
  ];

  static bool isError(String resp) =>
      resp.isEmpty || _errors.any((e) => resp.contains(e));

  /// For a Mode 01 request of [pid], returns the data bytes (A, B, ...) from
  /// every ECU line that answered, e.g. "410C1AF8" -> [0x1A, 0xF8].
  static List<List<int>> mode01Bytes(String resp, int pid) {
    if (isError(resp)) return const [];
    final prefix = '41${pid.toRadixString(16).padLeft(2, '0').toUpperCase()}';
    final out = <List<int>>[];
    for (final line in resp.split('\n')) {
      final hex = line.replaceAll(' ', '');
      final i = hex.indexOf(prefix);
      if (i < 0) continue;
      final bytes = hexToBytes(hex.substring(i + prefix.length));
      if (bytes.isNotEmpty) out.add(bytes);
    }
    return out;
  }

  static List<int> hexToBytes(String hex) {
    final clean = hex.replaceAll(RegExp(r'[^0-9A-F]'), '');
    final out = <int>[];
    for (var i = 0; i + 1 < clean.length; i += 2) {
      out.add(int.parse(clean.substring(i, i + 2), radix: 16));
    }
    return out;
  }
}
