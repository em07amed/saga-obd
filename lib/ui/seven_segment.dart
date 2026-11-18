import 'dart:ui' as ui;
import 'dart:typed_data';

import 'package:flutter/material.dart';

/// Digital-clock style numbers (7 segments), drawn by hand so no font file
/// is needed. Unlit segments are shown faintly, like a real LCD.
class SevenSeg extends StatelessWidget {
  final String text;
  final double height;
  final Color color;
  final bool glow;
  const SevenSeg(this.text,
      {super.key, required this.height, required this.color, this.glow = true});

  static double widthOf(String s, double h) {
    var w = 0.0;
    for (final ch in s.split('')) {
      w += ch == ':' || ch == '.' ? h * 0.24 : h * 0.62;
    }
    return w;
  }

  @override
  Widget build(BuildContext context) => CustomPaint(
        size: Size(widthOf(text, height) + height * 0.1, height),
        painter: _SegPainter(text, color, glow),
      );
}

class _SegPainter extends CustomPainter {
  final String text;
  final Color color;
  final bool glow;
  _SegPainter(this.text, this.color, this.glow);

  static const _digits = {
    '0': 'abcdef', '1': 'bc', '2': 'abged', '3': 'abgcd', '4': 'fgbc',
    '5': 'afgcd', '6': 'afgedc', '7': 'abc', '8': 'abcdefg', '9': 'abcdfg',
    '-': 'g', ' ': '',
  };

  @override
  void paint(Canvas canvas, Size size) {
    final h = size.height;
    // Slight italic lean like a car display.
    canvas.translate(h * 0.08, 0);
    canvas.transform(Float64List.fromList(
        [1, 0, 0, 0, -0.08, 1, 0, 0, 0, 0, 1, 0, 0, 0, 0, 1]));
    final on = Paint()..color = color;
    final off = Paint()..color = color.withValues(alpha: 0.07);
    final halo = Paint()
      ..color = color.withValues(alpha: 0.55)
      ..maskFilter = ui.MaskFilter.blur(BlurStyle.normal, h * 0.06);
    var x = 0.0;
    for (final ch in text.split('')) {
      if (ch == ':' || ch == '.') {
        final r = h * 0.065;
        final cx = x + h * 0.12;
        final dots = ch == ':' ? [h * 0.32, h * 0.68] : [h - r];
        for (final y in dots) {
          if (glow) canvas.drawCircle(Offset(cx, y), r, halo);
          canvas.drawCircle(Offset(cx, y), r, on);
        }
        x += h * 0.24;
        continue;
      }
      final lit = _digits[ch] ?? '';
      final w = h * 0.5;
      final segs = _segments(x, w, h);
      for (final e in segs.entries) {
        if (!lit.contains(e.key)) canvas.drawPath(e.value, off);
      }
      for (final e in segs.entries) {
        if (lit.contains(e.key)) {
          if (glow) canvas.drawPath(e.value, halo);
          canvas.drawPath(e.value, on);
        }
      }
      x += h * 0.62;
    }
  }

  Map<String, Path> _segments(double x0, double w, double h) {
    final t = h * 0.12; // thickness
    final g = h * 0.018; // gap between segments
    final l = x0 + t / 2, r = x0 + w - t / 2;
    final top = t / 2, mid = h / 2, bot = h - t / 2;
    Path hs(double a, double b, double y) => Path()
      ..moveTo(a, y)
      ..lineTo(a + t / 2, y - t / 2)
      ..lineTo(b - t / 2, y - t / 2)
      ..lineTo(b, y)
      ..lineTo(b - t / 2, y + t / 2)
      ..lineTo(a + t / 2, y + t / 2)
      ..close();
    Path vs(double x, double a, double b) => Path()
      ..moveTo(x, a)
      ..lineTo(x + t / 2, a + t / 2)
      ..lineTo(x + t / 2, b - t / 2)
      ..lineTo(x, b)
      ..lineTo(x - t / 2, b - t / 2)
      ..lineTo(x - t / 2, a + t / 2)
      ..close();
    return {
      'a': hs(l + g, r - g, top),
      'g': hs(l + g, r - g, mid),
      'd': hs(l + g, r - g, bot),
      'f': vs(l, top + g, mid - g),
      'b': vs(r, top + g, mid - g),
      'e': vs(l, mid + g, bot - g),
      'c': vs(r, mid + g, bot - g),
    };
  }

  @override
  bool shouldRepaint(_SegPainter o) =>
      o.text != text || o.color != color || o.glow != glow;
}
