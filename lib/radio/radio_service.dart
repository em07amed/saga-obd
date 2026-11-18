import 'dart:convert';

import 'package:audio_session/audio_session.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:just_audio/just_audio.dart';
import 'package:shared_preferences/shared_preferences.dart';

class Station {
  final String id;
  final String name;
  final String url;
  final String favicon;
  final String tags;
  final String country;
  const Station(this.id, this.name, this.url, this.favicon, this.tags,
      this.country);

  factory Station.fromJson(Map<String, dynamic> j) => Station(
        j['stationuuid'] as String? ?? j['id'] as String? ?? '',
        (j['name'] as String? ?? '').trim(),
        (j['url_resolved'] as String?)?.isNotEmpty == true
            ? j['url_resolved'] as String
            : j['url'] as String? ?? '',
        j['favicon'] as String? ?? '',
        j['tags'] as String? ?? '',
        j['countrycode'] as String? ?? j['country'] as String? ?? '',
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'url_resolved': url,
        'favicon': favicon,
        'tags': tags,
        'country': country,
      };
}

/// Internet radio from the free, community-run Radio Browser directory.
class RadioService extends ChangeNotifier {
  final _player = AudioPlayer();
  late SharedPreferences _p;

  static const _hosts = [
    'de1.api.radio-browser.info',
    'nl1.api.radio-browser.info',
    'at1.api.radio-browser.info',
  ];
  static const _ua = {'User-Agent': 'CarOBD/1.0'};

  Station? current;
  bool loading = false;
  String? error;
  List<Station> favourites = [];

  bool get playing => _player.playing && current != null;

  Future<void> init() async {
    _p = await SharedPreferences.getInstance();
    final raw = _p.getStringList('radioFavs') ?? const [];
    favourites = [
      for (final s in raw)
        Station.fromJson(Map<String, dynamic>.from(jsonDecode(s) as Map)),
    ];
    final session = await AudioSession.instance;
    await session.configure(const AudioSessionConfiguration.music());
    _player.playerStateStream.listen((_) => notifyListeners());
  }

  Future<List<Station>> _get(String path, Map<String, String> q) async {
    Object? last;
    for (final h in _hosts) {
      try {
        final res = await http
            .get(Uri.https(h, path, q), headers: _ua)
            .timeout(const Duration(seconds: 8));
        if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
        return [
          for (final e in jsonDecode(res.body) as List)
            Station.fromJson(Map<String, dynamic>.from(e as Map)),
        ].where((s) => s.url.isNotEmpty && s.name.isNotEmpty).toList();
      } catch (e) {
        last = e;
      }
    }
    throw last ?? Exception('no server');
  }

  /// Most popular working stations in Egypt.
  Future<List<Station>> egypt() => _get('/json/stations/bycountrycodeexact/EG', {
        'hidebroken': 'true',
        'order': 'clickcount',
        'reverse': 'true',
        'limit': '80',
      });

  Future<List<Station>> search(String name) => _get('/json/stations/search', {
        'name': name,
        'hidebroken': 'true',
        'order': 'clickcount',
        'reverse': 'true',
        'limit': '60',
      });

  Future<void> play(Station s) async {
    current = s;
    loading = true;
    error = null;
    notifyListeners();
    try {
      await _player.setUrl(s.url);
      _player.play(); // don't await: completes only when playback stops
    } catch (_) {
      error = 'المحطة دي مش شغالة دلوقتي';
    }
    loading = false;
    notifyListeners();
  }

  Future<void> toggle() async {
    if (current == null) return;
    if (_player.playing) {
      await _player.pause();
    } else {
      // Live streams: reconnect instead of resuming stale buffer.
      await play(current!);
    }
    notifyListeners();
  }

  Future<void> stop() async {
    await _player.stop();
    notifyListeners();
  }

  bool isFav(Station s) => favourites.any((f) => f.id == s.id);

  Future<void> toggleFav(Station s) async {
    if (isFav(s)) {
      favourites = favourites.where((f) => f.id != s.id).toList();
    } else {
      favourites = [...favourites, s];
    }
    await _p.setStringList(
        'radioFavs', [for (final f in favourites) jsonEncode(f.toJson())]);
    notifyListeners();
  }

  @override
  void dispose() {
    _player.dispose();
    super.dispose();
  }
}
