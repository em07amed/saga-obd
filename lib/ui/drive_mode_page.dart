import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../main.dart';
import '../obd/pids.dart';
import '../nav/nav_service.dart';
import 'drive_panels.dart';
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

enum _Panel { gauges, map, music, phone }

class _DriveModePageState extends State<DriveModePage> {
  _Panel _panel = _Panel.gauges;
  bool get _map => _panel == _Panel.map;
  final _search = TextEditingController();
  List<Place>? _results;
  bool _searching = false;

  void _show(_Panel p) {
    setState(() => _panel = _panel == p ? _Panel.gauges : p);
    if (p == _Panel.map) _startGps();
  }

  Future<void> _doSearch(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _searching = true);
    try {
      final p = _pos;
      final r = await App.nav
          .search(q, p == null ? null : LatLng(p.latitude, p.longitude));
      if (mounted) setState(() => _results = r);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('البحث محتاج نت'))));
      }
    }
    if (mounted) setState(() => _searching = false);
  }

  Future<void> _go(Place place) async {
    final p = _pos;
    if (p == null) return;
    setState(() {
      _results = null;
      _follow = true;
    });
    FocusScope.of(context).unfocus();
    await App.nav.start(place, LatLng(p.latitude, p.longitude));
  }
  final _mapCtl = MapController();
  StreamSubscription<Position>? _gps;
  Position? _pos;
  final List<LatLng> _path = [];
  bool _follow = true;

  Future<void> _startGps() async {
    if (_gps == null) {
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
        App.nav.update(at); // turn-by-turn keeps running on any panel
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
    final nav = App.nav;
    final step = nav.next;
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
            if (nav.route.length > 1)
              PolylineLayer(polylines: [
                Polyline(
                    points: nav.route,
                    color: const Color(0xFF1E88E5),
                    strokeWidth: 8,
                    borderColor: Colors.white,
                    borderStrokeWidth: 2),
              ]),
            if (_path.length > 1)
              PolylineLayer(polylines: [
                Polyline(points: _path, color: scheme.primary, strokeWidth: 5),
              ]),
            MarkerLayer(markers: [
              if (nav.destination != null)
                Marker(
                  point: nav.destination!.at,
                  width: 34,
                  height: 34,
                  child: mapPin(const Color(0xFFD32F2F), Icons.flag),
                ),
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
        // Turn-by-turn banner while navigating, search bar otherwise.
        if (nav.active && step != null)
          PositionedDirectional(
            top: 8,
            start: 8,
            end: 8,
            child: Material(
              color: const Color(0xFF1E88E5),
              borderRadius: BorderRadius.circular(14),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Icon(step.icon, size: 44, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(NavService.fmtDist(nav.toNextM),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900)),
                        Text(tr(step.text),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          )
        else
          PositionedDirectional(
            top: 8,
            start: 8,
            end: 8,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(28),
              color: scheme.surface,
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: _doSearch,
                decoration: InputDecoration(
                  hintText: tr('رايح فين؟'),
                  prefixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)))
                      : const Icon(Icons.search),
                  suffixIcon: _results != null
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _results = null))
                      : null,
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        if (_results != null && !nav.active)
          PositionedDirectional(
            top: 64,
            start: 8,
            end: 8,
            bottom: 8,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(14),
              color: scheme.surface,
              child: _results!.isEmpty
                  ? Center(child: Text(tr('ما لقيتش نتايج')))
                  : ListView(children: [
                      for (final r in _results!)
                        ListTile(
                          leading: const Icon(Icons.place),
                          title: Text(r.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(r.detail,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _go(r),
                        ),
                    ]),
            ),
          ),
        if (nav.routing)
          const Center(child: CircularProgressIndicator()),
        if (nav.error != null)
          PositionedDirectional(
            bottom: 60,
            start: 8,
            end: 8,
            child: Card(
                child: ListTile(
                    leading: const Icon(Icons.wifi_off),
                    title: Text(nav.error!))),
          ),
        // Remaining distance / time and stop button.
        if (nav.active)
          PositionedDirectional(
            bottom: 8,
            start: 8,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(24),
              color: scheme.surface,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                      '${NavService.fmtDist(nav.remainingM)} • ${nav.remaining.inMinutes} ${tr('د')}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  TextButton.icon(
                    onPressed: nav.stop,
                    icon: Icon(Icons.close, color: AppColors.danger(context)),
                    label: Text(tr('إنهاء'),
                        style: TextStyle(color: AppColors.danger(context))),
                  ),
                ]),
              ),
            ),
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
    _startGps();
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    _gps?.cancel();
    _search.dispose();
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
          listenable: Listenable.merge([obd, trips, App.maintenance, App.fuel, s, App.nav]),
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
                          child: _panel == _Panel.map
                              ? _liveMap(context)
                              : _panel == _Panel.music
                                  ? const MusicPanel()
                                  : _panel == _Panel.phone
                                      ? const PhonePanel()
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
                  ),
                  // Car-home dock, like a head unit: other apps + media.
                  const SizedBox(height: 8),
                  _Dock(current: _panel, onPanel: _show),
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
  final _Panel current;
  final void Function(_Panel) onPanel;
  const _Dock({required this.current, required this.onPanel});

  @override
  Widget build(BuildContext context) {
    final bt = App.obd.bt;
    final scheme = Theme.of(context).colorScheme;

    Widget btn(IconData icon, String label, VoidCallback onTap,
            {bool active = false}) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: active ? scheme.primary : scheme.surfaceContainerHighest,
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
                          color: active ? scheme.onPrimary : scheme.onSurface),
                      if (label.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: active
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

    return Row(children: [
      btn(Icons.speed, tr('العدادات'), () => onPanel(_Panel.gauges),
          active: current == _Panel.gauges),
      btn(Icons.navigation, tr('خرائط'), () => onPanel(_Panel.map),
          active: current == _Panel.map),
      btn(Icons.library_music, tr('موسيقى'), () => onPanel(_Panel.music),
          active: current == _Panel.music),
      btn(Icons.call, tr('مكالمة'), () => onPanel(_Panel.phone),
          active: current == _Panel.phone),
      btn(Icons.play_arrow, '', () => bt.mediaControl('play_pause')),
      btn(Icons.mic, tr('المساعد'), () => bt.launch('assistant')),
    ]);
  }
}
