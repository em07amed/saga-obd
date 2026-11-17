import '../settings.dart';
import 'pids.dart';

enum FuelSource { fuelRatePid, maf, speedDensity, none }

class FuelCalc {
  static const stoichAfr = 14.7; // gasoline
  static const densityGPerL = 740.0; // gasoline
  static const airMolarMass = 28.97; // g/mol
  static const gasConstant = 8.314; // J/(mol*K)

  /// Picks the best method the car supports.
  static FuelSource sourceFor(Set<int> supported) {
    if (supported.contains(Pids.fuelRate)) return FuelSource.fuelRatePid;
    if (supported.contains(Pids.maf)) return FuelSource.maf;
    if (supported.contains(Pids.map) &&
        supported.contains(Pids.rpm) &&
        supported.contains(Pids.iat)) {
      return FuelSource.speedDensity;
    }
    return FuelSource.none;
  }

  /// PIDs that must be polled every cycle for the chosen method.
  static List<int> inputsFor(FuelSource s) => switch (s) {
        FuelSource.fuelRatePid => [Pids.fuelRate],
        FuelSource.maf => [Pids.maf],
        FuelSource.speedDensity => [Pids.map],
        FuelSource.none => const [],
      };

  /// Litres per hour, or null if inputs are missing.
  static double? litresPerHour(
      FuelSource s, Map<int, double> v, AppSettings settings) {
    final rpm = v[Pids.rpm];
    if (rpm != null && rpm < 50) return 0; // engine off

    double? mafGs;
    switch (s) {
      case FuelSource.fuelRatePid:
        return v[Pids.fuelRate];
      case FuelSource.maf:
        mafGs = v[Pids.maf];
      case FuelSource.speedDensity:
        final map = v[Pids.map];
        final iat = v[Pids.iat];
        if (rpm == null || map == null || iat == null) return null;
        final imap = rpm * map / (iat + 273.15) / 2;
        mafGs = (imap / 60) *
            settings.volumetricEff *
            settings.displacementL *
            airMolarMass /
            gasConstant;
      case FuelSource.none:
        return null;
    }
    if (mafGs == null) return null;

    // Apply the ECU's own fuel trims when available.
    final trim = (v[Pids.stft1] ?? 0.0) + (v[Pids.ltft1] ?? 0.0);
    final fuelGs = mafGs / stoichAfr * (1 + trim / 100);
    return fuelGs * 3600 / densityGPerL;
  }

  /// L/100km; null when nearly stopped (show L/h instead).
  static double? litresPer100(double? lph, double? speedKmh) {
    if (lph == null || speedKmh == null || speedKmh < 5) return null;
    return lph * 100 / speedKmh;
  }
}
