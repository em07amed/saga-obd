import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng, Distance, LengthUnit;
import 'package:intl/intl.dart' show DateFormat;

import '../main.dart';
import '../trips/trip_db.dart';
import 'map_tiles.dart';
import 'widgets.dart';
import '../l10n.dart';

DateFormat get _dateFmt => DateFormat('EEE d MMM • h:mm a', Lang.code);

class TripsPage extends StatefulWidget {
  const TripsPage({super.key});

  @override
  State<TripsPage> createState() => _TripsPageState();
}

class _TripsPageState extends State<TripsPage> {
  late Future<List<Trip>> _future;
  int _seen = -1;

  @override
  void initState() {
    super.initState();
    _reload();
    App.trips.addListener(_onRecorder);
    App.settings.addListener(_onRecorder);
  }

  int? _vehicle;

  void _onRecorder() {
    if (App.trips.finishedCount != _seen ||
        App.settings.vehicle.id != _vehicle) {
      setState(_reload);
    }
  }

  void _reload() {
    _seen = App.trips.finishedCount;
    _vehicle = App.settings.vehicle.id;
    _future = App.db.trips(_vehicle ?? 0);
  }

  @override
  void dispose() {
    App.trips.removeListener(_onRecorder);
    App.settings.removeListener(_onRecorder);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RefreshIndicator(
      onRefresh: () async {
        setState(_reload);
        await _future;
      },
      child: FutureBuilder<List<Trip>>(
        future: _future,
        builder: (context, snap) {
          final trips = (snap.data ?? [])
              .where((t) => t.endedAt != null)
              .toList();
          if (snap.connectionState != ConnectionState.done) {
            return Center(child: CircularProgressIndicator());
          }
          if (trips.isEmpty) {
            return ListView(children: [
              SizedBox(height: 200),
              Center(child: Text(tr('لسه مفيش رحلات مسجلة'))),
            ]);
          }
          return ListView(
            padding: EdgeInsets.all(8),
            children: [
              _MonthSummary(trips: trips),
              for (final t in trips)
                Card(
                  child: ListTile(
                    title: Text(_dateFmt.format(t.startedAt)),
                    subtitle: Text(tr('${fmt(t.distanceKm, 1)} كم • '
                        '${fmtDuration(t.duration)} • '
                        '${fmt(t.avgL100, 1)} ل/100')),
                    trailing: Text(tr('${fmt(t.cost)} ج.م'),
                        style: Theme.of(context).textTheme.titleMedium),
                    onTap: () async {
                      await Navigator.of(context).push(MaterialPageRoute(
                          builder: (_) => TripDetailPage(trip: t)));
                      setState(_reload);
                    },
                  ),
                ),
            ],
          );
        },
      ),
    );
  }
}

class _MonthSummary extends StatelessWidget {
  final List<Trip> trips;
  _MonthSummary({required this.trips});

  @override
  Widget build(BuildContext context) {
    final now = DateTime.now();
    final month = trips.where(
        (t) => t.startedAt.year == now.year && t.startedAt.month == now.month);
    final km = month.fold<double>(0, (s, t) => s + t.distanceKm);
    final fuel = month.fold<double>(0, (s, t) => s + t.fuelL);
    final cost = month.fold<double>(0, (s, t) => s + t.cost);
    return Card(
      color: Theme.of(context).colorScheme.primaryContainer,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(tr('${App.settings.vehicle.name} • الشهر ده (${month.length} رحلة)'),
                style: Theme.of(context).textTheme.titleMedium),
            SizedBox(height: 8),
            Text(tr('${fmt(km)} كم • ${fmt(fuel, 1)} لتر • ${fmt(cost)} ج.م')),
            Text(tr('متوسط الاستهلاك: ${km > 1 ? fmt(fuel / km * 100, 1) : '—'} ل/100كم')),
          ],
        ),
      ),
    );
  }
}

class TripDetailPage extends StatelessWidget {
  final Trip trip;
  const TripDetailPage({super.key, required this.trip});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_dateFmt.format(trip.startedAt)),
        actions: [
          IconButton(
            icon: Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: Text(tr('حذف الرحلة؟')),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: Text(tr('إلغاء'))),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: Text(tr('حذف'))),
                  ],
                ),
              );
              if (ok == true) {
                await App.db.deleteTrip(trip.id);
                if (context.mounted) Navigator.pop(context);
              }
            },
          ),
        ],
      ),
      body: FutureBuilder<List<TripSample>>(
        future: App.db.samples(trip.id),
        builder: (context, snap) {
          final samples = snap.data ?? <TripSample>[];
          final route = samples
              .where((s) => s.lat != null && s.lng != null)
              .toList();
          return ListView(
            padding: EdgeInsets.all(8),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: NeverScrollableScrollPhysics(),
                childAspectRatio: 1.6,
                children: [
                  StatTile(
                      label: tr('المسافة'),
                      value: fmt(trip.distanceKm, 1),
                      unit: tr('كم'),
                      sub: trip.gpsKm > 0.3
                          ? tr('GPS • عداد OBD ${fmt(trip.obdKm, 1)}')
                          : tr('من عداد السرعة')),
                  StatTile(
                      label: tr('المدة'),
                      value: fmtDuration(trip.duration),
                      sub: tr('وقوف ${fmtDuration(Duration(seconds: trip.idleSec))}')),
                  StatTile(
                      label: tr('البنزين'),
                      value: fmt(trip.fuelL, 2),
                      unit: tr('لتر')),
                  StatTile(
                      label: tr('متوسط الاستهلاك'),
                      value: fmt(trip.avgL100, 1),
                      unit: tr('ل/100')),
                  StatTile(
                      label: tr('التكلفة'),
                      value: fmt(trip.cost),
                      unit: tr('ج.م'),
                      sub: trip.fuelPrice > 0
                          ? tr('سعر اللتر ${fmt(trip.fuelPrice, 2)}')
                          : tr('حدد سعر اللتر من الإعدادات')),
                  StatTile(
                      label: tr('أقصى سرعة / حرارة'),
                      value: fmt(trip.maxSpeed),
                      unit: tr('كم/س'),
                      sub: tr('أعلى حرارة مياه ${fmt(trip.maxCoolant)}°C')),
                ],
              ),
              if (route.length > 1) ...[
                SizedBox(height: 8),
                Text(tr('  خط السير (ملون بالسرعة)')),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(height: 360, child: _RouteMap(route)),
                ),
              ],
              if (samples.length > 1) ...[
                SizedBox(height: 8),
                Text(tr('  السرعة خلال الرحلة')),
                Card(
                  child: SizedBox(
                    height: 160,
                    child: Padding(
                      padding: EdgeInsets.all(12),
                      child: CustomPaint(
                        painter: _LinePainter(
                          samples.map((s) => s.speed ?? 0.0).toList(),
                          Theme.of(context).colorScheme.primary,
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

/// Real street map (OpenStreetMap) with the route coloured by speed.
class _RouteMap extends StatefulWidget {
  final List<TripSample> pts;
  const _RouteMap(this.pts);

  @override
  State<_RouteMap> createState() => _RouteMapState();
}

/// A stretch of the trip: over the speed limit, or stopped.
class _Event {
  final TripSample at;
  final bool speeding;
  final double value; // max speed, or stop seconds
  const _Event(this.at, this.speeding, this.value);
}

class _RouteMapState extends State<_RouteMap> {
  TripSample? _picked;
  late final List<_Event> _events = _findEvents();

  static Color _speedColor(double? kmh) => Color.lerp(AppColors.routeSlow,
      AppColors.routeFast, ((kmh ?? 0) / 120).clamp(0.0, 1.0))!;

  /// Over-limit stretches (marked at their top speed) and stops of 1 min+.
  List<_Event> _findEvents() {
    final limit = App.settings.speedLimit;
    final out = <_Event>[];
    TripSample? peak;
    TripSample? stopStart;
    for (final p in widget.pts) {
      final v = p.speed ?? 0;
      if (v > limit) {
        if (peak == null || v > (peak.speed ?? 0)) peak = p;
      } else if (peak != null) {
        out.add(_Event(peak, true, peak.speed ?? 0));
        peak = null;
      }
      if (v < 1) {
        stopStart ??= p;
      } else if (stopStart != null) {
        final secs = p.ts.difference(stopStart.ts).inSeconds;
        if (secs >= 60) out.add(_Event(stopStart, false, secs.toDouble()));
        stopStart = null;
      }
    }
    if (peak != null) out.add(_Event(peak, true, peak.speed ?? 0));
    return out;
  }

  void _onTap(LatLng at) {
    const d = Distance();
    TripSample? best;
    var bestM = double.infinity;
    for (final p in widget.pts) {
      final m = d.as(LengthUnit.Meter, at, LatLng(p.lat!, p.lng!));
      if (m < bestM) {
        bestM = m;
        best = p;
      }
    }
    setState(() => _picked = bestM < 150 ? best : null);
  }

  @override
  Widget build(BuildContext context) {
    final pts = widget.pts;
    final points = [for (final p in pts) LatLng(p.lat!, p.lng!)];
    final segments = <Polyline>[
      for (var i = 1; i < points.length; i++)
        Polyline(
          points: [points[i - 1], points[i]],
          color: _speedColor(pts[i].speed),
          strokeWidth: 5,
        ),
    ];
    final picked = _picked;
    final speeding = _events.where((e) => e.speeding).length;
    final stops = _events.length - speeding;

    return Stack(children: [
      FlutterMap(
        options: MapOptions(
          initialCameraFit: points.length > 1
              ? CameraFit.bounds(
                  bounds: LatLngBounds.fromPoints(points),
                  padding: const EdgeInsets.all(40),
                )
              : null,
          initialCenter: points.first,
          initialZoom: 15,
          interactionOptions: const InteractionOptions(
            flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
          ),
          onTap: (_, at) => _onTap(at),
        ),
        children: [
          mapTiles(context),
          PolylineLayer(polylines: segments),
          MarkerLayer(markers: [
            for (final e in _events)
              Marker(
                point: LatLng(e.at.lat!, e.at.lng!),
                width: 26,
                height: 26,
                child: GestureDetector(
                  onTap: () => setState(() => _picked = e.at),
                  child: e.speeding
                      ? mapPin(AppColors.danger(context), Icons.speed, size: 14)
                      : mapPin(const Color(0xFF546E7A), Icons.local_parking,
                          size: 14),
                ),
              ),
            Marker(
              point: points.first,
              width: 28,
              height: 28,
              child: mapPin(const Color(0xFF006A60), Icons.play_arrow),
            ),
            Marker(
              point: points.last,
              width: 28,
              height: 28,
              child: mapPin(AppColors.routeFast, Icons.flag),
            ),
            if (picked != null)
              Marker(
                point: LatLng(picked.lat!, picked.lng!),
                width: 18,
                height: 18,
                child: Container(
                  decoration: BoxDecoration(
                    color: Theme.of(context).colorScheme.primary,
                    shape: BoxShape.circle,
                    border: Border.all(color: Colors.white, width: 3),
                  ),
                ),
              ),
          ]),
          mapAttribution(),
        ],
      ),
      // Summary chips.
      PositionedDirectional(
        top: 8,
        start: 8,
        child: Wrap(spacing: 6, children: [
          if (speeding > 0)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: Icon(Icons.speed,
                  size: 16, color: AppColors.danger(context)),
              label: Text(tr('$speeding مرة فوق ${App.settings.speedLimit.round()}')),
            ),
          if (stops > 0)
            Chip(
              visualDensity: VisualDensity.compact,
              avatar: const Icon(Icons.local_parking, size: 16),
              label: Text(tr('$stops وقفة')),
            ),
        ]),
      ),
      // Details of the tapped point.
      if (picked != null)
        PositionedDirectional(
          bottom: 24,
          start: 8,
          end: 8,
          child: Card(
            child: ListTile(
              dense: true,
              leading: const Icon(Icons.place),
              title: Text(
                  '${fmt(picked.speed)} km/h • ${fmt(picked.rpm)} rpm • ${fmt(picked.coolant)} °C',
                  textDirection: TextDirection.ltr),
              subtitle: Text(_time.format(picked.ts)),
              trailing: IconButton(
                icon: const Icon(Icons.close),
                onPressed: () => setState(() => _picked = null),
              ),
            ),
          ),
        ),
    ]);
  }
}

DateFormat get _time => DateFormat('h:mm:ss a', Lang.code);

class _LinePainter extends CustomPainter {
  final List<double> values;
  final Color color;
  _LinePainter(this.values, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final maxV = math.max(values.reduce(math.max), 1.0);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = size.width * i / (values.length - 1);
      final y = size.height * (1 - values[i] / maxV);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
        path,
        Paint()
          ..color = color
          ..style = PaintingStyle.stroke
          ..strokeWidth = 2);
    final tp = TextPainter(
      text: TextSpan(
          text: tr('${maxV.toStringAsFixed(0)} كم/س'),
          style: TextStyle(fontSize: 11, color: color)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values;
}
