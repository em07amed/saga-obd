import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

import '../obd/obd_service.dart';
import '../settings.dart';
import 'trip_db.dart';

/// Starts a trip when the engine runs, ends it after the engine has been off
/// (or the adapter disconnected) for a while. Integrates distance and fuel.
class TripRecorder extends ChangeNotifier {
  final ObdService obd;
  final TripDb db;
  final AppSettings settings;

  static const _endAfter = Duration(seconds: 90);
  static const _maxDt = 5.0; // seconds; ignore gaps longer than this
  static const _persistEvery = Duration(seconds: 5);

  StreamSubscription<ObdSample>? _sub;
  StreamSubscription<Position>? _gpsSub;
  Timer? _offTimer;

  int? tripId;
  DateTime? startedAt;
  double obdKm = 0;
  double gpsKm = 0;
  double fuelL = 0;
  double maxSpeed = 0;
  double idleSec = 0;
  double maxCoolant = 0;

  DateTime? _lastTs;
  DateTime? _lastStoredSample;
  DateTime _lastPersist = DateTime.fromMillisecondsSinceEpoch(0);
  Position? _lastPos;
  final List<TripSample> _pending = [];
  bool _starting = false;

  /// Bumped whenever a trip is finished so lists can refresh.
  int finishedCount = 0;

  TripRecorder(this.obd, this.db, this.settings) {
    _sub = obd.samples.listen(_onSample);
    obd.addListener(_onObdState);
  }

  bool get active => tripId != null;
  double get distanceKm => gpsKm > 0.3 ? gpsKm : obdKm;
  double? get avgL100 => distanceKm > 0.5 ? fuelL / distanceKm * 100 : null;

  void _onObdState() {
    if (obd.state == ObdState.disconnected && active) _scheduleEnd();
  }

  Future<void> _onSample(ObdSample s) async {
    final running = (s.rpm ?? 0.0) > 300;

    if (running) {
      _offTimer?.cancel();
      _offTimer = null;
      if (!active) {
        if (_starting) return;
        _starting = true;
        try {
          await _start(s.ts);
        } finally {
          _starting = false;
        }
      }
    } else if (active) {
      _scheduleEnd();
    }
    if (!active) return;

    final last = _lastTs;
    _lastTs = s.ts;
    if (last != null) {
      final dt = s.ts.difference(last).inMilliseconds / 1000.0;
      if (dt > 0 && dt <= _maxDt) {
        final v = s.speed ?? 0.0;
        obdKm += v * dt / 3600;
        fuelL += (s.fuelRateLh ?? 0.0) * dt / 3600;
        if (v < 1 && running) idleSec += dt;
      }
    }
    maxSpeed = math.max(maxSpeed, s.speed ?? 0.0);
    maxCoolant = math.max(maxCoolant, s.coolant ?? 0.0);

    // Store at ~1 Hz.
    if (_lastStoredSample == null ||
        s.ts.difference(_lastStoredSample!).inMilliseconds >= 1000) {
      _lastStoredSample = s.ts;
      _pending.add(TripSample(s.ts, s.speed, s.rpm, s.coolant, s.fuelRateLh,
          _lastPos?.latitude, _lastPos?.longitude));
    }
    if (s.ts.difference(_lastPersist) >= _persistEvery) {
      _lastPersist = s.ts;
      await _persist();
    }
    notifyListeners();
  }

  Future<void> _start(DateTime at) async {
    tripId = await db.startTrip(at, settings.fuelPrice, settings.vehicle.id ?? 0);
    startedAt = at;
    obdKm = 0;
    gpsKm = 0;
    fuelL = 0;
    maxSpeed = 0;
    idleSec = 0;
    maxCoolant = 0;
    _lastTs = null;
    _lastStoredSample = null;
    _lastPos = null;
    _pending.clear();
    await _startGps();
    notifyListeners();
  }

  Future<void> _startGps() async {
    try {
      if (!await Geolocator.isLocationServiceEnabled()) return;
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return; // asked once at app start; don't nag while driving
      }
      _gpsSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 10,
        ),
      ).listen((pos) {
        if (pos.accuracy > 30) return; // skip poor fixes
        final prev = _lastPos;
        if (prev != null) {
          gpsKm += Geolocator.distanceBetween(
                  prev.latitude, prev.longitude, pos.latitude, pos.longitude) /
              1000;
        }
        _lastPos = pos;
      });
    } catch (_) {
      // GPS is optional.
    }
  }

  void _scheduleEnd() {
    _offTimer ??= Timer(_endAfter, () {
      _offTimer = null;
      unawaited(_end());
    });
  }

  Future<void> _persist() async {
    final id = tripId;
    if (id == null) return;
    if (_pending.isNotEmpty) {
      final copy = List<TripSample>.from(_pending);
      _pending.clear();
      await db.insertSamples(id, copy);
    }
    await db.updateTrip(id, {
      'obd_km': obdKm,
      'gps_km': gpsKm,
      'fuel_l': fuelL,
      'max_speed': maxSpeed,
      'idle_sec': idleSec.round(),
      'max_coolant': maxCoolant,
    });
  }

  Future<void> _end() async {
    final id = tripId;
    if (id == null) return;
    await _persist();
    await _gpsSub?.cancel();
    _gpsSub = null;
    // Throw away "trips" that were just the engine idling in the garage.
    if (distanceKm < 0.1) {
      await db.deleteTrip(id);
    } else {
      await db.updateTrip(
          id, {'ended_at': (_lastTs ?? DateTime.now()).millisecondsSinceEpoch});
    }
    tripId = null;
    startedAt = null;
    finishedCount++;
    notifyListeners();
  }

  /// Ends the current trip immediately (e.g. from the UI).
  Future<void> endNow() async {
    _offTimer?.cancel();
    _offTimer = null;
    await _end();
  }

  @override
  void dispose() {
    _sub?.cancel();
    _gpsSub?.cancel();
    _offTimer?.cancel();
    obd.removeListener(_onObdState);
    super.dispose();
  }
}
