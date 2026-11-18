import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

/// OpenStreetMap tiles (no API key). In dark/sport themes the tiles are
/// darkened on the device so the map matches the rest of the app.
TileLayer mapTiles(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return TileLayer(
    urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    userAgentPackageName: 'com.ezzat.obd_saga',
    maxNativeZoom: 19,
    tileBuilder: dark ? darkModeTileBuilder : null,
  );
}

Widget mapAttribution() => const SimpleAttributionWidget(
      source: Text('OpenStreetMap contributors'),
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
