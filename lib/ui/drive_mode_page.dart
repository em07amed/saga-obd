import 'dart:async';
import 'dart:convert';
import 'package:http/http.dart' as http;

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../main.dart';
import '../obd/bt_channel.dart';
import '../obd/pids.dart';
import 'maintenance_page.dart';
import 'trips_page.dart';
import 'vehicle_avatar.dart';
import 'widgets.dart';
import '../l10n.dart';
import 'readings_page.dart' show DtcPage;

part 'head_unit.dart';

/// Full-screen landscape view for a phone on a dash mount: few, large numbers.
class DriveModePage extends StatefulWidget {
  const DriveModePage({super.key});

  @override
  State<DriveModePage> createState() => _DriveModePageState();
}

enum _Panel { home, gauges, faults, maintenance, trips }

class _DriveModePageState extends State<DriveModePage> {
  _Panel _panel = _Panel.home;
  void _show(_Panel p, {bool toggle = false}) {
    setState(() => _panel = toggle && _panel == p ? _Panel.home : p);
  }

  // ---------- voice commands ----------

  bool _listening = false;
  String _heard = '';

  /// Uses the phone's speech recognizer (Google's voice popup), which works
  /// on Samsung too, then runs the command.
  Future<void> _voice() async {
    if (_listening) return;
    if (!(await Permission.microphone.request()).isGranted) {
      _say(tr('اسمح بإذن الميكروفون'));
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    String? text;
    try {
      text = await App.obd.bt.listen(Lang.isEn ? 'en-US' : 'ar-EG');
    } catch (_) {
      text = null;
    }
    if (!mounted) return;
    setState(() {
      _listening = false;
      _heard = text ?? '';
    });
    if (text == null) {
      _say(tr('التعرف على الصوت مش متاح على الموبايل ده'));
    } else if (text.trim().isNotEmpty) {
      _handle(text);
    }
  }

  void _say(String s) =>
      App.obd.bt.speak(s, Lang.code, flush: true).catchError((_) {});

  /// Same length as the input (char-for-char) so indexes map back to it.
  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');

  static String _clean(String s) => s
      .trim()
      .replaceFirst(
          RegExp(r'^(على|علي|الى|إلى|الي|لـ|ل |to |the )\s*'), '')
      .trim();

  Future<void> _handle(String raw) async {
    final t = _norm(raw);
    bool has(List<String> ws) => ws.any((w) => t.contains(_norm(w)));
    String after(List<String> ws) {
      for (final w in ws) {
        final i = t.indexOf(_norm(w));
        if (i >= 0) return _clean(raw.substring(i + w.length));
      }
      return '';
    }

    final v = App.obd.values;

    // Navigate somewhere.
    const goWords = ['وديني', 'ودينى', 'خدني', 'عايز اروح', 'روح', 'navigate to', 'take me to', 'go to'];
    if (has(goWords)) {
      final dest = after(goWords);
      if (dest.isEmpty) return _say(tr('قول اسم المكان بعد وديني'));
      final p = await Geolocator.getLastKnownPosition().catchError((_) => null);
      try {
        final r = await App.places
            .search(dest, p == null ? null : LatLng(p.latitude, p.longitude));
        if (r.isEmpty) return _say(tr('ما لقيتش $dest'));
        _say(tr('رايحين على ${r.first.name}'));
        await _googleMaps(r.first.at);
      } catch (_) {
        _say(tr('البحث محتاج نت'));
      }
      return;
    }
    // Readings.
    if (has(['السرعه', 'سرعتي', 'speed'])) {
      return _say(tr('سرعتك ${fmt(v[Pids.speed])} كيلو'));
    }
    if (has(['الحراره', 'حراره', 'temperature'])) {
      return _say(tr('حرارة الموتور ${fmt(v[Pids.coolant])} درجة'));
    }
    if (has(['البنزين', 'fuel'])) {
      final l = App.fuel.litresNow;
      if (l == null) return _say(tr('مش عارف البنزين. سجّل تفويلة الأول'));
      final avg = App.fuel.realAvgL100 ?? App.trips.avgL100 ?? App.settings.defaultL100;
      return _say(tr('فاضل ${l.toStringAsFixed(0)} لتر، يكفوا حوالي ${(l / avg * 100).round()} كيلو'));
    }
    if (has(['العداد', 'odometer'])) {
      final km = App.maintenance.odometerKm;
      return _say(km == null
          ? tr('العداد مش متسجل')
          : tr('العداد ${km.round()} كيلو'));
    }
    // Panels.
    if (has(['العدادات', 'gauges'])) return _show(_Panel.gauges);
    if (has(['الاعطال', 'عطل', 'faults', 'codes'])) return _show(_Panel.faults);
    if (has(['الصيانه', 'maintenance'])) return _show(_Panel.maintenance);
    if (has(['الرحلات', 'الرحله', 'trips', 'trip'])) return _show(_Panel.trips);

    _say(tr('مش فاهم. جرّب: وديني على مكان، الأعطال، الصيانة، الرحلات، أو السرعة كام'));
  }

  /// Hand the trip to Google Maps; this app floats on top with the gauges.
  Future<void> _googleMaps([LatLng? to]) async {
    final ok = await App.obd.bt
        .openGoogleMaps(to?.latitude, to?.longitude)
        .catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Google Maps مش متثبت'))));
    }
  }

  // ---------- head-unit home: now playing + car status ----------

  Widget _dashboard(BuildContext context) {
    return Column(children: [
      Expanded(
          flex: 3,
          child: _HeadCarCard(onOpen: () => _show(_Panel.gauges))),
      const SizedBox(height: 12),
      Expanded(
          flex: 2,
          child: _HeadTripCard(onOpen: () => _show(_Panel.trips))),
    ]);
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable(); // screen stays on only in drive mode
    App.road.start();
    App.obd.bt.setPipAllowed(true).catchError((_) {});
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    App.obd.bt.setPipAllowed(false).catchError((_) {});
    super.dispose();
  }

  /// Tiny floating window over Google Maps: speed, limit, coolant.
  Widget _pipView(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([App.obd, App.road, App.settings]),
      builder: (context, _) {
        final v = App.obd.values;
        final speed = v[Pids.speed];
        final limit = App.road.effectiveLimit;
        final over = (speed ?? 0) > limit && App.settings.speedAlertMode != 'off';
        final coolant = v[Pids.coolant];
        final hot = coolant != null && coolant >= App.settings.coolantAlert;
        return Container(
          color: Colors.black,
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: FittedBox(
                child: Text(fmt(speed),
                    style: TextStyle(
                        color: over ? const Color(0xFFFF3B30) : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.normal)),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: FittedBox(
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                              color: const Color(0xFFD32F2F), width: 5),
                        ),
                        child: Text('${limit.round()}',
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: FittedBox(
                      child: Text('${fmt(coolant)}°',
                          style: TextStyle(
                              color: hot
                                  ? const Color(0xFFFF3B30)
                                  : Colors.white70,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: BtChannel.pip,
      builder: (context, inPip, _) =>
          inPip ? _pipView(context) : _fullView(context),
    );
  }

  Widget _fullView(BuildContext context) {
    final obd = App.obd;
    final trips = App.trips;
    final s = App.settings;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: _huBg,
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([obd, trips, App.maintenance, App.fuel, s, App.road]),
          builder: (context, _) {
            final v = obd.values;
            final rpm = v[Pids.rpm];
            final coolant = v[Pids.coolant];
            final litres = App.fuel.litresNow;
            final level = litres == null ? null : litres / s.tankLiters * 100;
            final avg = App.fuel.realAvgL100 ?? trips.avgL100 ?? s.defaultL100;
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
                              fontWeight: FontWeight.w900,
                              fontStyle: FontStyle.normal,
                              color: color)),
                    ),
                    Text(unit,
                        style: TextStyle(
                            fontSize: 14, color: scheme.onSurfaceVariant)),
                  ],
                );

            return Padding(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  _HeadStatusBar(
                    onClose: () => Navigator.pop(context),
                    subtitle: _listening
                        ? '🎙️ ${_heard.isEmpty ? tr('بسمعك…') : _heard}'
                        : [
                            obd.status,
                            if (App.maintenance.odometerKm != null)
                              tr('العداد ${fmt(App.maintenance.odometerKm)} كم'),
                          ].join(' • '),
                  ),
                  const SizedBox(height: 6),
                  Expanded(child: Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Column(children: [ Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Speed: the biggest number on screen.
                        Expanded(
                          flex: 3,
                          child: Card(
                            child: Column(children: [
                              Expanded(
                                child: big(
                                  tr('السرعة'),
                                  fmt(v[Pids.speed]),
                                  tr('كم/س'),
                                  size: 140,
                                  color: (v[Pids.speed] ?? 0) > App.road.effectiveLimit &&
                                          s.speedAlertMode != 'off'
                                      ? AppColors.danger(context)
                                      : null,
                                ),
                              ),
                              // Quick speed-limit control for the current road.
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: '-10',
                                    iconSize: 32,
                                    onPressed: () =>
                                        s.setSpeedLimit(s.speedLimit - 10),
                                    icon: const Icon(Icons.remove_circle_outline),
                                  ),
                                  Container(
                                    width: 56,
                                    height: 56,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      border: Border.all(
                                          color: const Color(0xFFD32F2F),
                                          width: 6),
                                    ),
                                    child: Text(
                                      s.speedAlertMode == 'off'
                                          ? '—'
                                          : '${App.road.effectiveLimit.round()}',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '+10',
                                    iconSize: 32,
                                    onPressed: () =>
                                        s.setSpeedLimit(s.speedLimit + 10),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                              // Where the limit comes from, and the next camera.
                              Text(
                                App.road.limitIsAuto
                                    ? tr('حد الطريق تلقائي')
                                    : tr('الحد يدوي'),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                              if (App.road.nextCameraM != null &&
                                  App.road.nextCameraM! <= 1000)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD32F2F),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.camera_alt,
                                          color: Colors.white, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        tr('رادار ${(App.road.nextCameraM! / 10).round() * 10} متر'),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                            ]),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: _panel == _Panel.home
                              ? _dashboard(context)
                              : _panel == _Panel.faults
                                  ? const _Embedded(DtcPage())
                                  : _panel == _Panel.maintenance
                                      ? const _Embedded(MaintenancePage())
                                  : _panel == _Panel.trips
                                      ? const _Embedded(TripsPage())
                                      : Column(
                            children: [
                              Expanded(
                                child: Row(children: [
                                  Expanded(
                                    child: Card(
                                      child: big('RPM', fmt(rpm), tr('لفة/د'),
                                          color: redline
                                              ? AppColors.danger(context)
                                              : null),
                                    ),
                                  ),
                                  Expanded(
                                    child: Card(
                                      child: big(tr('حرارة المياه'), fmt(coolant),
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
                                        tr('البنزين'),
                                        fmt(litres, 1),
                                        range == null
                                            ? tr('لتر')
                                            : tr('لتر • ~${fmt(range)} كم'),
                                        color: level != null && level < 15
                                            ? AppColors.warning(context)
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Card(
                                      child: obd.instantL100 != null
                                          ? big(tr('الاستهلاك'),
                                              fmt(obd.instantL100, 1), tr('ل/100كم'))
                                          : big(tr('الاستهلاك'),
                                              fmt(obd.fuelRateLh, 2), tr('ل/ساعة')),
                                    ),
                                  ),
                                  Expanded(
                                    child: Card(
                                      child: big(
                                        tr('الرحلة'),
                                        fmt(trips.distanceKm, 1),
                                        trips.active
                                            ? tr('كم • ${fmt(trips.fuelL * s.fuelPrice)} ج.م')
                                            : tr('كم'),
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
                  ) ]))),
                  const SizedBox(height: 8),
                  _HeadNav(
                      current: _panel,
                      onPanel: (p) => _show(p, toggle: true),
                      onVoice: _voice,
                      listening: _listening),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

/// Shows a normal app page inside a drive-mode panel. It gets its own
/// navigator, so its back button and sub-pages stay inside the panel
/// instead of closing drive mode.
class _Embedded extends StatelessWidget {
  final Widget page;
  const _Embedded(this.page);

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(16),
        child: Navigator(
          onGenerateRoute: (_) => MaterialPageRoute(builder: (_) => page),
        ),
      );
}
