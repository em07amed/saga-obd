import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:intl/intl.dart' show DateFormat;

import '../main.dart';
import '../trips/trip_db.dart';
import 'widgets.dart';

final _dateFmt = DateFormat('EEE d MMM • h:mm a', 'ar');

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
            return const Center(child: CircularProgressIndicator());
          }
          if (trips.isEmpty) {
            return ListView(children: const [
              SizedBox(height: 200),
              Center(child: Text('لسه مفيش رحلات مسجلة')),
            ]);
          }
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              _MonthSummary(trips: trips),
              for (final t in trips)
                Card(
                  child: ListTile(
                    title: Text(_dateFmt.format(t.startedAt)),
                    subtitle: Text('${fmt(t.distanceKm, 1)} كم • '
                        '${fmtDuration(t.duration)} • '
                        '${fmt(t.avgL100, 1)} ل/100'),
                    trailing: Text('${fmt(t.cost)} ج.م',
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
  const _MonthSummary({required this.trips});

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
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('${App.settings.vehicle.name} • الشهر ده (${month.length} رحلة)',
                style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            Text('${fmt(km)} كم • ${fmt(fuel, 1)} لتر • ${fmt(cost)} ج.م'),
            Text('متوسط الاستهلاك: ${km > 1 ? fmt(fuel / km * 100, 1) : '—'} ل/100كم'),
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
            icon: const Icon(Icons.delete_outline),
            onPressed: () async {
              final ok = await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text('حذف الرحلة؟'),
                  actions: [
                    TextButton(
                        onPressed: () => Navigator.pop(ctx, false),
                        child: const Text('إلغاء')),
                    FilledButton(
                        onPressed: () => Navigator.pop(ctx, true),
                        child: const Text('حذف')),
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
          final samples = snap.data ?? const <TripSample>[];
          final route = samples
              .where((s) => s.lat != null && s.lng != null)
              .toList();
          return ListView(
            padding: const EdgeInsets.all(8),
            children: [
              GridView.count(
                crossAxisCount: 2,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                childAspectRatio: 1.6,
                children: [
                  StatTile(
                      label: 'المسافة',
                      value: fmt(trip.distanceKm, 1),
                      unit: 'كم',
                      sub: trip.gpsKm > 0.3
                          ? 'GPS • عداد OBD ${fmt(trip.obdKm, 1)}'
                          : 'من عداد السرعة'),
                  StatTile(
                      label: 'المدة',
                      value: fmtDuration(trip.duration),
                      sub: 'وقوف ${fmtDuration(Duration(seconds: trip.idleSec))}'),
                  StatTile(
                      label: 'البنزين',
                      value: fmt(trip.fuelL, 2),
                      unit: 'لتر'),
                  StatTile(
                      label: 'متوسط الاستهلاك',
                      value: fmt(trip.avgL100, 1),
                      unit: 'ل/100'),
                  StatTile(
                      label: 'التكلفة',
                      value: fmt(trip.cost),
                      unit: 'ج.م',
                      sub: trip.fuelPrice > 0
                          ? 'سعر اللتر ${fmt(trip.fuelPrice, 2)}'
                          : 'حدد سعر اللتر من الإعدادات'),
                  StatTile(
                      label: 'أقصى سرعة / حرارة',
                      value: fmt(trip.maxSpeed),
                      unit: 'كم/س',
                      sub: 'أعلى حرارة مياه ${fmt(trip.maxCoolant)}°C'),
                ],
              ),
              if (route.length > 1) ...[
                const SizedBox(height: 8),
                const Text('  خط السير (ملون بالسرعة)'),
                Card(
                  clipBehavior: Clip.antiAlias,
                  child: SizedBox(height: 360, child: _RouteMap(route)),
                ),
              ],
              if (samples.length > 1) ...[
                const SizedBox(height: 8),
                const Text('  السرعة خلال الرحلة'),
                Card(
                  child: SizedBox(
                    height: 160,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
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
class _RouteMap extends StatelessWidget {
  final List<TripSample> pts;
  const _RouteMap(this.pts);

  static Color _speedColor(double? kmh) => Color.lerp(AppColors.routeSlow,
      AppColors.routeFast, ((kmh ?? 0) / 120).clamp(0.0, 1.0))!;

  @override
  Widget build(BuildContext context) {
    final points = [for (final p in pts) LatLng(p.lat!, p.lng!)];
    final dark = Theme.of(context).brightness == Brightness.dark;

    // One short polyline per segment so each can carry its own colour.
    final segments = <Polyline>[
      for (var i = 1; i < points.length; i++)
        Polyline(
          points: [points[i - 1], points[i]],
          color: _speedColor(pts[i].speed),
          strokeWidth: 5,
        ),
    ];

    Widget pin(Color c, IconData icon) => Container(
          decoration: BoxDecoration(
            color: c,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
          ),
          child: Icon(icon, size: 16, color: Colors.white),
        );

    return FlutterMap(
      options: MapOptions(
        initialCameraFit: points.length > 1
            ? CameraFit.bounds(
                bounds: LatLngBounds.fromPoints(points),
                padding: const EdgeInsets.all(32),
              )
            : null,
        initialCenter: points.first,
        initialZoom: 15,
        interactionOptions: const InteractionOptions(
          flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
        ),
      ),
      children: [
        TileLayer(
          urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
          userAgentPackageName: 'com.ezzat.obd_saga',
          tileBuilder: dark ? darkModeTileBuilder : null,
        ),
        PolylineLayer(polylines: segments),
        MarkerLayer(markers: [
          Marker(
            point: points.first,
            width: 28,
            height: 28,
            child: pin(const Color(0xFF006A60), Icons.play_arrow),
          ),
          Marker(
            point: points.last,
            width: 28,
            height: 28,
            child: pin(AppColors.routeFast, Icons.flag),
          ),
        ]),
        const SimpleAttributionWidget(
          source: Text('OpenStreetMap contributors'),
        ),
      ],
    );
  }
}

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
          text: '${maxV.toStringAsFixed(0)} كم/س',
          style: TextStyle(fontSize: 11, color: color)),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values;
}
