import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../settings.dart';
import 'bt_channel.dart';
import 'elm327.dart';
import 'fuel.dart';
import 'pids.dart';

enum ObdState { disconnected, connecting, initializing, connected }

/// One polling cycle's snapshot, consumed by the trip recorder.
class ObdSample {
  final DateTime ts;
  final double? rpm;
  final double? speed;
  final double? coolant;
  final double? fuelRateLh;
  final double? fuelLevelPct;
  const ObdSample(this.ts, this.rpm, this.speed, this.coolant, this.fuelRateLh,
      this.fuelLevelPct);
}

class ProbeResult {
  final String label;
  final String cmd;
  final String raw;
  final double? km;
  const ProbeResult(this.label, this.cmd, this.raw, this.km);
}

class ObdService extends ChangeNotifier {
  final BtChannel bt;
  final AppSettings settings;
  late final Elm327 elm;

  ObdState state = ObdState.disconnected;
  String status = 'غير متصل';
  String adapterVersion = '';
  String protocol = '';

  /// PIDs the car reports as supported (from 0100, 0120, ...).
  final Set<int> supported = {};

  /// Latest decoded value per PID.
  final Map<int, double> values = {};

  /// Latest raw data bytes per PID (for text-valued and unknown PIDs).
  final Map<int, List<int>> rawBytes = {};

  /// Vehicle identification number, if the ECU reports it (Mode 09).
  String? vin;

  /// Definition for [pid]; supported PIDs without a formula get a raw one.
  PidDef defFor(int pid) => Pids.byId[pid] ?? PidDef.unknown(pid);

  /// Every supported PID except the range markers (0x20, 0x40, ...).
  List<PidDef> get supportedDefs {
    final known = Pids.all.where((p) => supported.contains(p.pid));
    final unknown = (supported
            .where((id) => !Pids.byId.containsKey(id) && id % 0x20 != 0)
            .toList()
          ..sort())
        .map(PidDef.unknown);
    return [...known, ...unknown];
  }
  DateTime? lastUpdate;

  FuelSource fuelSource = FuelSource.none;
  double? fuelRateLh;
  double? instantL100;

  final _samples = StreamController<ObdSample>.broadcast();
  Stream<ObdSample> get samples => _samples.stream;

  bool _running = false;
  int _slowIndex = 0;
  int _consecutiveErrors = 0;

  ObdService(this.bt, this.settings) {
    elm = Elm327(bt);
    elm.onDisconnected = () {
      if (state != ObdState.disconnected) _setDisconnected('انقطع الاتصال');
    };
  }

  bool get isConnected => state == ObdState.connected;

  Future<void> connect() async {
    final address = settings.deviceAddress;
    if (address == null) {
      status = 'اختار جهاز الـ OBD من الإعدادات';
      notifyListeners();
      return;
    }
    if (state != ObdState.disconnected) return;

    if (!await Permission.bluetoothConnect.request().isGranted) {
      status = 'لازم توافق على صلاحية Bluetooth (الأجهزة القريبة)';
      notifyListeners();
      return;
    }

    state = ObdState.connecting;
    status = 'جاري الاتصال بـ ${settings.deviceName ?? address}…';
    notifyListeners();
    try {
      await bt.connect(address);
      state = ObdState.initializing;
      status = 'تهيئة الجهاز…';
      notifyListeners();

      adapterVersion = await elm.init();
      await _discoverSupported();
      protocol = await elm.send('ATDPN').catchError((_) => '');
      vin = await _readVin();
      fuelSource = FuelCalc.sourceFor(supported);

      if (supported.isEmpty) {
        throw StateError('العربية ما ردتش. اتأكد إن الكونتاكت شغال.');
      }

      state = ObdState.connected;
      status = 'متصل';
      notifyListeners();
      _startLoop();
    } catch (e) {
      await bt.disconnect().catchError((_) {});
      _setDisconnected('فشل الاتصال: ${_short(e)}');
    }
  }

  Future<void> disconnect() async {
    _running = false;
    await bt.disconnect().catchError((_) {});
    _setDisconnected('غير متصل');
  }

  void _setDisconnected(String msg) {
    _running = false;
    state = ObdState.disconnected;
    status = msg;
    fuelRateLh = null;
    instantL100 = null;
    notifyListeners();
  }

  Future<void> _discoverSupported() async {
    supported.clear();
    var base = 0x00;
    while (base <= 0xC0) {
      final cmd = '01${base.toRadixString(16).padLeft(2, '0').toUpperCase()}';
      String resp;
      try {
        // First request may trigger protocol search ("SEARCHING...").
        resp = await elm.send(cmd,
            timeout: Duration(seconds: base == 0 ? 8 : 2));
      } on ElmTimeout {
        break;
      }
      final answers = Elm327.mode01Bytes(resp, base);
      if (answers.isEmpty) break;
      var mask = 0;
      for (final a in answers) {
        if (a.length < 4) continue;
        mask |= (a[0] << 24) | (a[1] << 16) | (a[2] << 8) | a[3];
      }
      for (var bit = 0; bit < 32; bit++) {
        if (mask & (1 << (31 - bit)) != 0) supported.add(base + bit + 1);
      }
      // Bit 32 says whether the next range (base+0x20) exists.
      if (!supported.contains(base + 0x20)) break;
      base += 0x20;
    }
  }

  // ---------- polling ----------

  List<int> get _fastPids {
    final fast = <int>[Pids.rpm, Pids.speed, ...FuelCalc.inputsFor(fuelSource)];
    return fast.where(supported.contains).toList();
  }

  List<int> get _slowPids {
    final fast = _fastPids.toSet();
    return supportedDefs
        .map((p) => p.pid)
        .where((id) => !fast.contains(id))
        .toList();
  }

  void _startLoop() {
    if (_running) return;
    _running = true;
    _consecutiveErrors = 0;
    unawaited(_loop());
  }

  Future<void> _loop() async {
    while (_running && state == ObdState.connected) {
      final batch = <int>[..._fastPids];
      final slow = _slowPids;
      // Dashboard-critical slow PIDs get extra turns.
      const priority = [Pids.coolant, Pids.fuelLevel, Pids.iat, Pids.throttle];
      if (slow.isNotEmpty) {
        batch.add(slow[_slowIndex % slow.length]);
        _slowIndex++;
        final pr = priority.where(slow.contains).toList();
        if (pr.isNotEmpty) batch.add(pr[_slowIndex % pr.length]);
      }

      for (final pid in batch.toSet()) {
        if (!_running) return;
        await _poll(pid);
      }

      fuelRateLh = FuelCalc.litresPerHour(fuelSource, values, settings);
      instantL100 = FuelCalc.litresPer100(fuelRateLh, values[Pids.speed]);
      lastUpdate = DateTime.now();
      _samples.add(ObdSample(
        lastUpdate!,
        values[Pids.rpm],
        values[Pids.speed],
        values[Pids.coolant],
        fuelRateLh,
        values[Pids.fuelLevel],
      ));
      notifyListeners();

      if (_consecutiveErrors > 15) {
        // Engine probably switched off (ECU stops answering).
        values.remove(Pids.rpm);
        values.remove(Pids.speed);
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  Future<void> _poll(int pid) async {
    final def = defFor(pid);
    try {
      final resp = await elm.send(def.hex);
      final answers = Elm327.mode01Bytes(resp, pid);
      if (answers.isEmpty || answers.first.length < def.bytes) {
        _consecutiveErrors++;
        return;
      }
      rawBytes[pid] = answers.first;
      values[pid] = def.decode(answers.first);
      _consecutiveErrors = 0;
    } on ElmTimeout {
      _consecutiveErrors++;
    } catch (_) {
      _consecutiveErrors++;
    }
  }

  // ---------- VIN ----------

  Future<String?> _readVin() async {
    try {
      final resp = await elm.send('0902', timeout: const Duration(seconds: 4));
      if (Elm327.isError(resp)) return null;
      for (final frame in _joinFrames(resp)) {
        final i = frame.indexOf('4902');
        if (i < 0) continue;
        final bytes = Elm327.hexToBytes(frame.substring(i + 4));
        final chars = bytes
            .where((b) => b >= 0x30 && b <= 0x5A) // 0-9, A-Z
            .map(String.fromCharCode)
            .join();
        if (chars.length >= 17) return chars.substring(chars.length - 17);
        if (chars.isNotEmpty) return chars;
      }
    } catch (_) {}
    return null;
  }

  // ---------- odometer probe ----------

  /// Tries the known ways an ECU may expose total distance and returns the
  /// raw replies, so an unsupported car still tells us what it answered.
  Future<List<ProbeResult>> probeOdometer() async {
    final out = <ProbeResult>[];

    Future<String> ask(String cmd) async {
      try {
        return await elm.send(cmd, timeout: const Duration(seconds: 3));
      } catch (e) {
        return 'ERR: $e';
      }
    }

    // 1) SAE J1979 PID A6 (odometer, 0.1 km).
    var raw = await ask('01A6');
    var b = Elm327.mode01Bytes(raw, 0xA6);
    out.add(ProbeResult('PID 01A6 (العداد القياسي)', '01A6', raw,
        b.isNotEmpty && b.first.length >= 4 ? _u32(b.first) / 10 : null));

    // 2) ISO 27145 / UDS DID F4A6 (same value over service 22).
    raw = await ask('22F4A6');
    var d = _did(raw, 'F4A6');
    out.add(ProbeResult('UDS DID F4A6', '22F4A6', raw,
        d != null && d.length >= 4 ? _u32(d) / 10 : null));

    // 3) DID DD01, used by several manufacturers for total distance (km).
    raw = await ask('22DD01');
    d = _did(raw, 'DD01');
    out.add(ProbeResult('UDS DID DD01', '22DD01', raw,
        d != null && d.length >= 3
            ? (d[0] * 65536 + d[1] * 256 + d[2]).toDouble()
            : null));

    // Context: distance since codes cleared (almost always supported).
    raw = await ask('0131');
    b = Elm327.mode01Bytes(raw, 0x31);
    out.add(ProbeResult('مسافة من مسح الأعطال (مش العداد)', '0131', raw,
        b.isNotEmpty && b.first.length >= 2
            ? (b.first[0] * 256 + b.first[1]).toDouble()
            : null));
    return out;
  }

  static int _u32(List<int> d) =>
      d[0] * 16777216 + d[1] * 65536 + d[2] * 256 + d[3];

  /// Data bytes of a positive service-22 reply ("62" + DID + data), or null
  /// for a negative reply ("7F22..") / no data.
  static List<int>? _did(String raw, String did) {
    for (final frame in _joinFrames(raw)) {
      final i = frame.indexOf('62$did');
      if (i >= 0) return Elm327.hexToBytes(frame.substring(i + 6));
    }
    return null;
  }

  // ---------- trouble codes ----------

  Future<List<String>> readDtcs() async {
    final resp = await elm.send('03', timeout: const Duration(seconds: 4));
    if (!resp.contains('43')) return [];
    final isCan = _isCan;
    final codes = <String>{};
    for (final frame in _joinFrames(resp)) {
      final i = frame.indexOf('43');
      if (i < 0) continue;
      var bytes = Elm327.hexToBytes(frame.substring(i + 2));
      if (isCan && bytes.isNotEmpty) bytes = bytes.sublist(1); // count byte
      for (var j = 0; j + 1 < bytes.length; j += 2) {
        final a = bytes[j], b = bytes[j + 1];
        if (a == 0 && b == 0) continue;
        const letters = ['P', 'C', 'B', 'U'];
        final code = '${letters[a >> 6]}${(a >> 4) & 0x3}'
            '${(a & 0xF).toRadixString(16)}'
            '${b.toRadixString(16).padLeft(2, '0')}';
        codes.add(code.toUpperCase());
      }
    }
    return codes.toList()..sort();
  }

  Future<bool> clearDtcs() async {
    final resp = await elm.send('04', timeout: const Duration(seconds: 4));
    return resp.contains('44');
  }

  bool get _isCan {
    // ATDPN returns e.g. "A6" or "6"; protocols 6-9 are CAN.
    final p = protocol.replaceAll('A', '').trim();
    final n = int.tryParse(p, radix: 16);
    return n != null && n >= 6 && n <= 9;
  }

  /// Merges ELM multi-frame output ("0: ..", "1: ..") into one string per ECU.
  static List<String> _joinFrames(String resp) {
    final out = <String>[];
    final buf = StringBuffer();
    for (final raw in resp.split('\n')) {
      final line = raw.replaceAll(' ', '');
      final m = RegExp(r'^([0-9A-F]):(.*)$').firstMatch(line);
      if (m != null) {
        if (m.group(1) == '0' && buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
        buf.write(m.group(2));
      } else if (line.length <= 3) {
        continue; // multi-frame length header like "00A"
      } else {
        if (buf.isNotEmpty) {
          out.add(buf.toString());
          buf.clear();
        }
        out.add(line);
      }
    }
    if (buf.isNotEmpty) out.add(buf.toString());
    return out;
  }

  static String _short(Object e) {
    if (e is PlatformException) {
      final m = e.message ?? '';
      if (m.contains('permission')) return 'صلاحية ناقصة: $m';
      if (m.contains('Bluetooth is off')) return 'الـ Bluetooth مقفول';
      if (m.contains('read failed') || m.contains('timeout')) {
        return 'الجهاز مش بيرد. اتأكد إنه متركب والكونتاكت شغال';
      }
      return m.isEmpty ? e.code : m;
    }
    final s = e.toString();
    return s.length > 80 ? '${s.substring(0, 80)}…' : s;
  }

  @override
  void dispose() {
    _running = false;
    elm.dispose();
    _samples.close();
    super.dispose();
  }
}
