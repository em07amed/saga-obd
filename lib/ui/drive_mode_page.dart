import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../main.dart';
import '../obd/pids.dart';
import 'map_tiles.dart';
import 'sport_theme.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Full-screen landscape view for a phone on a dash mount: few, large numbers.
class DriveModePage extends StatefulWidget {
  const DriveModePage({super.key});

  @override
  State<DriveModePage> createState() => _DriveModePageState();
}

class _DriveModePageState extends State<DriveModePage> {
  bool _map = false;
  final _mapCtl = MapController();
  StreamSubscription<Position>? _gps;
  Position? _pos;
  final List<LatLng> _path = [];
  bool _follow = true;

  Future<void> _toggleMap() async {
    setState(() => _map = !_map);
    if (_map && _gps == null) {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen((p) {
        if (!mounted) return;
        final at = LatLng(p.latitude, p.longitude);
        setState(() {
          _pos = p;
          if (p.accuracy < 30) _path.add(at);
        });
        if (_map && _follow) {
          // Zoom out a little at speed so more road ahead is visible.
          final kmh = p.speed * 3.6;
          final zoom = kmh > 90 ? 15.0 : kmh > 50 ? 16.0 : 17.0;
          try {
            _mapCtl.move(at, zoom);
          } catch (_) {}
        }
      });
    }
  }

  Widget _liveMap(BuildContext context) {
    final p = _pos;
    final scheme = Theme.of(context).colorScheme;
    if (p == null) {
      return Card(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(tr('بيدوّر على موقعك…')),
          ]),
        ),
      );
    }
    final at = LatLng(p.latitude, p.longitude);
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FlutterMap(
          mapController: _mapCtl,
          options: MapOptions(
            initialCenter: at,
            initialZoom: 17,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onPositionChanged: (_, byUser) {
              if (byUser && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            mapTiles(context),
            if (_path.length > 1)
              PolylineLayer(polylines: [
                Polyline(points: _path, color: scheme.primary, strokeWidth: 5),
              ]),
            MarkerLayer(markers: [
              Marker(
                point: at,
                width: 40,
                height: 40,
                child: Transform.rotate(
                  angle: (p.heading.isNaN ? 0 : p.heading) * 3.14159265 / 180,
                  child: Icon(Icons.navigation,
                      size: 40,
                      color: scheme.primary,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black54)
                      ]),
                ),
              ),
            ]),
            mapAttribution(),
          ],
        ),
        if (!_follow)
          PositionedDirectional(
            bottom: 12,
            end: 12,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              tooltip: tr('تتبّع موقعي'),
              onPressed: () {
                setState(() => _follow = true);
                _mapCtl.move(at, 17);
              },
              child: const Icon(Icons.my_location),
            ),
          ),
      ]),
    );
  }

  @override
  void initState() {
    super.initState();
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable(); // screen stays on only in drive mode
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    _gps?.cancel();
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
          listenable: Listenable.merge([obd, trips, App.maintenance, App.fuel, s]),
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
                              fontStyle: isSport(context)
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              color: color)),
                    ),
                    Text(unit,
                        style: TextStyle(
                            fontSize: 14, color: scheme.onSurfaceVariant)),
                  ],
                );

            return Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: tr('خروج'),
                        iconSize: 28,
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close),
                      ),
                      IconButton.filledTonal(
                        tooltip: _map ? tr('العدادات') : tr('الخريطة'),
                        iconSize: 26,
                        onPressed: _toggleMap,
                        icon: Icon(_map ? Icons.speed : Icons.map),
                      ),
                      Expanded(
                        child: Text('${s.vehicle.name} • ${obd.status}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                      if (App.maintenance.odometerKm != null)
                        Text(tr('العداد ${fmt(App.maintenance.odometerKm)} كم'),
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  // Shift light: 12 blocks, green → amber → red up to 6000 rpm.
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        for (var i = 0; i < 12; i++)
                          Expanded(
                            child: Container(
                              height: 10,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                color: (rpm ?? 0) >= 6000 * (i + 1) / 12
                                    ? (i < 7
                                        ? AppColors.ok(context)
                                        : i < 10
                                            ? AppColors.warning(context)
                                            : AppColors.danger(context))
                                    : scheme.outlineVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
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
                                  color: (v[Pids.speed] ?? 0) > s.speedLimit &&
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
                                          : '${s.speedLimit.round()}',
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
                              const SizedBox(height: 8),
                            ]),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: _map ? _liveMap(context) : Column(
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
                  ),
                  // Car-home dock, like a head unit: other apps + media.
                  const SizedBox(height: 8),
                  _Dock(),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  @override
  Widget build(BuildContext context) {
    final bt = App.obd.bt;
    final scheme = Theme.of(context).colorScheme;

    Widget btn(IconData icon, String label, VoidCallback onTap,
            {bool accent = false}) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: accent ? scheme.primary : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                child: SizedBox(
                  height: 56,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 28,
                          color: accent ? scheme.onPrimary : scheme.onSurface),
                      if (label.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: accent
                                      ? scheme.onPrimary
                                      : scheme.onSurface)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    Future<void> open(String kind) async {
      final ok = await bt.launch(kind).catchError((_) => false);
      if (!ok && context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('مفيش تطبيق مناسب على الموبايل'))));
      }
    }

    return Row(children: [
      btn(Icons.navigation, tr('خرائط'), () => open('maps')),
      btn(Icons.skip_previous, '', () => bt.mediaKey('prev')),
      btn(Icons.play_arrow, '', () => bt.mediaKey('play_pause'), accent: true),
      btn(Icons.skip_next, '', () => bt.mediaKey('next')),
      btn(Icons.library_music, tr('موسيقى'), () => open('music')),
      btn(Icons.call, tr('مكالمة'), () => open('dialer')),
      btn(Icons.mic, tr('المساعد'), () => open('assistant')),
    ]);
  }
}
