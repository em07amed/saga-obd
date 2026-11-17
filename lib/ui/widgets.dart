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
        padding: EdgeInsets.all(8),
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
                  fill: hot ? AppColors.danger(context) : scheme.primary,
                  danger: AppColors.danger(context),
                  segmented: isSport(context),
                ),
                child: Center(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      FittedBox(
                        child: Text(fmt(v, decimals),
                            style: TextStyle(
                                fontSize: 34,
                                fontWeight: isSport(context)
                                    ? FontWeight.w900
                                    : FontWeight.bold,
                                fontStyle: isSport(context)
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                color: hot ? AppColors.danger(context) : null)),
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
  final Color danger;
  final bool segmented;

  _GaugePainter({
    required this.fraction,
    required this.redFraction,
    required this.track,
    required this.fill,
    required this.danger,
    this.segmented = false,
  });

  static const _start = math.pi * 150 / 180;
  static const _sweep = math.pi * 240 / 180;

  @override
  void paint(Canvas canvas, Size size) {
    if (segmented) return _paintSegments(canvas, size);
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

  /// Sport style: a ring of short blocks that light up, red past redline.
  void _paintSegments(Canvas canvas, Size size) {
    const n = 32;
    final c = size.center(Offset.zero);
    final r = math.min(size.width, size.height) / 2 - 4;
    final rf = redFraction ?? 2;
    final p = Paint()
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.butt;
    for (var i = 0; i < n; i++) {
      final f0 = i / n;
      final a = _start + _sweep * (i + 0.5) / n;
      final lit = f0 < fraction;
      final red = f0 >= rf;
      p
        ..strokeWidth = i % 4 == 0 ? 4 : 3
        ..color = lit
            ? (red ? danger : fill)
            : (red ? danger.withValues(alpha: 0.25) : track);
      final inner = r - (i % 4 == 0 ? 16 : 11);
      canvas.drawLine(
        c + Offset(math.cos(a), math.sin(a)) * inner,
        c + Offset(math.cos(a), math.sin(a)) * r,
        p,
      );
    }
  }

  @override
  bool shouldRepaint(_GaugePainter old) =>
      old.fraction != fraction ||
      old.fill != fill ||
      old.segmented != segmented;
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
                            isSport(context) ? FontWeight.w900 : FontWeight.bold,
                        fontStyle: isSport(context)
                            ? FontStyle.italic
                            : FontStyle.normal,
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
