import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'l10n.dart';
import 'trips/trip_db.dart';
import 'vehicle.dart';

/// App-wide settings plus the user's vehicles. Car-specific values (tank,
/// engine, fuel, odometer) come from the active vehicle.
class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;
  TripDb? _db;

  String? deviceAddress;
  String? deviceName;
  bool autoConnect = true;
  String themeMode = 'sport'; // sport | system | light | dark
  String lang = 'ar'; // ar | en
  bool alertsOn = true;
  bool voiceAlerts = true;

  /// Speed limit chosen by the driver (km/h) and how to warn when exceeded:
  /// 'voice' (spoken message), 'beep' (tone, no message) or 'off'.
  double speedLimit = 100;
  String speedAlertMode = 'voice';
  double coolantAlert = 80; // °C; 105 is the normal value, 80 for testing

  /// Official Egypt pump prices (EGP/L) as of Nov 2026. Editable per vehicle
  /// because the pricing committee changes them periodically.
  static const gradePrices = {'80': 20.75, '92': 22.25, '95': 24.0};

  List<Vehicle> vehicles = [];
  int? _activeId;

  /// Fallback used only before load() / in tests.
  final Vehicle _fallback = Vehicle(name: 'عربيتي');

  Vehicle get vehicle => vehicles.firstWhere((v) => v.id == _activeId,
      orElse: () => vehicles.isNotEmpty ? vehicles.first : _fallback);

  // Active-vehicle shortcuts used across the app.
  double get tankLiters => vehicle.tankL;
  double get displacementL => vehicle.displacementL;
  double get volumetricEff => vehicle.ve;
  String get fuelGrade => vehicle.fuelGrade;
  double get fuelPrice => vehicle.fuelPrice;
  double get defaultL100 => vehicle.defaultL100;
  double? get odoBaseKm => vehicle.odoBaseKm;
  DateTime? get odoBaseAt => vehicle.odoBaseAt;

  Future<void> load(TripDb db) async {
    _db = db;
    _p = await SharedPreferences.getInstance();
    deviceAddress = _p.getString('deviceAddress');
    deviceName = _p.getString('deviceName');
    autoConnect = _p.getBool('autoConnect') ?? true;
    themeMode = _p.getString('themeMode') ?? themeMode;
    lang = _p.getString('lang') ?? lang;
    alertsOn = _p.getBool('alertsOn') ?? true;
    voiceAlerts = _p.getBool('voiceAlerts') ?? true;
    speedLimit = _p.getDouble('speedLimit') ?? speedLimit;
    speedAlertMode = _p.getString('speedAlertMode') ?? speedAlertMode;
    coolantAlert = _p.getDouble('coolantAlert') ?? coolantAlert;
    Lang.code = lang;

    vehicles = await db.vehicles();
    if (vehicles.isEmpty) {
      // First run, or upgrade from the single-car version: build the first
      // vehicle from the old per-app settings and attach existing history.
      final at = _p.getInt('odoBaseAt');
      final grade = _p.getString('fuelGrade') ?? '95';
      final first = Vehicle(
        name: _p.containsKey('tankLiters') ? 'بروتون ساجا' : 'عربيتي',
        make: _p.containsKey('tankLiters') ? 'Proton' : '',
        model: _p.containsKey('tankLiters') ? 'Saga' : '',
        tankL: _p.getDouble('tankLiters') ?? 40,
        displacementL: _p.getDouble('displacementL') ?? 1.332,
        ve: _p.getDouble('volumetricEff') ?? 0.80,
        fuelGrade: grade,
        fuelPrice: _p.getDouble('fuelPrice') ?? gradePrices[grade] ?? 24,
        defaultL100: _p.getDouble('defaultL100') ?? 7.0,
        odoBaseKm: _p.getDouble('odoBaseKm'),
        odoBaseAt: at == null ? null : DateTime.fromMillisecondsSinceEpoch(at),
      );
      first.id = await db.insertVehicle(first);
      await db.adoptOrphans(first.id!);
      vehicles = [first];
    }
    _activeId = _p.getInt('activeVehicle') ?? vehicles.first.id;
  }

  Future<void> _saveActive() async {
    await _db?.updateVehicle(vehicle);
    notifyListeners();
  }

  // ---------- vehicles ----------

  Future<void> setActiveVehicle(int id) async {
    _activeId = id;
    await _p.setInt('activeVehicle', id);
    notifyListeners();
  }

  Future<int> addVehicle(Vehicle v) async {
    v.id = await _db!.insertVehicle(v);
    vehicles = [...vehicles, v];
    await setActiveVehicle(v.id!);
    return v.id!;
  }

  Future<void> updateVehicle(Vehicle v) async {
    await _db!.updateVehicle(v);
    vehicles = [for (final x in vehicles) x.id == v.id ? v : x];
    notifyListeners();
  }

  /// Deletes the vehicle with its trips and maintenance. Keeps at least one.
  Future<void> deleteVehicle(int id) async {
    if (vehicles.length <= 1) return;
    await _db!.deleteVehicle(id);
    vehicles = vehicles.where((v) => v.id != id).toList();
    if (_activeId == id) await setActiveVehicle(vehicles.first.id!);
    notifyListeners();
  }

  // ---------- global ----------

  Future<void> setDevice(String name, String address) async {
    deviceName = name;
    deviceAddress = address;
    await _p.setString('deviceName', name);
    await _p.setString('deviceAddress', address);
    notifyListeners();
  }

  Future<void> setCoolantAlert(double v) async {
    coolantAlert = v;
    await _p.setDouble('coolantAlert', v);
    notifyListeners();
  }

  Future<void> setSpeedLimit(double v) async {
    speedLimit = v.clamp(20, 200).toDouble();
    await _p.setDouble('speedLimit', speedLimit);
    notifyListeners();
  }

  Future<void> setSpeedAlertMode(String mode) async {
    speedAlertMode = mode;
    await _p.setString('speedAlertMode', mode);
    notifyListeners();
  }

  Future<void> setVoiceAlerts(bool v) async {
    voiceAlerts = v;
    await _p.setBool('voiceAlerts', v);
    notifyListeners();
  }

  Future<void> setAlerts(bool v) async {
    alertsOn = v;
    await _p.setBool('alertsOn', v);
    notifyListeners();
  }

  Future<void> setLang(String code) async {
    lang = code;
    Lang.code = code;
    await _p.setString('lang', code);
    notifyListeners();
  }

  Future<void> setThemeMode(String mode) async {
    themeMode = mode;
    await _p.setString('themeMode', mode);
    notifyListeners();
  }

  Future<void> setAutoConnect(bool v) async {
    autoConnect = v;
    await _p.setBool('autoConnect', v);
    notifyListeners();
  }

  // ---------- active vehicle values ----------

  /// Switches grade and resets the price to that grade's official price.
  Future<void> setFuelGrade(String grade) async {
    vehicle.fuelGrade = grade;
    vehicle.fuelPrice = gradePrices[grade] ?? vehicle.fuelPrice;
    await _saveActive();
  }

  /// Dashboard odometer minus PID 0131 (distance since codes cleared),
  /// learned once per vehicle. Null until calibrated.
  double? get odoOffset => _p.getDouble('odoOffset_${vehicle.id}');

  Future<void> setOdoOffset(double? v) async {
    final key = 'odoOffset_${vehicle.id}';
    if (v == null) {
      await _p.remove(key);
    } else {
      await _p.setDouble(key, v);
    }
    notifyListeners();
  }

  Future<void> setOdometer(double km) async {
    vehicle.odoBaseKm = km;
    vehicle.odoBaseAt = DateTime.now();
    await _saveActive();
  }

  Future<void> setNumber(String key, double v) async {
    final x = vehicle;
    switch (key) {
      case 'tankLiters':
        x.tankL = v;
      case 'displacementL':
        x.displacementL = v;
      case 'volumetricEff':
        x.ve = v;
      case 'fuelPrice':
        x.fuelPrice = v;
      case 'defaultL100':
        x.defaultL100 = v;
      default:
        return;
    }
    await _saveActive();
  }
}
