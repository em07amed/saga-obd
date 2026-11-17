import 'package:flutter/material.dart';

import '../main.dart';
import '../obd/fuel.dart';
import '../obd/pids.dart';
import 'widgets.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final obd = App.obd;
    final trips = App.trips;
    final settings = App.settings;

    return Column(
      children: [
        const ConnectionBar(),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([obd, trips, settings]),
            builder: (context, _) {
              final v = obd.values;

              // Fuel in tank and range.
              final levelPct = v[Pids.fuelLevel];
              final litres =
                  levelPct == null ? null : levelPct / 100 * settings.tankLiters;
              final avg = trips.avgL100 ?? settings.defaultL100;
              final rangeKm =
                  litres == null || avg <= 0 ? null : litres / avg * 100;

              // Instant consumption.
              final l100 = obd.instantL100;
              final lph = obd.fuelRateLh;
              final consumptionSub = switch (obd.fuelSource) {
                FuelSource.fuelRatePid => 'من حساس الاستهلاك',
                FuelSource.maf => 'محسوب من MAF',
                FuelSource.speedDensity =>
                  'محسوب من MAP (VE ${settings.volumetricEff.toStringAsFixed(2)})',
                FuelSource.none => 'العربية مش بتدعم قراءات الاستهلاك',
              };

              final coolant = v[Pids.coolant];
              final volt = v[Pids.voltage];

              final tiles = <Widget>[
                Gauge(
                    label: 'RPM',
                    unit: 'لفة/د',
                    value: v[Pids.rpm],
                    min: 0,
                    max: 7000,
                    redFrom: 6000),
                Gauge(
                    label: 'السرعة',
                    unit: 'كم/س',
                    value: v[Pids.speed],
                    min: 0,
                    max: 200),
                Gauge(
                    label: 'حرارة المياه',
                    unit: '°C',
                    value: coolant,
                    min: 40,
                    max: 130,
                    redFrom: 105),
                StatTile(
                  label: 'البنزين',
                  icon: Icons.local_gas_station,
                  value: fmt(litres, 1),
                  unit: 'لتر',
                  sub: levelPct == null
                      ? 'مستوى البنزين مش مدعوم'
                      : '${fmt(levelPct)}% • يكفي ~${fmt(rangeKm)} كم',
                  color: levelPct != null && levelPct < 15
                      ? AppColors.warning(context)
                      : null,
                ),
                StatTile(
                  label: 'الاستهلاك اللحظي',
                  icon: Icons.eco,
                  value: l100 != null ? fmt(l100, 1) : fmt(lph, 2),
                  unit: l100 != null ? 'ل/100كم' : 'ل/ساعة',
                  sub: consumptionSub,
                ),
                StatTile(
                  label: trips.active ? 'الرحلة الحالية' : 'مفيش رحلة شغالة',
                  icon: Icons.route,
                  value: fmt(trips.distanceKm, 1),
                  unit: 'كم',
                  sub: trips.active
                      ? '${fmt(trips.fuelL, 2)} لتر • '
                          'متوسط ${fmt(trips.avgL100, 1)} ل/100 • '
                          '${fmt(trips.fuelL * settings.fuelPrice)} ج.م'
                      : 'هتبدأ لوحدها لما الموتور يدور',
                ),
                StatTile(
                  label: 'البطارية',
                  icon: Icons.battery_charging_full,
                  value: fmt(volt, 2),
                  unit: 'V',
                  color: volt != null && (volt < 12.0 || volt > 15.0)
                      ? AppColors.warning(context)
                      : null,
                ),
                StatTile(
                  label: 'البوابة / الحمل',
                  icon: Icons.tune,
                  value: fmt(v[Pids.throttle]),
                  unit: '%',
                  sub: 'حمل المحرك ${fmt(v[Pids.load])}%',
                ),
                StatTile(
                  label: 'حرارة الهواء الداخل',
                  icon: Icons.air,
                  value: fmt(v[Pids.iat]),
                  unit: '°C',
                  sub: v[Pids.ambient] == null
                      ? null
                      : 'الجو ${fmt(v[Pids.ambient])}°C',
                ),
              ];

              return LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth > 900
                    ? 5
                    : c.maxWidth > 600
                        ? 4
                        : 2;
                return GridView.count(
                  padding: const EdgeInsets.all(8),
                  crossAxisCount: cols,
                  childAspectRatio: 1.05,
                  children: tiles,
                );
              });
            },
          ),
        ),
      ],
    );
  }
}
