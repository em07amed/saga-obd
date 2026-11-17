/// One car the user drives. Trips and maintenance are recorded per vehicle.
class Vehicle {
  int? id;
  String name;
  String make;
  String model;
  int? year;
  double tankL;
  double displacementL;
  double ve; // volumetric efficiency, used when the car has no MAF sensor
  String fuelGrade;
  double fuelPrice;
  double defaultL100;
  double? odoBaseKm;
  DateTime? odoBaseAt;

  Vehicle({
    this.id,
    required this.name,
    this.make = '',
    this.model = '',
    this.year,
    this.tankL = 40,
    this.displacementL = 1.3,
    this.ve = 0.80,
    this.fuelGrade = '92',
    this.fuelPrice = 22.25,
    this.defaultL100 = 7.0,
    this.odoBaseKm,
    this.odoBaseAt,
  });

  String get subtitle => [
        if (make.isNotEmpty) make,
        if (model.isNotEmpty) model,
        if (year != null) '$year',
      ].join(' ');

  Map<String, Object?> toRow() => {
        'name': name,
        'make': make,
        'model': model,
        'year': year,
        'tank_l': tankL,
        'displacement_l': displacementL,
        've': ve,
        'fuel_grade': fuelGrade,
        'fuel_price': fuelPrice,
        'default_l100': defaultL100,
        'odo_base_km': odoBaseKm,
        'odo_base_at': odoBaseAt?.millisecondsSinceEpoch,
      };

  factory Vehicle.fromRow(Map<String, Object?> r) => Vehicle(
        id: r['id'] as int,
        name: r['name'] as String,
        make: (r['make'] as String?) ?? '',
        model: (r['model'] as String?) ?? '',
        year: r['year'] as int?,
        tankL: (r['tank_l'] as num).toDouble(),
        displacementL: (r['displacement_l'] as num).toDouble(),
        ve: (r['ve'] as num).toDouble(),
        fuelGrade: r['fuel_grade'] as String,
        fuelPrice: (r['fuel_price'] as num).toDouble(),
        defaultL100: (r['default_l100'] as num).toDouble(),
        odoBaseKm: (r['odo_base_km'] as num?)?.toDouble(),
        odoBaseAt: r['odo_base_at'] == null
            ? null
            : DateTime.fromMillisecondsSinceEpoch(r['odo_base_at'] as int),
      );
}
