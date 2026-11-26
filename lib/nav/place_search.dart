import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:latlong2/latlong.dart' show LatLng, Distance, LengthUnit;

import '../l10n.dart';

/// A place found by search.
class Place {
  final String name;
  final String detail;
  final LatLng at;
  const Place(this.name, this.detail, this.at);
}

/// Free place search (OpenStreetMap geocoders). Driving itself is handed to
/// Google Maps.
class PlaceSearch {
  static const _ua = {'User-Agent': 'CarOBD/1.0 (+https://github.com/em07amed/saga-obd)'};

  /// Place search. Tries several free geocoders in turn, so one being down
  /// or blocking us doesn't break search: Nominatim → Photon → Esri.
  Future<List<Place>> search(String q, LatLng? near) async {
    Object? lastError;
    for (final src in [_nominatim, _photon, _esri]) {
      try {
        final r = await src(q, near).timeout(const Duration(seconds: 8));
        if (r.isNotEmpty) return _sortByDistance(r, near);
      } catch (e) {
        lastError = e;
      }
    }
    if (lastError != null) throw lastError;
    return [];
  }

  static List<Place> _sortByDistance(List<Place> r, LatLng? near) {
    if (near == null) return r;
    const d = Distance();
    return [...r]..sort((a, b) => d
        .as(LengthUnit.Meter, near, a.at)
        .compareTo(d.as(LengthUnit.Meter, near, b.at)));
  }

  Future<List<Place>> _nominatim(String q, LatLng? near) async {
    final params = {
      'q': q,
      'format': 'json',
      'limit': '8',
      'accept-language': Lang.code,
      if (near != null)
        'viewbox': '${near.longitude - 0.6},${near.latitude + 0.6},'
            '${near.longitude + 0.6},${near.latitude - 0.6}',
    };
    final uri = Uri.https('nominatim.openstreetmap.org', '/search', params);
    final res = await http.get(uri, headers: _ua);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final list = jsonDecode(res.body) as List;
    return [
      for (final e in list)
        Place(
          (e['display_name'] as String).split(',').first,
          (e['display_name'] as String).split(',').skip(1).take(3).join(','),
          LatLng(double.parse(e['lat'] as String),
              double.parse(e['lon'] as String)),
        ),
    ];
  }

  Future<List<Place>> _photon(String q, LatLng? near) async {
    final uri = Uri.https('photon.komoot.io', '/api/', {
      'q': q,
      'limit': '8',
      if (near != null) 'lat': '${near.latitude}',
      if (near != null) 'lon': '${near.longitude}',
    });
    final res = await http.get(uri, headers: _ua);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final feats = (jsonDecode(res.body)['features'] as List?) ?? const [];
    return [
      for (final f in feats)
        if (f['geometry']?['coordinates'] is List)
          Place(
            '${f['properties']?['name'] ?? f['properties']?['street'] ?? q}',
            [
              f['properties']?['street'],
              f['properties']?['city'] ?? f['properties']?['district'],
              f['properties']?['state'],
            ].whereType<String>().join(', '),
            LatLng((f['geometry']['coordinates'][1] as num).toDouble(),
                (f['geometry']['coordinates'][0] as num).toDouble()),
          ),
    ];
  }

  Future<List<Place>> _esri(String q, LatLng? near) async {
    final uri = Uri.https('geocode.arcgis.com',
        '/arcgis/rest/services/World/GeocodeServer/findAddressCandidates', {
      'SingleLine': q,
      'f': 'json',
      'maxLocations': '8',
      'outFields': 'PlaceName,Place_addr',
      'langCode': Lang.code,
      if (near != null) 'location': '${near.longitude},${near.latitude}',
    });
    final res = await http.get(uri, headers: _ua);
    if (res.statusCode != 200) throw Exception('HTTP ${res.statusCode}');
    final c = (jsonDecode(res.body)['candidates'] as List?) ?? const [];
    return [
      for (final e in c)
        Place(
          '${e['attributes']?['PlaceName'] ?? ''}'.isNotEmpty
              ? '${e['attributes']['PlaceName']}'
              : '${e['address']}'.split(',').first,
          '${e['attributes']?['Place_addr'] ?? e['address'] ?? ''}',
          LatLng((e['location']['y'] as num).toDouble(),
              (e['location']['x'] as num).toDouble()),
        ),
    ];
  }
}
