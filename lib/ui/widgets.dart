import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../main.dart';
import '../obd/obd_service.dart';

/// Colours chosen for contrast on a white background.
class AppColors {
  static const danger = Color(0xFFC62828);
  static const warning = Color(0xFF9A5B00);
  static const ok = Color(0xFF1E7A34);
  static const routeSlow = Color(0xFF2E9E4A);
  static const routeFast = Color(0xFFD32F2F);
}

String fmt(double? v, [int decimals = 0]) =>
    v == null || v.isNaN || v.isInfinite ? '—' : v.toStringAsFixed(decimals);

String fmtDuration(Duration d) {
  final h = d.inHours;
  final m = d.inMinutes % 60;
  return h > 0 ? '$h س $m د' : '$m د';
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
          ObdState.connected => AppColors.ok,
          ObdState.disconnected => scheme.error,
          _ => AppColors.warning,
        };
        return Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          color: scheme.surfaceContainerHighest,
          child: Row(
            children: [
              Icon(Icons.bluetooth, color: color, size: 20),
              const SizedBox(width: 8),
              Expanded(
                child: Text(obd.status,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
              ),
              if (busy)
                const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2))
              else if (obd.isConnected)
                TextButton(
                    onPressed: obd.disconnect, child: const Text('فصل'))
              else
                FilledButton(
                    onPressed: obd.connect, child: const Text('اتصال')),
            ],
          ),
        );
      },
    );
  }
}

/// Arc gauge (240°) with a red zone.
class Gauge extends StatelessWidget {
  final String label;
  final String unit;
  final double? value;
  final double min;
  final double max;
  final double? redFrom;
  final int decimals;

  const Gauge({
    super.key,
    required this.label,
    required this.unit,
    required this.value,
    required this.min,
    required this.max,
    this.redFrom,
    this.decimals = 0,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final v = value;
    final hot = v != null && redFrom != null && v >= redFrom!;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: Column(
          children: [
            Text(label, style: Theme.of(context).textTheme.labelLarge),
            Expanded(
              child: CustomPaint(
                painter: _GaugePainter(
                  fraction: v == null ? 0 : ((v - min) / (max - min)).clamp(0.0, 1.0),
                  redFraction:
                      redFrom == null ? null : (redFrom! - min) / (max - min),
                  track: scheme.outlineVariant,
                  fill: hot ? AppColors.danger : scheme.primary,
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        child: Text(fmt(v, decimals),
                            style: TextStyle(
                                fontSize: 34,
                                fontWeight: FontWeight.bold,
                                color: hot ? AppColors.danger : null)),
                      ),
                      Text(unit, style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _GaugePainter extends CustomPainter {
  final double fraction;
  final double? redFraction;
  final Color track;
  final Color fill;

  _GaugePainter({
    required this.fraction,
    required this.redFraction,
    required this.track,
    required this.fill,
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
          base..color = AppColors.danger.withValues(alpha: 0.25));
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
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Row(children: [
              if (icon != null) Icon(icon, size: 18, color: color),
              if (icon != null) const SizedBox(width: 6),
              Expanded(
                  child: Text(label,
                      style: t.labelLarge,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis)),
            ]),
            const SizedBox(height: 6),
            FittedBox(
              alignment: AlignmentDirectional.centerStart,
              fit: BoxFit.scaleDown,
              child: Text.rich(TextSpan(children: [
                TextSpan(
                    text: value,
                    style: t.headlineMedium
                        ?.copyWith(fontWeight: FontWeight.bold, color: color)),
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
