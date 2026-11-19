import 'package:shared_preferences/shared_preferences.dart';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';

class MapStyle {
  final String id, name, url, credit;
  final int maxZoom;
  final List<String> subdomains;
  const MapStyle(this.id, this.name, this.url, this.credit,
      {this.maxZoom = 19, this.subdomains = const []});
}

/// Free tile sources that need no API key. If one fails to load (blocked,
/// down), the map switches to the next one by itself.
const mapStyles = [
  MapStyle('streets', 'شوارع (Esri)',
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Street_Map/MapServer/tile/{z}/{y}/{x}',
      'Esri, HERE, Garmin, OpenStreetMap contributors',
      maxZoom: 19),
  MapStyle('osm', 'OpenStreetMap (عربي)',
      'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
      'OpenStreetMap contributors'),
  MapStyle('hot', 'OSM ملوّنة',
      'https://{s}.tile.openstreetmap.fr/hot/{z}/{x}/{y}.png',
      'OpenStreetMap contributors, HOT',
      subdomains: ['a', 'b', 'c']),
  MapStyle('sat', 'قمر صناعي (Esri)',
      'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
      'Esri, Maxar, Earthstar Geographics',
      maxZoom: 19),
];

/// Index into [mapStyles] currently shown; changes on failure or by choice.
final mapStyleIndex = ValueNotifier<int>(0);
int _errors = 0, _tried = 1;
bool _manual = false; // the driver picked a style: never switch it for them

void setMapStyle(String id) {
  final i = mapStyles.indexWhere((m) => m.id == id);
  if (i >= 0) {
    _manual = true;
    mapStyleIndex.value = i;
    SharedPreferences.getInstance()
        .then((p) => p.setString('mapStyle', id))
        .catchError((_) => false);
  }
}

/// Restores the style the driver picked last time (call once at start-up).
Future<void> loadMapStyle() async {
  try {
    final id = (await SharedPreferences.getInstance()).getString('mapStyle');
    final i = mapStyles.indexWhere((m) => m.id == id);
    if (i >= 0) {
      _manual = true;
      mapStyleIndex.value = i;
    }
  } catch (_) {}
}

/// The base map. In dark/sport themes the tiles are darkened on the device
/// (not for satellite) so the map matches the rest of the app.
Widget mapTiles(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return ValueListenableBuilder<int>(
    valueListenable: mapStyleIndex,
    builder: (context, i, _) {
      final m = mapStyles[i];
      return TileLayer(
        key: ValueKey(m.id),
        urlTemplate: m.url,
        subdomains: m.subdomains,
        userAgentPackageName: 'com.ezzat.obd_saga',
        maxNativeZoom: m.maxZoom,
        tileBuilder: dark && m.id != 'sat' ? darkModeTileBuilder : null,
        errorTileCallback: (tile, error, stack) {
          // Default source failing a lot → try the next one (once each).
          // Never overrides a style the driver chose.
          if (_manual) return;
          if (++_errors >= 12 && _tried < mapStyles.length - 1) {
            _errors = 0;
            _tried++;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              mapStyleIndex.value = (mapStyleIndex.value + 1) %
                  (mapStyles.length - 1); // never auto-switch to satellite
            });
          }
        },
      );
    },
  );
}

Widget mapAttribution() => ValueListenableBuilder<int>(
      valueListenable: mapStyleIndex,
      builder: (context, i, _) =>
          SimpleAttributionWidget(source: Text(mapStyles[i].credit)),
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
