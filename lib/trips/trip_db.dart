import 'package:path/path.dart' as p;
import 'package:sqflite/sqflite.dart';

class Trip {
  final int id;
  final DateTime startedAt;
  final DateTime? endedAt;
  final double obdKm;
  final double gpsKm;
  final double fuelL;
  final double maxSpeed;
  final int idleSec;
  final double maxCoolant;
  final double fuelPrice;

  const Trip({
    required this.id,
    required this.startedAt,
    required this.endedAt,
    required this.obdKm,
    required this.gpsKm,
    required this.fuelL,
    required this.maxSpeed,
    required this.idleSec,
    required this.maxCoolant,
    required this.fuelPrice,
  });

  /// GPS distance is more accurate than the OBD speed integral when present.
  double get distanceKm => gpsKm > 0.3 ? gpsKm : obdKm;
  double? get avgL100 => distanceKm > 0.2 ? fuelL / distanceKm * 100 : null;
  double get cost => fuelL * fuelPrice;
  Duration get duration =>
      (endedAt ?? DateTime.now()).difference(startedAt);

  factory Trip.fromRow(Map<String, Object?> r) => Trip(
        id: r['id'] as int,
        startedAt: DateTime.fromMillisecondsSinceEpoch(r['started_at'] as int),
        endedAt: r['ended_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['ended_at'] as int),
        obdKm: (r['obd_km'] as num).toDouble(),
        gpsKm: (r['gps_km'] as num).toDouble(),
        fuelL: (r['fuel_l'] as num).toDouble(),
        maxSpeed: (r['max_speed'] as num).toDouble(),
        idleSec: r['idle_sec'] as int,
        maxCoolant: (r['max_coolant'] as num).toDouble(),
        fuelPrice: (r['fuel_price'] as num).toDouble(),
      );
}

class TripSample {
  final DateTime ts;
  final double? speed;
  final double? rpm;
  final double? coolant;
  final double? fuelRate;
  final double? lat;
  final double? lng;

  const TripSample(this.ts, this.speed, this.rpm, this.coolant, this.fuelRate,
      this.lat, this.lng);

  factory TripSample.fromRow(Map<String, Object?> r) => TripSample(
        DateTime.fromMillisecondsSinceEpoch(r['ts'] as int),
        (r['speed'] as num?)?.toDouble(),
        (r['rpm'] as num?)?.toDouble(),
        (r['coolant'] as num?)?.toDouble(),
        (r['fuel_rate'] as num?)?.toDouble(),
        (r['lat'] as num?)?.toDouble(),
        (r['lng'] as num?)?.toDouble(),
      );
}

class TripDb {
  late Database _db;

  Future<void> open() async {
    final path = p.join(await getDatabasesPath(), 'trips.db');
    _db = await openDatabase(path, version: 2,
        onUpgrade: (db, oldV, newV) async {
      if (oldV < 2) await _createMaintenance(db);
    }, onCreate: (db, _) async {
      await db.execute('''
        CREATE TABLE trips(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          started_at INTEGER NOT NULL,
          ended_at INTEGER,
          obd_km REAL NOT NULL DEFAULT 0,
          gps_km REAL NOT NULL DEFAULT 0,
          fuel_l REAL NOT NULL DEFAULT 0,
          max_speed REAL NOT NULL DEFAULT 0,
          idle_sec INTEGER NOT NULL DEFAULT 0,
          max_coolant REAL NOT NULL DEFAULT 0,
          fuel_price REAL NOT NULL DEFAULT 0
        )''');
      await db.execute('''
        CREATE TABLE samples(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          trip_id INTEGER NOT NULL,
          ts INTEGER NOT NULL,
          speed REAL, rpm REAL, coolant REAL, fuel_rate REAL,
          lat REAL, lng REAL
        )''');
      await db.execute('CREATE INDEX idx_samples_trip ON samples(trip_id)');
      await _createMaintenance(db);
    });
    await _closeDanglingTrips();
  }

  static Future<void> _createMaintenance(Database db) => db.execute('''
        CREATE TABLE maintenance(
          id INTEGER PRIMARY KEY AUTOINCREMENT,
          date INTEGER NOT NULL,
          km REAL,
          type TEXT NOT NULL,
          cost REAL NOT NULL DEFAULT 0,
          notes TEXT,
          next_km REAL,
          next_date INTEGER
        )''');

  Database get raw => _db;

  /// Sum of trip distances that started at or after [since].
  Future<double> kmSince(DateTime since) async {
    final rows = await _db.query('trips',
        where: 'started_at >= ? AND ended_at IS NOT NULL',
        whereArgs: [since.millisecondsSinceEpoch]);
    return rows
        .map(Trip.fromRow)
        .fold<double>(0, (s, t) => s + t.distanceKm);
  }

  /// Trips left open by a crash/kill get closed at their last sample.
  Future<void> _closeDanglingTrips() async {
    final open = await _db.query('trips', where: 'ended_at IS NULL');
    for (final r in open) {
      final id = r['id'] as int;
      final last = await _db.rawQuery(
          'SELECT MAX(ts) AS t FROM samples WHERE trip_id = ?', [id]);
      final t = last.first['t'] as int? ?? r['started_at'] as int;
      await _db.update('trips', {'ended_at': t},
          where: 'id = ?', whereArgs: [id]);
    }
  }

  Future<int> startTrip(DateTime at, double fuelPrice) => _db.insert('trips', {
        'started_at': at.millisecondsSinceEpoch,
        'fuel_price': fuelPrice,
      });

  Future<void> updateTrip(int id, Map<String, Object?> values) =>
      _db.update('trips', values, where: 'id = ?', whereArgs: [id]);

  Future<void> insertSamples(int tripId, List<TripSample> samples) async {
    final batch = _db.batch();
    for (final s in samples) {
      batch.insert('samples', {
        'trip_id': tripId,
        'ts': s.ts.millisecondsSinceEpoch,
        'speed': s.speed,
        'rpm': s.rpm,
        'coolant': s.coolant,
        'fuel_rate': s.fuelRate,
        'lat': s.lat,
        'lng': s.lng,
      });
    }
    await batch.commit(noResult: true);
  }

  Future<List<Trip>> trips() async {
    final rows = await _db.query('trips', orderBy: 'started_at DESC');
    return rows.map(Trip.fromRow).toList();
  }

  Future<List<TripSample>> samples(int tripId) async {
    final rows = await _db.query('samples',
        where: 'trip_id = ?', whereArgs: [tripId], orderBy: 'ts');
    return rows.map(TripSample.fromRow).toList();
  }

  Future<void> deleteTrip(int id) async {
    await _db.delete('samples', where: 'trip_id = ?', whereArgs: [id]);
    await _db.delete('trips', where: 'id = ?', whereArgs: [id]);
  }
}
