import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

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
  }

  void _onRecorder() {
    if (App.trips.finishedCount != _seen) setState(_reload);
  }

  void _reload() {
    _seen = App.trips.finishedCount;
    _future = App.db.trips();
  }

  @override
  void dispose() {
    App.trips.removeListener(_onRecorder);
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
            Text('الشهر ده (${month.length} رحلة)',
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
                  child: AspectRatio(
                    aspectRatio: 1,
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: CustomPaint(painter: _RoutePainter(route)),
                    ),
                  ),
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

/// Draws GPS points scaled to fit, coloured green→red by speed.
class _RoutePainter extends CustomPainter {
  final List<TripSample> pts;
  _RoutePainter(this.pts);

  @override
  void paint(Canvas canvas, Size size) {
    var minLat = pts.first.lat!, maxLat = minLat;
    var minLng = pts.first.lng!, maxLng = minLng;
    for (final p in pts) {
      minLat = math.min(minLat, p.lat!);
      maxLat = math.max(maxLat, p.lat!);
      minLng = math.min(minLng, p.lng!);
      maxLng = math.max(maxLng, p.lng!);
    }
    // Longitude degrees shrink with latitude.
    final kx = math.cos((minLat + maxLat) / 2 * math.pi / 180);
    final w = math.max((maxLng - minLng) * kx, 1e-6);
    final h = math.max(maxLat - minLat, 1e-6);
    final scale = math.min(size.width / w, size.height / h);
    final ox = (size.width - w * scale) / 2;
    final oy = (size.height - h * scale) / 2;

    Offset at(TripSample p) => Offset(
          ox + (p.lng! - minLng) * kx * scale,
          oy + (maxLat - p.lat!) * scale,
        );

    final paint = Paint()
      ..strokeWidth = 4
      ..strokeCap = StrokeCap.round;
    for (var i = 1; i < pts.length; i++) {
      final t = ((pts[i].speed ?? 0.0) / 120).clamp(0.0, 1.0);
      paint.color = Color.lerp(AppColors.routeSlow, AppColors.routeFast, t)!;
      canvas.drawLine(at(pts[i - 1]), at(pts[i]), paint);
    }
    canvas.drawCircle(at(pts.first), 6, Paint()..color = const Color(0xFF171D1B));
    canvas.drawCircle(at(pts.last), 6, Paint()..color = AppColors.routeFast);
  }

  @override
  bool shouldRepaint(_RoutePainter old) => old.pts != pts;
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
          style: const TextStyle(fontSize: 11, color: Color(0xFF4A5552))),
      textDirection: TextDirection.rtl,
    )..layout();
    tp.paint(canvas, Offset.zero);
  }

  @override
  bool shouldRepaint(_LinePainter old) => old.values != values;
}
