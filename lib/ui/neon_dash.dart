import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../main.dart';
import '../obd/pids.dart';
import 'seven_segment.dart';

const neonBg = Color(0xFF14171A);
const neonCyan = Color(0xFF2EE6D6);
const neonRed = Color(0xFFFF3B30);

/// Sporty digital dashboard for drive mode: a glowing speedometer (or a giant
/// digital speed, tap to switch) and trip stats in LCD digits.
class NeonDash extends StatefulWidget {
  const NeonDash({super.key});

  @override
  State<NeonDash> createState() => _NeonDashState();
}

class _NeonDashState extends State<NeonDash> {
  bool _digital = false;

  @override
  Widget build(BuildContext context) {
    final obd = App.obd;
    final trips = App.trips;
    final s = App.settings;
    final v = obd.values;
    final speed = v[Pids.speed] ?? 0;
    final limit = App.road.effectiveLimit;
    final over = s.speedAlertMode != 'off' && speed > limit;
    final color = over ? neonRed : neonCyan;

    final dur = trips.active && trips.startedAt != null
        ? DateTime.now().difference(trips.startedAt!)
        : Duration.zero;
    String two(int n) => n.toString().padLeft(2, '0');
    final durTxt =
        '${two(dur.inHours)}:${two(dur.inMinutes % 60)}:${two(dur.inSeconds % 60)}';
    final km = trips.distanceKm;
    final avgSpeed = dur.inSeconds > 30 ? km / (dur.inSeconds / 3600) : null;
    final coolant = v[Pids.coolant];
    final rpm = v[Pids.rpm];
    final litres = App.fuel.litresNow;

    String n(double? x, [int d = 0]) => x == null ? '--' : x.toStringAsFixed(d);

    final stats = [
      _Stat(Icons.timer_outlined, tr('المدة'), durTxt, ''),
      _Stat(Icons.route, tr('المسافة'), n(km, km < 100 ? 2 : 1), tr('كم')),
      _Stat(Icons.show_chart, tr('متوسط السرعة'), n(avgSpeed), tr('كم/س')),
      _Stat(Icons.speed, tr('أقصى سرعة'), n(trips.maxSpeed), tr('كم/س')),
      _Stat(Icons.rotate_right, 'RPM', n(rpm), ''),
      _Stat(Icons.thermostat, tr('الحرارة'), n(coolant), '°C',
          warn: coolant != null && coolant >= s.coolantAlert),
      _Stat(Icons.local_gas_station, tr('البنزين'), n(litres, 1), tr('لتر')),
      _Stat(Icons.water_drop_outlined, tr('الاستهلاك'),
          n(obd.instantL100 ?? obd.fuelRateLh, 1),
          obd.instantL100 != null ? tr('ل/100') : tr('ل/س')),
    ];

    final gauge = GestureDetector(
      onTap: () => setState(() => _digital = !_digital),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: speed),
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeOut,
        builder: (context, sp, _) => _digital
            ? _digitalSpeed(sp, color)
            : AspectRatio(
                aspectRatio: 1,
                child: CustomPaint(
                  painter: _GaugePainter(sp, limit,
                      s.speedAlertMode != 'off', color),
                  child: Center(
                    child: Column(mainAxisSize: MainAxisSize.min, children: [
                      const SizedBox(height: 8),
                      LayoutBuilder(builder: (context, c) {
                        final h = c.maxWidth * 0.26;
                        return SevenSeg(sp.round().toString(),
                            height: h.clamp(30, 130), color: color);
                      }),
                      const SizedBox(height: 10),
                      Text(tr('كم/س'),
                          style: TextStyle(color: color, fontSize: 18)),
                    ]),
                  ),
                ),
              ),
      ),
    );

    return Container(
      decoration: BoxDecoration(
        color: neonBg,
        borderRadius: BorderRadius.circular(16),
        gradient: const RadialGradient(
            center: Alignment(0, -0.4),
            radius: 1.1,
            colors: [Color(0xFF1E2328), neonBg]),
      ),
      padding: const EdgeInsets.all(8),
      child: LayoutBuilder(builder: (context, c) {
        final wide = c.maxWidth > c.maxHeight * 1.15;
        Widget grid(int cols) => _StatGrid(stats: stats, cols: cols);
        if (wide) {
          return Row(children: [
            Expanded(flex: 5, child: Center(child: gauge)),
            const SizedBox(width: 8),
            Expanded(flex: 6, child: grid(2)),
          ]);
        }
        return Column(children: [
          Expanded(flex: 6, child: Center(child: gauge)),
          Expanded(flex: 5, child: grid(2)),
        ]);
      }),
    );
  }

  Widget _digitalSpeed(double sp, Color color) => LayoutBuilder(
        builder: (context, c) {
          final h = math.min(c.maxHeight * 0.6, c.maxWidth / 2.1);
          return Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            FittedBox(
                child: SevenSeg(sp.round().toString().padLeft(3, ' '),
                    height: h, color: color)),
            const SizedBox(height: 12),
            Text(tr('كم/س'), style: TextStyle(color: color, fontSize: 22)),
          ]);
        },
      );
}

class _Stat {
  final IconData icon;
  final String label, value, unit;
  final bool warn;
  _Stat(this.icon, this.label, this.value, this.unit, {this.warn = false});
}

class _StatGrid extends StatelessWidget {
  final List<_Stat> stats;
  final int cols;
  const _StatGrid({required this.stats, required this.cols});

  @override
  Widget build(BuildContext context) {
    final rows = (stats.length / cols).ceil();
    const line = BorderSide(color: Color(0x22FFFFFF));
    return Column(children: [
      for (var r = 0; r < rows; r++)
        Expanded(
          child: Row(children: [
            for (var i = r * cols; i < math.min((r + 1) * cols, stats.length); i++)
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    border: Border(
                      bottom: r < rows - 1 ? line : BorderSide.none,
                      left: i % cols != 0 ? line : BorderSide.none,
                    ),
                  ),
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  child: _tile(stats[i]),
                ),
              ),
          ]),
        ),
    ]);
  }

  Widget _tile(_Stat s) {
    final c = s.warn ? neonRed : neonCyan;
    return LayoutBuilder(builder: (context, box) {
      final h = (box.maxHeight * 0.42).clamp(14.0, 44.0);
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(children: [
            Icon(s.icon, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Expanded(
              child: Text(s.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.white70, fontSize: 13)),
            ),
          ]),
          const SizedBox(height: 4),
          Flexible(
            child: FittedBox(
              fit: BoxFit.scaleDown,
              alignment: AlignmentDirectional.centerStart,
              child: Row(
                textDirection: TextDirection.ltr,
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  SevenSeg(s.value, height: h, color: c),
                  if (s.unit.isNotEmpty) ...[
                    const SizedBox(width: 6),
                    Text(s.unit, style: TextStyle(color: c, fontSize: 13)),
                  ],
                ],
              ),
            ),
          ),
        ],
      );
    });
  }
}

class _GaugePainter extends CustomPainter {
  final double speed, limit;
  final bool showLimit;
  final Color color;
  _GaugePainter(this.speed, this.limit, this.showLimit, this.color);

  static const max = 240.0;
  static const start = math.pi * 0.75; // bottom-left
  static const sweep = math.pi * 1.5; // 270°

  double _a(double v) => start + sweep * (v.clamp(0, max) / max);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final rad = size.shortestSide / 2;

    // Dark face.
    canvas.drawCircle(c, rad * 0.98, Paint()..color = const Color(0xFF181B1F));

    // Inner track + lit progress.
    final inner = Rect.fromCircle(center: c, radius: rad * 0.66);
    canvas.drawArc(inner, start, sweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rad * 0.07
          ..strokeCap = StrokeCap.round
          ..color = const Color(0xFF2A2F35));
    if (speed > 0.5) {
      canvas.drawArc(inner, start, _a(speed) - start, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = rad * 0.07
            ..strokeCap = StrokeCap.round
            ..color = color.withValues(alpha: 0.35));
    }

    // Outer scale: grey track, then orange→red zone from 140.
    final outer = Rect.fromCircle(center: c, radius: rad * 0.8);
    canvas.drawArc(outer, start, sweep, false,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = rad * 0.025
          ..color = const Color(0xFF33383E));
    // Hot zone drawn in small steps, orange → red.
    const steps = 40;
    for (var i = 0; i < steps; i++) {
      final v0 = 140 + (max - 140) * i / steps;
      final v1 = 140 + (max - 140) * (i + 1) / steps;
      canvas.drawArc(outer, _a(v0), _a(v1) - _a(v0) + 0.005, false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = rad * 0.035
            ..color = Color.lerp(const Color(0xFFFF7A1A),
                const Color(0xFFE01010), i / steps)!
                .withValues(alpha: i < 4 ? (i + 1) / 5 : 1));
    }

    // Ticks + labels.
    for (var k = 0; k <= max; k += 10) {
      final a = _a(k.toDouble());
      final major = k % 20 == 0;
      final dir = Offset(math.cos(a), math.sin(a));
      final p1 = c + dir * rad * (major ? 0.72 : 0.75);
      final p2 = c + dir * rad * 0.84;
      canvas.drawLine(
          p1,
          p2,
          Paint()
            ..strokeWidth = major ? rad * 0.022 : rad * 0.01
            ..strokeCap = StrokeCap.round
            ..color = major ? neonCyan : neonCyan.withValues(alpha: 0.4));
      if (k % 40 == 0) {
        final tp = TextPainter(
          text: TextSpan(
              text: '$k',
              style: TextStyle(
                  color: Colors.white,
                  fontSize: rad * 0.085,
                  fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout();
        final lp = c + dir * rad * 0.93;
        tp.paint(canvas, lp - Offset(tp.width / 2, tp.height / 2));
      }
    }

    // Speed-limit marker on the scale.
    if (showLimit && limit > 0 && limit < max) {
      final a = _a(limit);
      final dir = Offset(math.cos(a), math.sin(a));
      canvas.drawLine(c + dir * rad * 0.7, c + dir * rad * 0.86,
          Paint()
            ..strokeWidth = rad * 0.03
            ..strokeCap = StrokeCap.round
            ..color = neonRed);
    }

    // Glowing needle.
    final a = _a(speed);
    final dir = Offset(math.cos(a), math.sin(a));
    final n1 = c + dir * rad * 0.56, n2 = c + dir * rad * 0.8;
    canvas.drawLine(
        n1,
        n2,
        Paint()
          ..strokeWidth = rad * 0.07
          ..strokeCap = StrokeCap.round
          ..color = color.withValues(alpha: 0.6)
          ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, rad * 0.04));
    canvas.drawLine(
        n1,
        n2,
        Paint()
          ..strokeWidth = rad * 0.03
          ..strokeCap = StrokeCap.round
          ..color = Colors.white);
  }

  @override
  bool shouldRepaint(_GaugePainter o) =>
      o.speed != speed || o.limit != limit || o.color != color ||
      o.showLimit != showLimit;
}
