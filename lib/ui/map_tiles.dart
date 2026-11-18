import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// CARTO basemaps (OpenStreetMap data): a clean light map, or a dark one
/// that matches the dark and sport themes.
TileLayer mapTiles(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return TileLayer(
    urlTemplate:
        'https://{s}.basemaps.cartocdn.com/${dark ? 'dark_all' : 'rastertiles/voyager'}/{z}/{x}/{y}.png',
    subdomains: const ['a', 'b', 'c', 'd'],
    userAgentPackageName: 'com.ezzat.obd_saga',
    maxNativeZoom: 19,
  );
}

Widget mapAttribution() => const SimpleAttributionWidget(
      source: Text('© OpenStreetMap contributors © CARTO'),
    );

/// Round marker with an icon, used for start/end/events.
Widget mapPin(Color c, IconData icon, {double size = 16}) => Container(
      decoration: BoxDecoration(
        color: c,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 2),
        boxShadow: const [BoxShadow(blurRadius: 4, color: Colors.black38)],
      ),
      child: Icon(icon, size: size, color: Colors.white),
    );
