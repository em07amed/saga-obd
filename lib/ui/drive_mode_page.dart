import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../obd/pids.dart';
import 'widgets.dart';

/// Full-screen landscape view for a phone on a dash mount: few, large numbers.
class DriveModePage extends StatefulWidget {
  const DriveModePage({super.key});

  @override
  State<DriveModePage> createState() => _DriveModePageState();
}

class _DriveModePageState extends State<DriveModePage> {
  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final obd = App.obd;
    final trips = App.trips;
    final s = App.settings;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([obd, trips, App.maintenance]),
          builder: (context, _) {
            final v = obd.values;
            final rpm = v[Pids.rpm];
            final coolant = v[Pids.coolant];
            final level = v[Pids.fuelLevel];
            final litres = level == null ? null : level / 100 * s.tankLiters;
            final avg = trips.avgL100 ?? s.defaultL100;
            final range = litres == null ? null : litres / avg * 100;
            final hot = coolant != null && coolant >= 105;
            final redline = rpm != null && rpm >= 6000;

            Widget big(String label, String value, String unit,
                    {Color? color, double size = 64}) =>
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 16, color: scheme.onSurfaceVariant)),
                    FittedBox(
                      child: Text(value,
                          style: TextStyle(
                              fontSize: size,
                              height: 1.1,
                              fontWeight: FontWeight.w800,
                              color: color)),
                    ),
                    Text(unit,
                        style: TextStyle(
                            fontSize: 14, color: scheme.onSurfaceVariant)),
                  ],
                );

            return Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: 'خروج',
                        iconSize: 28,
                        onPressed: () => Navigator.pop(context),
                        icon: const Icon(Icons.close),
                      ),
                      Expanded(
                        child: Text(obd.status,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                      if (App.maintenance.odometerKm != null)
                        Text('العداد ${fmt(App.maintenance.odometerKm)} كم',
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Speed: the biggest number on screen.
                        Expanded(
                          flex: 3,
                          child: Card(
                            child: big('السرعة', fmt(v[Pids.speed]), 'كم/س',
                                size: 140),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: Column(
                            children: [
                              Expanded(
                                child: Row(children: [
                                  Expanded(
                                    child: Card(
                                      child: big('RPM', fmt(rpm), 'لفة/د',
                                          color: redline
                                              ? AppColors.danger(context)
                                              : null),
                                    ),
                                  ),
                                  Expanded(
                                    child: Card(
                                      child: big('حرارة المياه', fmt(coolant),
                                          '°C',
                                          color: hot
                                              ? AppColors.danger(context)
                                              : null),
                                    ),
                                  ),
                                ]),
                              ),
                              Expanded(
                                child: Row(children: [
                                  Expanded(
                                    child: Card(
                                      child: big(
                                        'البنزين',
                                        fmt(litres, 1),
                                        range == null
                                            ? 'لتر'
                                            : 'لتر • ~${fmt(range)} كم',
                                        color: level != null && level < 15
                                            ? AppColors.warning(context)
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Card(
                                      child: obd.instantL100 != null
                                          ? big('الاستهلاك',
                                              fmt(obd.instantL100, 1), 'ل/100كم')
                                          : big('الاستهلاك',
                                              fmt(obd.fuelRateLh, 2), 'ل/ساعة'),
                                    ),
                                  ),
                                  Expanded(
                                    child: Card(
                                      child: big(
                                        'الرحلة',
                                        fmt(trips.distanceKm, 1),
                                        trips.active
                                            ? 'كم • ${fmt(trips.fuelL * s.fuelPrice)} ج.م'
                                            : 'كم',
                                      ),
                                    ),
                                  ),
                                ]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
