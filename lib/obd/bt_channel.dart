import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

class CallInfo {
  final String state; // idle | ringing | offhook
  final String? number;
  final String? name;
  final bool incoming;
  final DateTime? since;
  final bool speaker;
  final bool muted;
  const CallInfo(this.state, this.number, this.name, this.incoming, this.since,
      this.speaker, this.muted);
  const CallInfo.idle()
      : state = 'idle',
        number = null,
        name = null,
        incoming = false,
        since = null,
        speaker = false,
        muted = false;
  factory CallInfo.fromMap(Map<String, dynamic> m) {
    final s = (m['since'] as num?)?.toInt() ?? 0;
    return CallInfo(
      m['state'] as String? ?? 'idle',
      m['number'] as String?,
      m['name'] as String?,
      m['incoming'] == true,
      s > 0 ? DateTime.fromMillisecondsSinceEpoch(s) : null,
      m['speaker'] == true,
      m['muted'] == true,
    );
  }
  bool get idle => state == 'idle';
  bool get ringing => state == 'ringing';
  String get who => name ?? number ?? '';
}

class BtDevice {
  final String name;
  final String address;
  const BtDevice(this.name, this.address);
}

/// Thin Dart wrapper over the native RFCOMM bridge in MainActivity.kt.
class BtChannel {
  static const _method = MethodChannel('obd/bt');
  static const _events = EventChannel('obd/bt/events');
  static const disconnectedMarker = '\u0000DISCONNECTED';

  /// True while the app is shown as a floating Picture-in-Picture window.
  static final pip = ValueNotifier<bool>(false);

  /// Current phone call (idle when there is none).
  static final phoneCall = ValueNotifier<CallInfo>(const CallInfo.idle());

  BtChannel() {
    _method.setMethodCallHandler((call) async {
      if (call.method == 'pip') pip.value = call.arguments == true;
      if (call.method == 'callState') {
        phoneCall.value =
            CallInfo.fromMap(Map<String, dynamic>.from(call.arguments as Map));
      }
    });
  }

  /// Float over other apps when leaving (only while drive mode is open).
  Future<void> setPipAllowed(bool v) =>
      _method.invokeMethod('setPipAllowed', {'allowed': v});

  /// Google Maps navigation to [lat],[lng] (or just Maps when null).
  Future<bool> openGoogleMaps([double? lat, double? lng]) async =>
      (await _method.invokeMethod<bool>(
          'openGoogleMaps', {'lat': lat, 'lng': lng})) ??
      false;

  /// Raw text chunks coming from the adapter (broadcast).
  final Stream<String> data =
      _events.receiveBroadcastStream().map((e) => e as String);

  Future<bool> isEnabled() async =>
      (await _method.invokeMethod<bool>('isEnabled')) ?? false;

  Future<List<BtDevice>> bondedDevices() async {
    final list = await _method.invokeListMethod<dynamic>('bondedDevices') ?? [];
    return list.map((e) {
      final m = Map<String, dynamic>.from(e as Map);
      return BtDevice(m['name'] as String, m['address'] as String);
    }).toList();
  }

  Future<void> connect(String address) =>
      _method.invokeMethod('connect', {'address': address});

  Future<void> write(String data) =>
      _method.invokeMethod('write', {'data': data});

  Future<void> disconnect() => _method.invokeMethod('disconnect');

  /// Foreground service that keeps logging alive with the screen off.
  Future<void> startKeepAlive(String title, String text) => _method
      .invokeMethod('startKeepAlive', {'title': title, 'text': text});

  Future<void> stopKeepAlive() => _method.invokeMethod('stopKeepAlive');

  /// One voice phrase via the system recognizer. '' if nothing was heard,
  /// null if no recognizer is available.
  Future<String?> listen(String lang) =>
      _method.invokeMethod<String>('listen', {'lang': lang});

  /// Phone battery percent.
  Future<int?> battery() => _method.invokeMethod<int>('battery');

  Future<bool> answerCall() async =>
      await _method.invokeMethod<bool>('callAnswer') ?? false;
  Future<bool> endCall() async =>
      await _method.invokeMethod<bool>('callEnd') ?? false;
  Future<bool> setSpeaker(bool on) async =>
      await _method.invokeMethod<bool>('callSpeaker', {'on': on}) ?? on;
  Future<bool> setMute(bool on) async =>
      await _method.invokeMethod<bool>('callMute', {'on': on}) ?? on;
  /// Ask Android to let us see the caller's number (caller-ID role).
  Future<bool> requestCallerId() async =>
      await _method.invokeMethod<bool>('callerIdRole') ?? false;
  Future<void> refreshCall() async {
    final m = await _method.invokeMethod<Map>('callCurrent');
    if (m != null) phoneCall.value = CallInfo.fromMap(Map<String, dynamic>.from(m));
  }

  /// Opens another app: maps | dialer | music | assistant.
  Future<bool> launch(String kind) async =>
      (await _method.invokeMethod<bool>('launch', {'kind': kind})) ?? false;

  /// Short warning tone without any spoken message.
  Future<void> beep() => _method.invokeMethod('beep');

  /// Speaks [text] with the phone's text-to-speech engine.
  /// [flush] interrupts anything still being spoken (for fast repeats).
  Future<void> speak(String text, String lang, {bool flush = false}) =>
      _method.invokeMethod(
          'speak', {'text': text, 'lang': lang, 'flush': flush});

  /// High-priority notification (heads-up, sound, vibration).
  Future<void> notify(String title, String text, {bool sound = true}) =>
      _method.invokeMethod(
          'notify', {'title': title, 'text': text, 'sound': sound});
}
