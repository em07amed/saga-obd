import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// User-tunable settings. Defaults match the Proton Saga 1.3 VVT.
class AppSettings extends ChangeNotifier {
  late SharedPreferences _p;

  String? deviceAddress;
  String? deviceName;
  bool autoConnect = true;
  String themeMode = 'system'; // system | light | dark

  /// Odometer as read off the dashboard by the user, and when.
  double? odoBaseKm;
  DateTime? odoBaseAt;

  double tankLiters = 40;
  double displacementL = 1.332;
  double volumetricEff = 0.80; // VE, calibrate from real fill-ups
  /// Official Egypt pump prices (EGP/L) as of Nov 2026. Editable in settings
  /// because the pricing committee changes them periodically.
  static const gradePrices = {'80': 20.75, '92': 22.25, '95': 24.0};
  String fuelGrade = '95';
  double fuelPrice = 24.0; // EGP per litre
  double defaultL100 = 7.0; // used for range until a trip has enough data

  Future<void> load() async {
    _p = await SharedPreferences.getInstance();
    deviceAddress = _p.getString('deviceAddress');
    deviceName = _p.getString('deviceName');
    autoConnect = _p.getBool('autoConnect') ?? true;
    themeMode = _p.getString('themeMode') ?? themeMode;
    odoBaseKm = _p.getDouble('odoBaseKm');
    final at = _p.getInt('odoBaseAt');
    odoBaseAt = at == null ? null : DateTime.fromMillisecondsSinceEpoch(at);
    tankLiters = _p.getDouble('tankLiters') ?? tankLiters;
    displacementL = _p.getDouble('displacementL') ?? displacementL;
    volumetricEff = _p.getDouble('volumetricEff') ?? volumetricEff;
    fuelGrade = _p.getString('fuelGrade') ?? fuelGrade;
    fuelPrice = _p.getDouble('fuelPrice') ?? gradePrices[fuelGrade] ?? fuelPrice;
    defaultL100 = _p.getDouble('defaultL100') ?? defaultL100;
  }

  Future<void> setDevice(String name, String address) async {
    deviceName = name;
    deviceAddress = address;
    await _p.setString('deviceName', name);
    await _p.setString('deviceAddress', address);
    notifyListeners();
  }

  /// Switches grade and resets the price to that grade's official price.
  Future<void> setFuelGrade(String grade) async {
    fuelGrade = grade;
    fuelPrice = gradePrices[grade] ?? fuelPrice;
    await _p.setString('fuelGrade', grade);
    await _p.setDouble('fuelPrice', fuelPrice);
    notifyListeners();
  }

  Future<void> setOdometer(double km) async {
    odoBaseKm = km;
    odoBaseAt = DateTime.now();
    await _p.setDouble('odoBaseKm', km);
    await _p.setInt('odoBaseAt', odoBaseAt!.millisecondsSinceEpoch);
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

  Future<void> setNumber(String key, double v) async {
    switch (key) {
      case 'tankLiters':
        tankLiters = v;
      case 'displacementL':
        displacementL = v;
      case 'volumetricEff':
        volumetricEff = v;
      case 'fuelPrice':
        fuelPrice = v;
      case 'defaultL100':
        defaultL100 = v;
      default:
        return;
    }
    await _p.setDouble(key, v);
    notifyListeners();
  }
}
