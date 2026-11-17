import 'package:flutter/foundation.dart';

import '../obd/obd_service.dart';
import '../obd/pids.dart';
import '../settings.dart';
import '../trips/trip_db.dart';
import '../trips/trip_recorder.dart';

class FillUp {
  final int? id;
  final DateTime date;
  final double litres;
  final double cost;
  final bool full;

  const FillUp({
    this.id,
    required this.date,
    required this.litres,
    required this.cost,
    required this.full,
  });

  factory FillUp.fromRow(Map<String, Object?> r) => FillUp(
        id: r['id'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
        litres: (r['litres'] as num).toDouble(),
        cost: (r['cost'] as num).toDouble(),
        full: (r['full'] as int) == 1,
      );
}

/// Real consumption between two full tanks, and what the app had computed.
class FillStat {
  final FillUp fill;
  final double km;
  final double litres;
  final double appLitres;
  const FillStat(this.fill, this.km, this.litres, this.appLitres);
  double? get l100 => km > 1 ? litres / km * 100 : null;
}

/// Fuel log: tracks how much is in the tank for cars that don't report
/// fuel level, and the real consumption from full-to-full fill-ups.
class FuelLogService extends ChangeNotifier {
  final TripDb db;
  final AppSettings settings;
  final ObdService obd;
  final TripRecorder trips;

  List<FillUp> fills = []; // newest first
  List<FillStat> stats = []; // newest first
  double? _litresAtLast; // tank content right after the last fill-up
  double _usedSinceLast = 0; // finished trips since then

  FuelLogService(this.db, this.settings, this.obd, this.trips) {
    trips.addListener(_onTrips);
    settings.addListener(_onSettings);
  }

  int _seenTrips = -1;
  int? _vehicle;
  void _onTrips() {
    if (trips.finishedCount != _seenTrips) {
      _seenTrips = trips.finishedCount;
      load();
    }
  }

  void _onSettings() {
    if (settings.vehicle.id != _vehicle) load();
  }

  int get _vid => settings.vehicle.id ?? 0;

  Future<void> load() async {
    _vehicle = settings.vehicle.id;
    final rows = await db.raw.query('fillups',
        where: 'vehicle_id = ?', whereArgs: [_vid], orderBy: 'date DESC');
    fills = rows.map(FillUp.fromRow).toList();
    await _recompute();
    notifyListeners();
  }

  Future<void> _recompute() async {
    final tank = settings.tankLiters;
    final asc = fills.reversed.toList();
    double? level;
    final st = <FillStat>[];
    FillUp? lastFull;
    var litresSinceFull = 0.0;
    for (var i = 0; i < asc.length; i++) {
      final f = asc[i];
      if (level != null && i > 0) {
        final used = (await db.tripTotals(_vid, asc[i - 1].date, f.date)).fuel;
        level = (level - used).clamp(0.0, tank);
      }
      if (f.full) {
        if (lastFull != null) {
          final t = await db.tripTotals(_vid, lastFull.date, f.date);
          st.add(FillStat(f, t.km, litresSinceFull + f.litres, t.fuel));
        }
        lastFull = f;
        litresSinceFull = 0;
        level = tank;
      } else {
        litresSinceFull += f.litres;
        level = level == null ? null : (level + f.litres).clamp(0.0, tank);
      }
    }
    _litresAtLast = level;
    _usedSinceLast = asc.isEmpty
        ? 0
        : (await db.tripTotals(_vid, asc.last.date)).fuel;
    stats = st.reversed.toList();
  }

  /// Litres in the tank: from the car's fuel-level sensor when available,
  /// otherwise estimated from the last full fill-up minus fuel used since.
  double? get litresNow {
    final pct = obd.values[Pids.fuelLevel];
    if (pct != null) return pct / 100 * settings.tankLiters;
    final base = _litresAtLast;
    if (base == null) return null;
    final active = trips.active ? trips.fuelL : 0.0;
    return (base - _usedSinceLast - active).clamp(0.0, settings.tankLiters);
  }

  bool get fromSensor => obd.values[Pids.fuelLevel] != null;

  /// Real L/100km averaged over the last full-to-full intervals.
  double? get realAvgL100 {
    final s = stats.where((x) => x.km > 20).take(3).toList();
    final km = s.fold<double>(0, (a, x) => a + x.km);
    final l = s.fold<double>(0, (a, x) => a + x.litres);
    return km > 20 ? l / km * 100 : null;
  }

  /// VE that would have made the app's litres match the pump's.
  double? get suggestedVe {
    final s = stats.where((x) => x.appLitres > 1 && x.km > 20).take(3).toList();
    if (s.isEmpty) return null;
    final real = s.fold<double>(0, (a, x) => a + x.litres);
    final app = s.fold<double>(0, (a, x) => a + x.appLitres);
    return (settings.volumetricEff * real / app).clamp(0.4, 1.2);
  }

  Future<void> add(FillUp f) async {
    await db.raw.insert('fillups', {
      'vehicle_id': _vid,
      'date': f.date.millisecondsSinceEpoch,
      'litres': f.litres,
      'cost': f.cost,
      'full': f.full ? 1 : 0,
    });
    await load();
  }

  Future<void> delete(int id) async {
    await db.raw.delete('fillups', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  @override
  void dispose() {
    trips.removeListener(_onTrips);
    settings.removeListener(_onSettings);
    super.dispose();
  }
}
