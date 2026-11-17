import 'package:flutter/services.dart';

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
}
