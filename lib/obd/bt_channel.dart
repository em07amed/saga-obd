import 'dart:typed_data';

import 'package:flutter/services.dart';

class NowPlaying {
  final bool access;
  final String? title;
  final String? artist;
  final String? app;
  final bool playing;
  final Uint8List? art;
  const NowPlaying(
      this.access, this.title, this.artist, this.app, this.playing, this.art);
}

class Contact {
  final String name;
  final String number;
  final bool starred;
  const Contact(this.name, this.number, this.starred);
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

  /// What the phone is playing (needs notification access).
  Future<NowPlaying> nowPlaying() async {
    final m = Map<String, dynamic>.from(
        await _method.invokeMethod<Map>('nowPlaying') ?? const {});
    return NowPlaying(
      m['access'] == true,
      m['title'] as String?,
      m['artist'] as String?,
      m['app'] as String?,
      m['playing'] == true,
      m['art'] as Uint8List?,
    );
  }

  /// play_pause | next | prev on the active player's media session.
  Future<void> mediaControl(String action) =>
      _method.invokeMethod('mediaControl', {'action': action});

  Future<void> openNotificationAccess() =>
      _method.invokeMethod('openNotificationAccess');

  Future<List<Contact>> contacts() async {
    final list = await _method.invokeListMethod<dynamic>('contacts') ?? [];
    return [
      for (final e in list)
        (() {
          final m = Map<String, dynamic>.from(e as Map);
          return Contact(m['name'] as String, m['number'] as String,
              m['starred'] == true);
        })(),
    ];
  }

  Future<void> call(String number) =>
      _method.invokeMethod('call', {'number': number});

  /// Media control for the phone's current player: play_pause | next | prev.
  Future<void> mediaKey(String key) =>
      _method.invokeMethod('mediaKey', {'key': key});

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
