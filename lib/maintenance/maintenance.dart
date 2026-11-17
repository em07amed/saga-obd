import 'package:flutter/foundation.dart';

import '../obd/obd_service.dart';
import '../obd/pids.dart';
import '../settings.dart';
import '../trips/trip_db.dart';
import '../trips/trip_recorder.dart';

/// Common service types; the user can also type their own.
const maintenanceTypes = [
  'تغيير زيت الموتور',
  'فلتر زيت',
  'فلتر هواء',
  'فلتر تكييف',
  'فلتر بنزين',
  'بوجيهات',
  'تيل فرامل أمامي',
  'تيل فرامل خلفي',
  'زيت فتيس',
  'مياه الردياتير',
  'سير الكاتينة',
  'بطارية',
  'كاوتش',
  'ترصيص وضبط زوايا',
  'أخرى',
];

class MaintenanceEntry {
  final int? id;
  final DateTime date;
  final double? km;
  final String type;
  final double cost;
  final String? notes;
  final double? nextKm;
  final DateTime? nextDate;

  const MaintenanceEntry({
    this.id,
    required this.date,
    required this.km,
    required this.type,
    required this.cost,
    this.notes,
    this.nextKm,
    this.nextDate,
  });

  Map<String, Object?> toRow() => {
        'date': date.millisecondsSinceEpoch,
        'km': km,
        'type': type,
        'cost': cost,
        'notes': notes,
        'next_km': nextKm,
        'next_date': nextDate?.millisecondsSinceEpoch,
      };

  factory MaintenanceEntry.fromRow(Map<String, Object?> r) => MaintenanceEntry(
        id: r['id'] as int,
        date: DateTime.fromMillisecondsSinceEpoch(r['date'] as int),
        km: (r['km'] as num?)?.toDouble(),
        type: r['type'] as String,
        cost: (r['cost'] as num).toDouble(),
        notes: r['notes'] as String?,
        nextKm: (r['next_km'] as num?)?.toDouble(),
        nextDate: r['next_date'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['next_date'] as int),
      );
}

/// An upcoming service derived from the latest entry of each type.
class DueItem {
  final MaintenanceEntry entry;
  final double? kmLeft;
  final int? daysLeft;
  const DueItem(this.entry, this.kmLeft, this.daysLeft);

  bool get overdue => (kmLeft ?? 1) <= 0 || (daysLeft ?? 1) <= 0;
  bool get soon =>
      !overdue && ((kmLeft != null && kmLeft! < 500) ||
          (daysLeft != null && daysLeft! < 14));
}

class MaintenanceService extends ChangeNotifier {
  final TripDb db;
  final AppSettings settings;
  final ObdService obd;
  final TripRecorder trips;

  List<MaintenanceEntry> entries = [];
  /// Dashboard reading + finished trips since then (null if never entered).
  double? _estimateBase;

  bool get odometerFromObd => (obd.values[Pids.odometer] ?? 0) > 0;

  /// Live odometer: the car's own value when reported, otherwise the
  /// estimate plus the trip in progress.
  double? get odometerKm {
    if (odometerFromObd) return obd.values[Pids.odometer];
    final base = _estimateBase;
    if (base == null) return null;
    return base + (trips.active ? trips.distanceKm : 0);
  }

  MaintenanceService(this.db, this.settings, this.obd, this.trips) {
    trips.addListener(_onTrips);
    settings.addListener(_onSettings);
  }

  int? _vehicleId;
  void _onSettings() {
    if (settings.vehicle.id != _vehicleId) {
      load(); // switched car: reload its history
    } else {
      refreshOdometer();
    }
  }

  int _seenTrips = -1;
  void _onTrips() {
    if (trips.finishedCount != _seenTrips) {
      _seenTrips = trips.finishedCount;
      refreshOdometer();
    }
  }

  Future<void> load() async {
    _vehicleId = settings.vehicle.id;
    final rows = await db.raw.query('maintenance',
        where: 'vehicle_id = ?',
        whereArgs: [_vehicleId],
        orderBy: 'date DESC, id DESC');
    entries = rows.map(MaintenanceEntry.fromRow).toList();
    await refreshOdometer();
  }

  /// Real odometer from OBD (PID A6) when the car reports it, otherwise the
  /// dashboard reading the user entered plus trips logged since then.
  Future<void> refreshOdometer() async {
    if (settings.odoBaseKm != null && settings.odoBaseAt != null) {
      _estimateBase = settings.odoBaseKm! +
          await db.kmSince(settings.odoBaseAt!, settings.vehicle.id ?? 0);
    } else {
      _estimateBase = null;
    }
    notifyListeners();
  }

  Future<void> save(MaintenanceEntry e) async {
    if (e.id == null) {
      await db.raw.insert(
          'maintenance', {...e.toRow(), 'vehicle_id': settings.vehicle.id});
    } else {
      await db.raw.update('maintenance', e.toRow(),
          where: 'id = ?', whereArgs: [e.id]);
    }
    // Recording a service with a known km is also a fresh odometer reading.
    final current = odometerKm;
    if (!odometerFromObd &&
        e.km != null &&
        (current == null || e.km! > current)) {
      await settings.setOdometer(e.km!);
    }
    await load();
  }

  Future<void> delete(int id) async {
    await db.raw.delete('maintenance', where: 'id = ?', whereArgs: [id]);
    await load();
  }

  /// Latest entry per type that has a next-service target, soonest first.
  List<DueItem> get due {
    final latest = <String, MaintenanceEntry>{};
    for (final e in entries) {
      latest.putIfAbsent(e.type, () => e); // entries are newest first
    }
    final now = DateTime.now();
    final items = latest.values
        .where((e) => e.nextKm != null || e.nextDate != null)
        .map((e) => DueItem(
              e,
              e.nextKm != null && odometerKm != null
                  ? e.nextKm! - odometerKm!
                  : null,
              e.nextDate?.difference(now).inDays,
            ))
        .toList();
    double score(DueItem d) => [
          if (d.kmLeft != null) d.kmLeft! / 30, // ~30 km/day
          if (d.daysLeft != null) d.daysLeft!.toDouble(),
        ].fold<double>(double.infinity, (a, b) => a < b ? a : b);
    items.sort((a, b) => score(a).compareTo(score(b)));
    return items;
  }

  double get totalCost => entries.fold<double>(0, (s, e) => s + e.cost);

  @override
  void dispose() {
    trips.removeListener(_onTrips);
    settings.removeListener(_onSettings);
    super.dispose();
  }
}
