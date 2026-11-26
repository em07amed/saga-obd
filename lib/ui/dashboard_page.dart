import 'package:flutter/material.dart';

import '../main.dart';
import '../obd/fuel.dart';
import '../obd/pids.dart';
import 'drive_mode_page.dart';
import 'fuel_page.dart';
import 'widgets.dart';
import '../l10n.dart';

class DashboardPage extends StatelessWidget {
  const DashboardPage({super.key});

  @override
  Widget build(BuildContext context) {
    final obd = App.obd;
    final trips = App.trips;
    final settings = App.settings;

    return Stack(children: [
      Column(
      children: [
        ConnectionBar(),
        Expanded(
          child: ListenableBuilder(
            listenable: Listenable.merge([obd, trips, settings, App.maintenance, App.fuel]),
            builder: (context, _) {
              final v = obd.values;

              // Fuel in tank and range.
              final levelPct = v[Pids.fuelLevel];
              final litres = App.fuel.litresNow;
              final lowFuel =
                  litres != null && litres < settings.tankLiters * 0.15;
              final avg = App.fuel.realAvgL100 ??
                  trips.avgL100 ??
                  settings.defaultL100;
              final rangeKm =
                  litres == null || avg <= 0 ? null : litres / avg * 100;

              // Instant consumption.
              final l100 = obd.instantL100;
              final lph = obd.fuelRateLh;
              final consumptionSub = switch (obd.fuelSource) {
                FuelSource.fuelRatePid => tr('من حساس الاستهلاك'),
                FuelSource.maf => tr('محسوب من MAF'),
                FuelSource.speedDensity =>
                  tr('محسوب من MAP (VE ${settings.volumetricEff.toStringAsFixed(2)})'),
                FuelSource.none => tr('العربية مش بتدعم قراءات الاستهلاك'),
              };

              final coolant = v[Pids.coolant];
              final volt = v[Pids.voltage];

              final tiles = <Widget>[
                Gauge(
                    label: 'RPM',
                    unit: tr('لفة/د'),
                    value: v[Pids.rpm],
                    min: 0,
                    max: 7000,
                    redFrom: 6000),
                Gauge(
                    label: tr('حرارة المياه'),
                    unit: '°C',
                    value: coolant,
                    min: 40,
                    max: 130,
                    redFrom: 105),
                GestureDetector(
                  onTap: () => Navigator.of(context).push(
                      MaterialPageRoute(builder: (_) => const FuelPage())),
                  child: StatTile(
                    label: tr('البنزين'),
                    icon: Icons.local_gas_station,
                    value: fmt(litres, 1),
                    unit: tr('لتر'),
                    sub: litres == null
                        ? tr('دوس هنا وسجّل تفويلة')
                        : levelPct != null
                            ? tr('${fmt(levelPct)}% • يكفي ~${fmt(rangeKm)} كم')
                            : tr('تقديري • يكفي ~${fmt(rangeKm)} كم'),
                    color: lowFuel ? AppColors.warning(context) : null,
                  ),
                ),
                StatTile(
                  label: tr('الاستهلاك اللحظي'),
                  icon: Icons.eco,
                  value: l100 != null ? fmt(l100, 1) : fmt(lph, 2),
                  unit: l100 != null ? tr('ل/100كم') : tr('ل/ساعة'),
                  sub: consumptionSub,
                ),
                StatTile(
                  label: trips.active ? tr('الرحلة الحالية') : tr('مفيش رحلة شغالة'),
                  icon: Icons.route,
                  value: fmt(trips.distanceKm, 1),
                  unit: tr('كم'),
                  sub: trips.active
                      ? tr('${fmt(trips.fuelL, 2)} لتر • '
                          'متوسط ${fmt(trips.avgL100, 1)} ل/100 • '
                          '${fmt(trips.fuelL * settings.fuelPrice)} ج.م')
                      : tr('هتبدأ لوحدها لما الموتور يدور'),
                ),
                StatTile(
                  label: tr('العداد'),
                  icon: Icons.av_timer,
                  value: fmt(App.maintenance.odometerKm),
                  unit: tr('كم'),
                  sub: App.maintenance.odometerKm == null
                      ? tr('اكتب رقم التابلوه من تاب الصيانة')
                      : switch (App.maintenance.odometerSource) {
                          'obd' => tr('من كمبيوتر العربية'),
                          'ecu' => tr('من كمبيوتر العربية • لحظي'),
                          'ecu_raw' => tr('تقريبي من كمبيوتر العربية • اضبطه من الصيانة'),
                          _ => tr('تقديري • بيزيد مع الرحلات'),
                        },
                ),
                StatTile(
                  label: tr('البطارية'),
                  icon: Icons.battery_charging_full,
                  value: fmt(volt, 2),
                  unit: 'V',
                  color: volt != null && (volt < 12.0 || volt > 15.0)
                      ? AppColors.warning(context)
                      : null,
                ),
                StatTile(
                  label: tr('البوابة / الحمل'),
                  icon: Icons.tune,
                  value: fmt(v[Pids.throttle]),
                  unit: '%',
                  sub: tr('حمل المحرك ${fmt(v[Pids.load])}%'),
                ),
                StatTile(
                  label: tr('حرارة الهواء الداخل'),
                  icon: Icons.air,
                  value: fmt(v[Pids.iat]),
                  unit: '°C',
                  sub: v[Pids.ambient] == null
                      ? null
                      : tr('الجو ${fmt(v[Pids.ambient])}°C'),
                ),
              ];

              return LayoutBuilder(builder: (context, c) {
                final cols = c.maxWidth > 900
                    ? 5
                    : c.maxWidth > 600
                        ? 4
                        : 2;
                final heroSize = (c.maxWidth * 0.86).clamp(220.0, 380.0);
                return CustomScrollView(slivers: [
                  // Big icon-style speedometer up top.
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Center(
                        child: SizedBox(
                          width: heroSize,
                          height: heroSize + 18,
                          child: Gauge(
                            hero: true,
                            label: tr('السرعة'),
                            unit: tr('كم/س'),
                            value: v[Pids.speed],
                            min: 0,
                            max: 220,
                          ),
                        ),
                      ),
                    ),
                  ),
                  SliverPadding(
                    padding: EdgeInsets.fromLTRB(8, 8, 8, 88),
                    sliver: SliverGrid.count(
                      crossAxisCount: cols,
                      childAspectRatio: 1.05,
                      children: tiles,
                    ),
                  ),
                ]);
              });
            },
          ),
        ),
      ],
    ),
      PositionedDirectional(
        end: 16,
        bottom: 16,
        child: FloatingActionButton.extended(
          heroTag: 'drive',
          onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => DriveModePage())),
          icon: Icon(Icons.directions_car),
          label: Text(tr('وضع القيادة')),
        ),
      ),
    ]);
  }
}
