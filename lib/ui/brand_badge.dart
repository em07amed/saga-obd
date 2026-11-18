import 'package:flutter/material.dart';

/// Generic badge for a car make: its initials on a colour picked from the
/// name. Deliberately not the manufacturer's logo (those are trademarks).
class BrandBadge extends StatelessWidget {
  final String make;
  final double size;
  const BrandBadge(this.make, {super.key, this.size = 40});

  static const _palette = [
    Color(0xFF00695C), Color(0xFF1565C0), Color(0xFF6A1B9A), Color(0xFFAD1457),
    Color(0xFFEF6C00), Color(0xFF2E7D32), Color(0xFF4E342E), Color(0xFF37474F),
  ];

  String get _initials {
    final words = make.trim().split(RegExp(r'[\s\-]+')).where((w) => w.isNotEmpty);
    if (words.isEmpty) return '?';
    if (words.length == 1) {
      final w = words.first;
      return w.length <= 3 && w.toUpperCase() == w
          ? w // short acronyms: BMW, MG, BYD
          : w.characters.take(2).toString().toUpperCase();
    }
    return words.take(2).map((w) => w.characters.first.toUpperCase()).join();
  }

  @override
  Widget build(BuildContext context) {
    final color = make.trim().isEmpty
        ? Theme.of(context).colorScheme.outline
        : _palette[make.toLowerCase().codeUnits.fold<int>(0, (a, b) => a + b) %
            _palette.length];
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      child: FittedBox(
        child: Padding(
          padding: EdgeInsets.all(size * 0.18),
          child: Text(_initials,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w900)),
        ),
      ),
    );
  }
}
