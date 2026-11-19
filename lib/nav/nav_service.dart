import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart' show IconData, Icons;
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng, Distance, LengthUnit;

import '../l10n.dart';
import '../obd/bt_channel.dart';

/// A place found by search (OpenStreetMap Nominatim).
class Place {
  final String name;
  final String detail;
  final LatLng at;
  const Place(this.name, this.detail, this.at);
}

/// One OSRM step; [atM] is where its maneuver sits along the route (m).
class NavStep {
  final String type;
  final String modifier;
  final int exit;
  final String road;
  final LatLng at;
  double atM = 0;
  bool farSaid = false;
  bool nearSaid = false;
  NavStep(this.type, this.modifier, this.exit, this.road, this.at);

  bool get isArrive => type == 'arrive';

  String get text {
    String act;
    if (type == 'arrive') return 'وصلت لوجهتك';
    if (type == 'depart') {
      act = 'ابدأ';
    } else if (type == 'roundabout' || type == 'rotary') {
      act = exit > 0 ? 'في الدوران اطلع من المخرج رقم $exit' : 'ادخل الدوران';
    } else if (type == 'on ramp') {
      act = 'اطلع على الطلعة';
    } else if (type == 'off ramp') {
      act = 'انزل من المخرج';
    } else {
      act = switch (modifier) {
        'left' => 'لف شمال',
        'right' => 'لف يمين',
        'slight left' => 'خليك شمال',
        'slight right' => 'خليك يمين',
        'sharp left' => 'لف شمال حاد',
        'sharp right' => 'لف يمين حاد',
        'uturn' => 'اعمل يو-تيرن',
        _ => 'كمّل على طول',
      };
    }
    return road.isEmpty ? act : '$act: $road';
  }

  IconData get icon {
    if (type == 'arrive') return Icons.flag;
    if (type == 'roundabout' || type == 'rotary') return Icons.roundabout_right;
    return switch (modifier) {
      'left' => Icons.turn_left,
      'right' => Icons.turn_right,
      'slight left' => Icons.turn_slight_left,
      'slight right' => Icons.turn_slight_right,
      'sharp left' => Icons.turn_sharp_left,
      'sharp right' => Icons.turn_sharp_right,
      'uturn' => Icons.u_turn_left,
      _ => Icons.straight,
    };
  }
}

/// Turn-by-turn navigation on free OpenStreetMap services:
/// Nominatim for search, the public OSRM server for driving routes.
class NavService extends ChangeNotifier {
  final BtChannel bt;
  NavService(this.bt);

  static const _ua = {'User-Agent': 'CarOBD/1.0 (+https://github.com/em07amed/saga-obd)'};
  static const _dist = Distance();

  Place? destination;
  List<LatLng> route = [];
  List<double> _cum = []; // cumulative metres along [route]
  List<NavStep> steps = [];
  double totalM = 0;
  double totalS = 0;
  double progressM = 0;
  int _idx = 0;
  int _offCount = 0;
  DateTime _lastRoute = DateTime.fromMillisecondsSinceEpoch(0);
  bool routing = false;
  String? error;

  bool get active => destination != null && route.isNotEmpty;
  double get remainingM => math.max(0, totalM - progressM);
  Duration get remaining => Duration(
      seconds: totalM <= 0 ? 0 : (totalS * remainingM / totalM).round());

  NavStep? get next {
    for (final s in steps) {
      if (s.atM > progressM + 5 || s.isArrive) return s;
    }
    return null;
  }

  double get toNextM => next == null ? 0 : math.max(0, next!.atM - progressM);

  // ---------- search ----------

  /// Place search. Tries several free geocoders in turn, so one being down
  /// or blocking us doesn't break search: Nominatim → Photon → Esri.
  Future<List<Place>> search(String q, LatLng? near) async {
    Object? lastError;
    for (final src in [_nominatim, _photon, _esri]) {
      try {
        final r = await src(q, near).timeout(const Duration(seconds: 8));
        if (r.isNotEmpty) return _sortByDistance(r, near);
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    return [];
  }

  static List<Place> _sortByDistance(List<Place> r, LatLng? near) {
    if (near == null) return r;
    const d = Distance();
    return [...r]..sort((a, b) => d
        .as(LengthUnit.Meter, near, a.at)
        .compareTo(d.as(LengthUnit.Meter, near, b.at)));
  }

  Future<List<Place>> _nominatim(String q, LatLng? near) async {
    final params = {
      'q': q,
      'format': 'json',
      'limit': '8',
      'accept-language': Lang.code,
      if (near != null)
        'viewbox': '${near.longitude - 0.6},${near.latitude + 0.6},'
            '${near.longitude + 0.6},${near.latitude - 0.6}',
    };
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
    final res = await http.get(uri, headers: _ua);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final list = jsonDecode(res.body) as List;
    return [
      for (final e in list)
        Place(
          (e['display_name'] as String).split(',').first,
          (e['display_name'] as String).split(',').skip(1).take(3).join(','),
          LatLng(double.parse(e['lat'] as String),
              double.parse(e['lon'] as String)),
        ),
    ];
  }

  Future<List<Place>> _photon(String q, LatLng? near) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': q,
      'limit': '8',
      if (near != null) 'lat': '${near.latitude}',
      if (near != null) 'lon': '${near.longitude}',
    });
    final res = await http.get(uri, headers: _ua);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final feats = (jsonDecode(res.body)['features'] as List?) ?? const [];
    return [
      for (final f in feats)
        if (f['geometry']?['coordinates'] is List)
          Place(
            '${f['properties']?['name'] ?? f['properties']?['street'] ?? q}',
            [
              f['properties']?['street'],
              f['properties']?['city'] ?? f['properties']?['district'],
              f['properties']?['state'],
            ].whereType<String>().join(', '),
            LatLng((f['geometry']['coordinates'][1] as num).toDouble(),
                (f['geometry']['coordinates'][0] as num).toDouble()),
          ),
    ];
  }

  Future<List<Place>> _esri(String q, LatLng? near) async {
    final uri = Uri.https('geocode.arcgis.com',
        '/arcgis/rest/services/World/GeocodeServer/findAddressCandidates', {
      'SingleLine': q,
      'f': 'json',
      'maxLocations': '8',
      'outFields': 'PlaceName,Place_addr',
      'langCode': Lang.code,
      if (near != null) 'location': '${near.longitude},${near.latitude}',
    });
    final res = await http.get(uri, headers: _ua);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final c = (jsonDecode(res.body)['candidates'] as List?) ?? const [];
    return [
      for (final e in c)
        Place(
          '${e['attributes']?['PlaceName'] ?? ''}'.isNotEmpty
              ? '${e['attributes']['PlaceName']}'
              : '${e['address']}'.split(',').first,
          '${e['attributes']?['Place_addr'] ?? e['address'] ?? ''}',
          LatLng((e['location']['y'] as num).toDouble(),
              (e['location']['x'] as num).toDouble()),
        ),
    ];
  }

  // ---------- routing ----------

  Future<void> start(Place to, LatLng from) async {
    destination = to;
    await _route(from);
    if (active) {
      _say(tr('يلا بينا. المسافة ${_fmtDist(totalM)}.'));
    }
  }

  void stop() {
    destination = null;
    route = [];
    steps = [];
    error = null;
    notifyListeners();
  }

  Future<void> _route(LatLng from) async {
    final to = destination;
    if (to == null) return;
    routing = true;
    error = null;
    _lastRoute = DateTime.now();
    notifyListeners();
    try {
      final uri = Uri.parse('https://router.project-osrm.org/route/v1/driving/'
          '${from.longitude},${from.latitude};${to.at.longitude},${to.at.latitude}'
          '?overview=full&geometries=geojson&steps=true');
      final res = await http.get(uri, headers: _ua);
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final j = jsonDecode(res.body) as Map<String, dynamic>;
      final r = (j['routes'] as List).first as Map<String, dynamic>;
      route = [
        for (final c in (r['geometry']['coordinates'] as List))
          LatLng((c[1] as num).toDouble(), (c[0] as num).toDouble()),
      ];
      _cum = [0];
      for (var i = 1; i < route.length; i++) {
        _cum.add(_cum.last + _m(route[i - 1], route[i]));
      }
      totalM = (r['distance'] as num).toDouble();
      totalS = (r['duration'] as num).toDouble();
      steps = [];
      for (final leg in r['legs'] as List) {
        for (final s in leg['steps'] as List) {
          final m = s['maneuver'] as Map<String, dynamic>;
          final loc = m['location'] as List;
          steps.add(NavStep(
            m['type'] as String? ?? '',
            m['modifier'] as String? ?? '',
            (m['exit'] as num?)?.toInt() ?? 0,
            s['name'] as String? ?? '',
            LatLng((loc[1] as num).toDouble(), (loc[0] as num).toDouble()),
          ));
        }
      }
      for (final s in steps) {
        s.atM = _cum[_nearestIndex(s.at, 0, route.length)];
      }
      _idx = 0;
      progressM = 0;
      _offCount = 0;
    } catch (e) {
      error = tr('مش قادر أجيب الطريق. اتأكد من النت.');
    }
    routing = false;
    notifyListeners();
  }

  // ---------- live guidance ----------

  /// Feed every GPS fix while navigating.
  void update(LatLng at) {
    if (!active || routing) return;
    // Search a window ahead of the last match so the position never jumps
    // back to an earlier part of a route that loops near itself.
    final from = math.max(0, _idx - 5);
    final to = math.min(route.length, _idx + 300);
    final i = _nearestIndex(at, from, to);
    final off = _m(at, route[i]);
    if (off > 60) {
      _offCount++;
      if (_offCount >= 3 &&
          DateTime.now().difference(_lastRoute) > const Duration(seconds: 15)) {
        _say(tr('بعيد عن الطريق. بحسب طريق جديد.'));
        _route(at);
      }
      return;
    }
    _offCount = 0;
    _idx = i;
    progressM = _cum[i];

    final n = next;
    if (n != null) {
      final d = n.atM - progressM;
      if (n.isArrive && d < 30) {
        _say(tr('وصلت لوجهتك'));
        stop();
        return;
      }
      if (!n.farSaid && d < 400 && d > 120) {
        n.farSaid = true;
        _say(tr('بعد ${_fmtDist(d)}، ${n.text}'));
      } else if (!n.nearSaid && d <= 50) {
        n.nearSaid = true;
        n.farSaid = true;
        _say(tr(n.text));
      }
    }
    notifyListeners();
  }

  void _say(String s) => bt.speak(s, Lang.code).catchError((_) {});

  static double _m(LatLng a, LatLng b) => _dist.as(LengthUnit.Meter, a, b);

  int _nearestIndex(LatLng p, int from, int to) {
    var best = from;
    var bestM = double.infinity;
    for (var i = from; i < to; i++) {
      final m = _m(p, route[i]);
      if (m < bestM) {
        bestM = m;
        best = i;
      }
    }
    return best;
  }

  static String _fmtDist(double m) => m >= 1000
      ? '${(m / 1000).toStringAsFixed(m >= 10000 ? 0 : 1)} كم'
      : '${(m / 10).round() * 10} متر';

  static String fmtDist(double m) => tr(_fmtDist(m));
}
