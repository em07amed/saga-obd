import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:latlong2/latlong.dart' show LatLng, Distance, LengthUnit;

import '../l10n.dart';
import '../obd/bt_channel.dart';
import '../obd/obd_service.dart';
import '../obd/pids.dart';
import '../settings.dart';

class SpeedCamera {
  final int id; // OSM node id, or negative for cameras the driver added
  final LatLng at;
  final double? limit;
  /// Direction of travel the camera watches (degrees), if known.
  final double? heading;
  bool farSaid = false;
  bool nearSaid = false;
  SpeedCamera(this.id, this.at, this.limit, {this.heading});
  bool get mine => id < 0;

  Map<String, dynamic> toJson() => {
        'id': id, 'lat': at.latitude, 'lon': at.longitude,
        'limit': limit, 'heading': heading,
      };
  static SpeedCamera fromJson(Map<String, dynamic> m) => SpeedCamera(
        (m['id'] as num).toInt(),
        LatLng((m['lat'] as num).toDouble(), (m['lon'] as num).toDouble()),
        (m['limit'] as num?)?.toDouble(),
        heading: (m['heading'] as num?)?.toDouble(),
      );
}

class _Road {
  final int id;
  final List<LatLng> pts;
  final double? fwd, back; // limit each way (null = unknown)
  final bool oneway;
  final String name;
  const _Road(this.id, this.pts, this.fwd, this.back, this.oneway, this.name);
}

/// Road speed limits and speed cameras from OpenStreetMap (Overpass API).
/// Data in Egypt is incomplete: a missing limit or camera means "unknown",
/// not "none", so the driver's manual limit stays the fallback.
class RoadService extends ChangeNotifier {
  final BtChannel bt;
  final AppSettings settings;
  final ObdService obd;
  RoadService(this.bt, this.settings, this.obd);

  static const _dist = Distance();
  static const _ua = {'User-Agent': 'CarOBD/1.0 (personal OBD dashboard)'};

  StreamSubscription<Position>? _gps;
  List<_Road> _roads = [];
  List<SpeedCamera> cameras = [];
  LatLng? _fetchedAt;
  DateTime _fetchedTime = DateTime.fromMillisecondsSinceEpoch(0);
  bool _fetching = false;

  /// Limit of the road under the car, if OSM (or the driver) knows it.
  double? roadLimit;
  String? roadName;
  int? roadId;
  DateTime? _roadSeen;
  int? _candidate; // a different road must win twice before we switch
  double _heading = double.nan;

  /// Driver's own corrections: road limits, added and hidden cameras.
  Map<int, double> _limitFix = {};
  List<SpeedCamera> _myCams = [];
  Set<int> _hidden = {};
  List<SpeedCamera> _osmCams = [];
  SharedPreferences? _p;
  LatLng? _last;

  Future<void> _loadFixes() async {
    final p = _p ??= await SharedPreferences.getInstance();
    try {
      final m = jsonDecode(p.getString('roadLimitFix') ?? '{}') as Map;
      _limitFix = {
        for (final e in m.entries)
          int.parse(e.key as String): (e.value as num).toDouble()
      };
      _myCams = [
        for (final c in jsonDecode(p.getString('myCameras') ?? '[]') as List)
          SpeedCamera.fromJson(Map<String, dynamic>.from(c as Map))
      ];
      _hidden = {
        for (final i in jsonDecode(p.getString('hiddenCameras') ?? '[]') as List)
          (i as num).toInt()
      };
    } catch (_) {}
    _mergeCams();
  }

  Future<void> _saveFixes() async {
    final p = _p ??= await SharedPreferences.getInstance();
    await p.setString('roadLimitFix',
        jsonEncode({for (final e in _limitFix.entries) '${e.key}': e.value}));
    await p.setString(
        'myCameras', jsonEncode([for (final c in _myCams) c.toJson()]));
    await p.setString('hiddenCameras', jsonEncode(_hidden.toList()));
  }

  void _mergeCams() {
    final old = {for (final c in cameras) c.id: c};
    cameras = [
      for (final c in [..._osmCams, ..._myCams])
        if (!_hidden.contains(c.id)) old[c.id] ?? c
    ];
  }

  /// Correct the limit of the road the car is on (saved on this phone).
  Future<bool> setLimitForThisRoad(double? limit) async {
    final id = roadId;
    if (id == null) return false;
    if (limit == null) {
      _limitFix.remove(id);
    } else {
      _limitFix[id] = limit;
    }
    await _saveFixes();
    if (_last != null) _matchRoad(_last!, force: true);
    notifyListeners();
    return true;
  }

  bool get thisRoadFixed => roadId != null && _limitFix.containsKey(roadId);

  /// "There's a radar here" — saved at the car's position and direction.
  Future<void> addCameraHere() async {
    final at = _last;
    if (at == null) return;
    _myCams.add(SpeedCamera(-DateTime.now().millisecondsSinceEpoch, at, null,
        heading: _heading.isNaN ? null : _heading));
    await _saveFixes();
    _mergeCams();
    notifyListeners();
  }

  /// "No radar here" — hides an OSM camera or deletes one the driver added.
  Future<void> removeCamera(SpeedCamera c) async {
    if (c.mine) {
      _myCams.removeWhere((m) => m.id == c.id);
    } else {
      _hidden.add(c.id);
    }
    await _saveFixes();
    _mergeCams();
    if (nextCamera?.id == c.id) {
      nextCamera = null;
      nextCameraM = null;
    }
    notifyListeners();
  }

  SpeedCamera? nextCamera;
  double? nextCameraM;

  /// Limit the alerts should use right now.
  double get effectiveLimit =>
      settings.autoRoadLimit && roadLimit != null
          ? roadLimit!
          : settings.speedLimit;
  bool get limitIsAuto => settings.autoRoadLimit && roadLimit != null;

  Future<void> start() async {
    if (_gps != null) return;
    await _loadFixes();
    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied ||
        perm == LocationPermission.deniedForever) {
      return;
    }
    _gps = Geolocator.getPositionStream(
      locationSettings: const LocationSettings(
        accuracy: LocationAccuracy.bestForNavigation,
        distanceFilter: 10,
      ),
    ).listen(_onFix, onError: (_) {});
  }

  void stop() {
    _gps?.cancel();
    _gps = null;
    roadLimit = null;
    nextCamera = null;
    notifyListeners();
  }

  void _onFix(Position p) {
    final at = LatLng(p.latitude, p.longitude);
    _last = at;
    if (p.speed > 2 && !p.heading.isNaN) _heading = p.heading;
    final f = _fetchedAt;
    if (f == null ||
        _m(f, at) > 600 ||
        DateTime.now().difference(_fetchedTime) > const Duration(minutes: 15)) {
      _fetch(at);
    }
    _matchRoad(at);
    _checkCameras(at, _heading, p.speed * 3.6);
    notifyListeners();
  }

  // ---------- data ----------

  Future<void> _fetch(LatLng at) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final q = '[out:json][timeout:25];('
          // All drivable roads, so a nearby tagged side street can't steal
          // the match from the unknown road we're actually on.
          'way(around:1000,${at.latitude},${at.longitude})["highway"~"^(motorway|trunk|primary|secondary|tertiary|unclassified|residential|living_street|service)(_link)?\$"];'
          'node(around:4000,${at.latitude},${at.longitude})["highway"="speed_camera"];'
          ');out geom tags;';
      final res = await http.post(
        Uri.parse('https://overpass-api.de/api/interpreter'),
        headers: _ua,
        body: {'data': q},
      );
      if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
      final els = (jsonDecode(res.body)['elements'] as List)
          .cast<Map<String, dynamic>>();
      final roads = <_Road>[];
      final cams = <SpeedCamera>[];
      for (final e in els) {
        final tags = Map<String, dynamic>.from(e['tags'] as Map? ?? const {});
        if (e['type'] == 'node') {
          cams.add(SpeedCamera(
            e['id'] as int,
            LatLng((e['lat'] as num).toDouble(), (e['lon'] as num).toDouble()),
            parseMaxspeed(tags['maxspeed'] as String?),
            heading: double.tryParse('${tags['direction'] ?? tags['camera:direction'] ?? ''}'),
          ));
        } else if (e['type'] == 'way' && e['geometry'] != null) {
          final all = parseMaxspeed(tags['maxspeed'] as String?);
          final ow = tags['oneway'] == 'yes' ||
              tags['junction'] == 'roundabout' ||
              '${tags['highway']}' == 'motorway';
          roads.add(_Road(
            e['id'] as int,
            [
              for (final g in e['geometry'] as List)
                LatLng((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()),
            ],
            parseMaxspeed(tags['maxspeed:forward'] as String?) ?? all,
            parseMaxspeed(tags['maxspeed:backward'] as String?) ?? all,
            ow,
            (tags['name:${Lang.code}'] ?? tags['name'] ?? '') as String,
          ));
        }
      }
      // Keep camera "already announced" state across refreshes.
      _osmCams = cams;
      _mergeCams();
      _roads = roads;
      _fetchedAt = at;
      _fetchedTime = DateTime.now();
    } catch (_) {
      // Offline or Overpass busy: keep the last data, retry on next move.
      _fetchedTime = DateTime.now().subtract(const Duration(minutes: 14));
    }
    _fetching = false;
  }

  /// "60", "60 km/h", "40 mph"; anything else (e.g. "EG:urban") → null.
  static double? parseMaxspeed(String? v) {
    if (v == null) return null;
    final m = RegExp(r'(\d+(?:\.\d+)?)').firstMatch(v);
    if (m == null) return null;
    final n = double.parse(m.group(1)!);
    return v.contains('mph') ? (n * 1.609).roundToDouble() : n;
  }

  // ---------- matching ----------

  /// Picks the road under the car: close to the centre line AND pointing the
  /// way we drive (so a parallel service road or a bridge above doesn't win),
  /// and only switches after the new road wins twice in a row.
  void _matchRoad(LatLng at, {bool force = false}) {
    final hasDir = !_heading.isNaN;
    _Road? best;
    var bestScore = double.infinity;
    var bestFwd = true;
    for (final r in _roads) {
      for (var i = 1; i < r.pts.length; i++) {
        final d = _toSegment(at, r.pts[i - 1], r.pts[i]);
        if (d > 22) continue;
        var score = d;
        var fwd = true;
        if (hasDir) {
          final seg = _bearing(r.pts[i - 1], r.pts[i]);
          final diff = (((_heading - seg) + 540) % 360 - 180).abs();
          fwd = diff <= 90;
          final off = fwd ? diff : 180 - diff;
          if (off > 35) continue; // crossing road, not ours
          if (r.oneway && !fwd) continue; // wrong way on a one-way
          score += off * 0.4;
        }
        if (score < bestScore) {
          bestScore = score;
          best = r;
          bestFwd = fwd;
        }
      }
    }
    if (best != null) {
      if (!force && roadId != null && best.id != roadId) {
        if (_candidate != best.id) {
          _candidate = best.id; // wait for one more fix to confirm
          return;
        }
      }
      _candidate = null;
      roadId = best.id;
      roadLimit = _limitFix[best.id] ?? (bestFwd ? best.fwd : best.back);
      roadName = best.name;
      _roadSeen = DateTime.now();
    } else if (_roadSeen == null ||
        DateTime.now().difference(_roadSeen!) > const Duration(seconds: 15)) {
      // Lost the road for a while: fall back to the manual limit.
      roadLimit = null;
      roadName = null;
      roadId = null;
    }
  }

  void _checkCameras(LatLng at, double heading, double gpsKmh) {
    if (!settings.cameraAlerts) {
      nextCamera = null;
      return;
    }
    final speed = obd.values[Pids.speed] ?? gpsKmh;
    final moving = speed > 10 && !heading.isNaN;
    SpeedCamera? best;
    var bestM = double.infinity;
    for (final c in cameras) {
      final d = _m(at, c.at);
      if (d > 1000) {
        c.farSaid = false; // re-arm once well past / away
        c.nearSaid = false;
        continue;
      }
      // Only cameras on the line we're driving: ahead of us and at most
      // ~35 m to the side (a cone alone catches parallel streets).
      if (moving) {
        final diff = ((_bearing(at, c.at) - heading + 540) % 360) - 180;
        if (diff.abs() > 60) continue;
        final side = d * math.sin(diff.abs() * math.pi / 180);
        if (side > 35) continue;
        // A camera that watches the other direction isn't ours.
        final ch = c.heading;
        if (ch != null) {
          final o = ((ch - heading + 540) % 360) - 180;
          if (o.abs() > 60) continue;
        }
      }
      if (d < bestM) {
        bestM = d;
        best = c;
      }
    }
    nextCamera = best;
    nextCameraM = best == null ? null : bestM;
    if (best == null || !moving) return;

    final limit = best.limit ?? effectiveLimit;
    if (!best.farSaid && bestM <= 600) {
      best.farSaid = true;
      _say(tr('رادار بعد ${(bestM / 50).round() * 50} متر. الحد ${limit.round()}.'));
    } else if (!best.nearSaid && bestM <= 200 && speed > limit) {
      best.nearSaid = true;
      _say(tr('هدّي. الرادار قدامك والحد ${limit.round()}.'));
    }
  }

  void _say(String s) {
    if (settings.voiceAlerts) {
      bt.speak(s, Lang.code, flush: true).catchError((_) {});
    } else {
      bt.beep().catchError((_) {});
    }
  }

  // ---------- geometry ----------

  static double _m(LatLng a, LatLng b) => _dist.as(LengthUnit.Meter, a, b);

  static double _bearing(LatLng a, LatLng b) {
    final p1 = a.latitude * math.pi / 180, p2 = b.latitude * math.pi / 180;
    final dl = (b.longitude - a.longitude) * math.pi / 180;
    final y = math.sin(dl) * math.cos(p2);
    final x = math.cos(p1) * math.sin(p2) -
        math.sin(p1) * math.cos(p2) * math.cos(dl);
    return (math.atan2(y, x) * 180 / math.pi + 360) % 360;
  }

  /// Metres from [p] to segment [a]-[b] (local flat approximation).
  static double _toSegment(LatLng p, LatLng a, LatLng b) {
    const r = 6371000.0;
    final k = math.cos(p.latitude * math.pi / 180);
    double x(LatLng q) => q.longitude * math.pi / 180 * r * k;
    double y(LatLng q) => q.latitude * math.pi / 180 * r;
    final px = x(p), py = y(p), ax = x(a), ay = y(a), bx = x(b), by = y(b);
    final dx = bx - ax, dy = by - ay;
    final len2 = dx * dx + dy * dy;
    var t = len2 == 0 ? 0.0 : ((px - ax) * dx + (py - ay) * dy) / len2;
    t = t.clamp(0.0, 1.0);
    final cx = ax + t * dx, cy = ay + t * dy;
    return math.sqrt((px - cx) * (px - cx) + (py - cy) * (py - cy));
  }

  @override
  void dispose() {
    _gps?.cancel();
    super.dispose();
  }
}
