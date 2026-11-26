import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';
import '../obd/obd_service.dart';
import '../l10n.dart';
import 'sport_theme.dart';

/// Status colours with enough contrast in both light and dark themes.
class AppColors {
  static bool _dark(BuildContext c) =>
      Theme.of(c).brightness == Brightness.dark;
  static Color danger(BuildContext c) => isSport(c)
      ? const Color(0xFFFF3B30)
      : _dark(c)
          ? const Color(0xFFFF8A80)
          : const Color(0xFFC62828);
  static Color warning(BuildContext c) => isSport(c)
      ? const Color(0xFFFFB020)
      : _dark(c)
          ? const Color(0xFFFFB870)
          : const Color(0xFF9A5B00);
  static Color ok(BuildContext c) => isSport(c)
      ? const Color(0xFF3DDC84)
      : _dark(c)
          ? const Color(0xFF7BD88F)
          : const Color(0xFF1E7A34);
  static const routeSlow = Color(0xFF2E9E4A);
  static const routeFast = Color(0xFFD32F2F);
}

String fmt(double? v, [int decimals = 0]) =>
    v == null || v.isNaN || v.isInfinite ? '—' : v.toStringAsFixed(decimals);

String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? tr('$h س $m د') : tr('$m د');
}

/// Status strip with connect / disconnect button.
class ConnectionBar extends StatelessWidget {
  const ConnectionBar({super.key});

  @override
  Widget build(BuildContext context) {
    final obd = App.obd;
    return ListenableBuilder(
      listenable: obd,
      builder: (context, _) {
        final scheme = Theme.of(context).colorScheme;
        final busy = obd.state == ObdState.connecting ||
            obd.state == ObdState.initializing;
        final color = switch (obd.state) {
          ObdState.connected => AppColors.ok(context),
          ObdState.disconnected => scheme.error,
          _ => AppColors.warning(context),
        };
        return Container(
          padding: EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: scheme.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(Icons.bluetooth, color: color, size: 20),
              SizedBox(width: 8),
              Expanded(
                child: Text(obd.status,
                    maxLines: 3, overflow: TextOverflow.ellipsis),
              ),
              if (busy)
                SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else if (obd.isConnected)
                TextButton(
                    onPressed: obd.disconnect, child: Text(tr('فصل')))
              else
                FilledButton(
                    onPressed: obd.connect, child: Text(tr('اتصال'))),
            ],
          ),
        );
      },
    );
  }
}

/// Arc gauge with a red zone. In the default (sport) theme it is drawn like
/// the app icon: a glowing amber arc, white major ticks with numbers, amber
/// minor ticks, and a big upright number in a dark centre disc.
class Gauge extends StatelessWidget {
  final String label;
  final String unit;
  final double? value;
  final double min;
  final double max;
  final double? redFrom;
  final int decimals;

  /// Full-size hero gauge: no card, bigger number and labels.
  final bool hero;

  const Gauge({
    super.key,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    this.redFrom,
    this.decimals = 0,
    this.hero = false,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final sport = isSport(context);
    final v = value;
    final hot = v != null && redFrom != null && v >= redFrom!;
    final fraction =
        v == null ? 0.0 : ((v - min) / (max - min)).clamp(0.0, 1.0);
    final accent = hot ? AppColors.danger(context) : scheme.primary;

    final number = FittedBox(
      child: Text(fmt(v, decimals),
          textDirection: TextDirection.ltr,
          style: TextStyle(
              fontSize: hero ? 72 : 34,
              height: 1.0,
              letterSpacing: hero ? -2 : -0.5,
              fontWeight: sport ? FontWeight.w600 : FontWeight.bold,
              color: hot
                  ? AppColors.danger(context)
                  : sport
                      ? Colors.white
                      : null)),
    );
    final unitText = Text(unit,
        style: sport
            ? TextStyle(
                fontSize: hero ? 15 : 11,
                fontWeight: FontWeight.w600,
                color: accent)
            : Theme.of(context).textTheme.bodySmall);

    final dial = CustomPaint(
      painter: sport
          ? _GlowGaugePainter(
              fraction: fraction,
              min: min,
              max: max,
              redFraction:
                  redFrom == null ? null : (redFrom! - min) / (max - min),
              accent: accent,
              danger: AppColors.danger(context),
              hero: hero,
            )
          : _GaugePainter(
              fraction: fraction,
              redFraction:
                  redFrom == null ? null : (redFrom! - min) / (max - min),
              track: scheme.outlineVariant,
              fill: accent,
              danger: AppColors.danger(context),
            ),
      child: Center(
        child: FractionallySizedBox(
          widthFactor: sport ? 0.5 : 0.7,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              number,
              unitText,
            ],
          ),
        ),
      ),
    );

    if (hero) {
      return Column(children: [
        Expanded(child: AspectRatio(aspectRatio: 1, child: dial)),
        Text(label,
            style: TextStyle(
                fontSize: 13,
                letterSpacing: 1.5,
                color: scheme.onSurfaceVariant)),
      ]);
    }

    return Card(
      child: Padding(
        padding: EdgeInsets.all(8),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            Expanded(child: dial),
          ],
        ),
      ),
    );
  }
}

/// Icon-style dial: 270° glowing arc on a dark disc with tick marks.
class _GlowGaugePainter extends CustomPainter {
  final double fraction;
  final double min;
  final double max;
  final double? redFraction;
  final Color accent;
  final Color danger;
  final bool hero;

  _GlowGaugePainter({
    required this.fraction,
    required this.min,
    required this.max,
    required this.redFraction,
    required this.accent,
    required this.danger,
    required this.hero,
  });

  static const _start = math.pi * 135 / 180;
  static const _sweep = math.pi * 270 / 180;

  /// A tidy major step giving 6–12 labelled ticks.
  double get _step {
    final span = max - min;
    for (final s in [5.0, 10, 20, 25, 50, 100, 250, 500, 1000, 2000]) {
      if (span / s <= 12) return s.toDouble();
    }
    return span / 10;
  }

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - (hero ? 10 : 5);
    final w = hero ? 9.0 : 5.0;
    final rect = Rect.fromCircle(center: c, radius: r);
    Offset at(double a, double rad) =>
        c + Offset(math.cos(a), math.sin(a)) * rad;

    // Dark radial disc behind everything.
    canvas.drawCircle(
        c,
        r - w,
        Paint()
          ..shader = RadialGradient(colors: const [
            Color(0xFF1C1C1E),
            Color(0xFF0A0A0B),
            Color(0xFF000000),
          ], stops: const [0, 0.7, 1])
              .createShader(Rect.fromCircle(center: c, radius: r)));

    // Inner hairline ring around the number.
    canvas.drawCircle(
        c,
        r * 0.52,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = const Color(0x33FFFFFF));

    // Track.
    final arc = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = w
      ..strokeCap = StrokeCap.round;
    canvas.drawArc(rect, _start, _sweep, false,
        arc..color = const Color(0xFF151517));
    final rf = redFraction;
    if (rf != null && rf < 1) {
      canvas.drawArc(rect, _start + _sweep * rf, _sweep * (1 - rf), false,
          arc..color = danger.withValues(alpha: 0.22));
    }

    // Glow + fill + bright tip.
    if (fraction > 0.002) {
      final sweep = _sweep * fraction;
      canvas.drawArc(
          rect,
          _start,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w * 1.8
            ..strokeCap = StrokeCap.round
            ..color = accent.withValues(alpha: 0.55)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 1.4));
      canvas.drawArc(
          rect,
          _start,
          sweep,
          false,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = w
            ..strokeCap = StrokeCap.round
            ..shader = SweepGradient(
              startAngle: 0,
              endAngle: math.pi * 2,
              colors: [accent, Color.lerp(accent, Colors.white, 0.15)!],
              transform: GradientRotation(_start),
            ).createShader(rect));
      final tip = at(_start + sweep, r);
      canvas.drawCircle(
          tip,
          w * 0.85,
          Paint()
            ..color = const Color(0xFFFFE55D)
            ..maskFilter = MaskFilter.blur(BlurStyle.normal, w * 0.6));
      canvas.drawCircle(tip, w * 0.55, Paint()..color = const Color(0xFFFFF3B0));
    }

    // Ticks and labels.
    final step = _step;
    final minor = step / 5;
    final tickOuter = r - w - (hero ? 8 : 4);
    final tick = Paint()..strokeCap = StrokeCap.round;
    final n = ((max - min) / minor).round();
    final labels = r > 60;
    for (var i = 0; i <= n; i++) {
      final val = min + i * minor;
      final f = (val - min) / (max - min);
      final a = _start + _sweep * f;
      final major = i % 5 == 0;
      final red = rf != null && f >= rf;
      tick
        ..strokeWidth = major ? (hero ? 2.6 : 1.8) : (hero ? 1.2 : 0.9)
        ..color = major
            ? (red ? danger : Colors.white)
            : (red ? danger : accent).withValues(alpha: f <= fraction ? 0.95 : 0.45);
      final len = major ? (hero ? 16.0 : 8.0) : (hero ? 8.0 : 4.0);
      canvas.drawLine(at(a, tickOuter), at(a, tickOuter - len), tick);

      if (major && labels) {
        final text = val >= 1000 && step >= 500
            ? (val / 1000).toStringAsFixed(val % 1000 == 0 ? 0 : 1)
            : val.toStringAsFixed(0);
        final tp = TextPainter(
          text: TextSpan(
              text: text,
              style: TextStyle(
                  color: red ? danger : Colors.white,
                  fontSize: hero ? 14 : 9,
                  fontWeight: FontWeight.w600)),
          textDirection: TextDirection.ltr,
        )..layout();
        final p = at(a, tickOuter - len - (hero ? 18 : 10));
        tp.paint(canvas, p - Offset(tp.width / 2, tp.height / 2));
      }
    }
  }

  @override
  bool shouldRepaint(_GlowGaugePainter old) =>
      old.fraction != fraction || old.accent != accent || old.hero != hero;
}

class _GaugePainter extends CustomPainter {
  final double fraction;
  final double? redFraction;
  final Color track;
  final Color fill;
  final Color danger;

  _GaugePainter({
    required this.fraction,
    required this.redFraction,
    required this.track,
    required this.fill,
    required this.danger,
  });

  static const _start = math.pi * 150 / 180;
  static const _sweep = math.pi * 240 / 180;

  @override
  void paint(Canvas canvas, Size size) {
    final r = math.min(size.width, size.height) / 2 - 8;
    final rect = Rect.fromCircle(center: size.center(Offset.zero), radius: r);
    final base = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 10
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(rect, _start, _sweep, false, base..color = track);
    final rf = redFraction;
    if (rf != null && rf < 1) {
      canvas.drawArc(rect, _start + _sweep * rf, _sweep * (1 - rf), false,
          base..color = danger.withValues(alpha: 0.25));
    }
    if (fraction > 0) {
      canvas.drawArc(
          rect, _start, _sweep * fraction, false, base..color = fill);
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction || old.fill != fill;
}

/// Plain number tile with optional subtitle.
class StatTile extends StatelessWidget {
  final String label;
  final String value;
  final String? unit;
  final String? sub;
  final IconData? icon;
  final Color? color;

  const StatTile({
    super.key,
    required this.label,
    required this.value,
    this.unit,
    this.sub,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return Card(
      child: Padding(
        padding: EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              if (icon != null)
                Icon(icon,
                    size: 18,
                    color: color ??
                        (isSport(context)
                            ? Theme.of(context).colorScheme.primary
                            : null)),
              if (icon != null) SizedBox(width: 6),
              Expanded(
                  child: Text(label,
                      style: t.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ]),
            SizedBox(height: 6),
            FittedBox(
              alignment: AlignmentDirectional.centerStart,
              fit: BoxFit.scaleDown,
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: value,
                    style: t.headlineMedium?.copyWith(
                        fontWeight:
                            isSport(context) ? FontWeight.w600 : FontWeight.bold,
                        fontStyle: FontStyle.normal,
                        color: color)),
                if (unit != null) TextSpan(text: ' $unit', style: t.bodyMedium),
              ])),
            ),
            if (sub != null)
              Text(sub!,
                  style: t.bodySmall,
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis),
          ],
        ),
      ),
    );
  }
}
