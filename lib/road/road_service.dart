import 'dart:async';
import 'dart:convert';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng, Distance, LengthUnit;

import '../l10n.dart';
import '../obd/bt_channel.dart';
import '../obd/obd_service.dart';
import '../obd/pids.dart';
import '../settings.dart';

class SpeedCamera {
  final int id;
  final LatLng at;
  final double? limit;
  bool farSaid = false;
  bool nearSaid = false;
  SpeedCamera(this.id, this.at, this.limit);
}

class _Road {
  final List<LatLng> pts;
  final double limit;
  final String name;
  const _Road(this.pts, this.limit, this.name);
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

  /// Limit of the road under the car, if OSM knows it.
  double? roadLimit;
  String? roadName;
  DateTime? _roadSeen;

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
    final f = _fetchedAt;
    if (f == null ||
        _m(f, at) > 1200 ||
        DateTime.now().difference(_fetchedTime) > const Duration(minutes: 15)) {
      _fetch(at);
    }
    _matchRoad(at);
    _checkCameras(at, p.heading, p.speed * 3.6);
    notifyListeners();
  }

  // ---------- data ----------

  Future<void> _fetch(LatLng at) async {
    if (_fetching) return;
    _fetching = true;
    try {
      final q = '[out:json][timeout:25];('
          'way(around:2000,${at.latitude},${at.longitude})["highway"]["maxspeed"];'
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
          ));
        } else if (e['type'] == 'way' && e['geometry'] != null) {
          final lim = parseMaxspeed(tags['maxspeed'] as String?);
          if (lim == null) continue;
          roads.add(_Road([
            for (final g in e['geometry'] as List)
              LatLng((g['lat'] as num).toDouble(), (g['lon'] as num).toDouble()),
          ], lim, (tags['name:${Lang.code}'] ?? tags['name'] ?? '') as String));
        }
      }
      // Keep camera "already announced" state across refreshes.
      final old = {for (final c in cameras) c.id: c};
      cameras = [for (final c in cams) old[c.id] ?? c];
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

  void _matchRoad(LatLng at) {
    _Road? best;
    var bestM = 25.0; // must be within 25 m of the road centre line
    for (final r in _roads) {
      for (var i = 1; i < r.pts.length; i++) {
        final d = _toSegment(at, r.pts[i - 1], r.pts[i]);
        if (d < bestM) {
          bestM = d;
          best = r;
        }
      }
    }
    if (best != null) {
      roadLimit = best.limit;
      roadName = best.name;
      _roadSeen = DateTime.now();
    } else if (_roadSeen == null ||
        DateTime.now().difference(_roadSeen!) > const Duration(seconds: 15)) {
      // Lost the road for a while: fall back to the manual limit.
      roadLimit = null;
      roadName = null;
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
      // Only cameras roughly ahead of the direction of travel.
      if (moving) {
        final diff = ((_bearing(at, c.at) - heading + 540) % 360) - 180;
        if (diff.abs() > 45) continue;
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
