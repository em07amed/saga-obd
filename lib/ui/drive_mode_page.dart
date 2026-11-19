import 'dart:math' as math;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../main.dart';
import '../obd/bt_channel.dart';
import '../obd/pids.dart';
import '../nav/nav_service.dart';
import 'drive_panels.dart';
import 'map_tiles.dart';
import 'vehicle_avatar.dart';
import 'sport_theme.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Full-screen landscape view for a phone on a dash mount: few, large numbers.
class DriveModePage extends StatefulWidget {
  const DriveModePage({super.key});

  @override
  State<DriveModePage> createState() => _DriveModePageState();
}

enum _Panel { gauges, map, music, radio, phone }

class _DriveModePageState extends State<DriveModePage> {
  _Panel _panel = _Panel.gauges;
  bool get _map => _panel == _Panel.map;
  final _search = TextEditingController();
  List<Place>? _results;
  bool _searching = false;

  void _show(_Panel p, {bool toggle = false}) {
    setState(() => _panel = toggle && _panel == p ? _Panel.gauges : p);
    if (p == _Panel.map) _startGps();
  }

  Future<void> _doSearch(String q) async {
    if (q.trim().isEmpty) return;
    setState(() => _searching = true);
    try {
      final p = _pos;
      final r = await App.nav
          .search(q, p == null ? null : LatLng(p.latitude, p.longitude));
      if (mounted) setState(() => _results = r);
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(tr('البحث محتاج نت'))));
      }
    }
    if (mounted) setState(() => _searching = false);
  }

  // ---------- voice commands ----------

  bool _listening = false;
  String _heard = '';

  /// Uses the phone's speech recognizer (Google's voice popup), which works
  /// on Samsung too, then runs the command.
  Future<void> _voice() async {
    if (_listening) return;
    if (!(await Permission.microphone.request()).isGranted) {
      _say(tr('اسمح بإذن الميكروفون'));
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    String? text;
    try {
      text = await App.obd.bt.listen(Lang.isEn ? 'en-US' : 'ar-EG');
    } catch (_) {
      text = null;
    }
    if (!mounted) return;
    setState(() {
      _listening = false;
      _heard = text ?? '';
    });
    if (text == null) {
      _say(tr('التعرف على الصوت مش متاح على الموبايل ده'));
    } else if (text.trim().isNotEmpty) {
      _handle(text);
    }
  }

  void _say(String s) =>
      App.obd.bt.speak(s, Lang.code, flush: true).catchError((_) {});

  /// Same length as the input (char-for-char) so indexes map back to it.
  static String _norm(String s) => s
      .toLowerCase()
      .replaceAll(RegExp('[أإآ]'), 'ا')
      .replaceAll('ة', 'ه')
      .replaceAll('ى', 'ي');

  static String _clean(String s) => s
      .trim()
      .replaceFirst(
          RegExp(r'^(على|علي|الى|إلى|الي|لـ|ل |to |the )\s*'), '')
      .trim();

  Future<void> _handle(String raw) async {
    final t = _norm(raw);
    bool has(List<String> ws) => ws.any((w) => t.contains(_norm(w)));
    String after(List<String> ws) {
      for (final w in ws) {
        final i = t.indexOf(_norm(w));
        if (i >= 0) return _clean(raw.substring(i + w.length));
      }
      return '';
    }

    final v = App.obd.values;

    // Stop navigation.
    if (has(['وقف الملاحه', 'انهي الملاحه', 'الغي الملاحه', 'stop navigation'])) {
      App.nav.stop();
      _say(tr('وقفت الملاحة'));
      return;
    }
    // Navigate somewhere.
    const goWords = ['وديني', 'ودينى', 'خدني', 'عايز اروح', 'روح', 'navigate to', 'take me to', 'go to'];
    if (has(goWords)) {
      final dest = after(goWords);
      if (dest.isEmpty) return _say(tr('قول اسم المكان بعد وديني'));
      _show(_Panel.map);
      final p = _pos;
      try {
        final r = await App.nav
            .search(dest, p == null ? null : LatLng(p.latitude, p.longitude));
        if (r.isEmpty) return _say(tr('ما لقيتش $dest'));
        _say(tr('رايحين على ${r.first.name}'));
        await _go(r.first);
      } catch (_) {
        _say(tr('البحث محتاج نت'));
      }
      return;
    }
    // Answer / hang up the current call.
    final pc = BtChannel.phoneCall.value;
    if (pc.ringing && has(['رد', 'افتح', 'answer'])) {
      await App.obd.bt.answerCall();
      return;
    }
    if (!pc.idle && !has(['راديو']) && has(['اقفل', 'ارفض', 'انهي', 'end call', 'hang up', 'decline'])) {
      await App.obd.bt.endCall();
      return;
    }
    // Call someone.
    const callWords = ['اتصل ب', 'اتصل على', 'كلم', 'call '];
    if (has(callWords)) {
      final who = _norm(after(callWords));
      if (who.isEmpty) return _say(tr('قول الاسم بعد اتصل'));
      if (!(await Permission.contacts.request()).isGranted) return;
      final all = await App.obd.bt.contacts().catchError((_) => <Contact>[]);
      Contact? hit;
      for (final c in all) {
        final n = _norm(c.name);
        if (n == who) {
          hit = c;
          break;
        }
        if (hit == null && (n.contains(who) || who.contains(n))) hit = c;
      }
      if (hit == null) return _say(tr('مش لاقي ${after(callWords)} في الأسماء'));
      _say(tr('بتصل بـ ${hit.name}'));
      if ((await Permission.phone.request()).isGranted) {
        await Future<void>.delayed(const Duration(milliseconds: 1500));
        await App.obd.bt.call(hit.number).catchError((_) {});
      }
      return;
    }
    // Radio.
    if (has(['وقف الراديو', 'اقفل الراديو', 'stop radio', 'stop the radio'])) {
      await App.radio.stop();
      return _say(tr('قفلت الراديو'));
    }
    const radioWords = ['راديو', 'اذاعه', 'radio'];
    if (has(radioWords)) {
      _show(_Panel.radio);
      final name = after(radioWords);
      try {
        final list = name.isNotEmpty
            ? await App.radio.search(name)
            : App.radio.favourites.isNotEmpty
                ? App.radio.favourites
                : await App.radio.egypt();
        if (list.isEmpty) return _say(tr('ما لقيتش المحطة'));
        await App.radio.play(list.first);
      } catch (_) {
        _say(tr('الراديو محتاج نت'));
      }
      return;
    }
    // Readings.
    if (has(['السرعه', 'سرعتي', 'speed'])) {
      return _say(tr('سرعتك ${fmt(v[Pids.speed])} كيلو'));
    }
    if (has(['الحراره', 'حراره', 'temperature'])) {
      return _say(tr('حرارة الموتور ${fmt(v[Pids.coolant])} درجة'));
    }
    if (has(['البنزين', 'fuel'])) {
      final l = App.fuel.litresNow;
      if (l == null) return _say(tr('مش عارف البنزين. سجّل تفويلة الأول'));
      final avg = App.fuel.realAvgL100 ?? App.trips.avgL100 ?? App.settings.defaultL100;
      return _say(tr('فاضل ${l.toStringAsFixed(0)} لتر، يكفوا حوالي ${(l / avg * 100).round()} كيلو'));
    }
    if (has(['العداد', 'odometer'])) {
      final km = App.maintenance.odometerKm;
      return _say(km == null
          ? tr('العداد مش متسجل')
          : tr('العداد ${km.round()} كيلو'));
    }
    // Panels.
    if (has(['العدادات', 'gauges'])) return _show(_Panel.gauges);
    if (has(['الخريطه', 'map'])) return _show(_Panel.map);
    if (has(['الموسيقي', 'الاغاني', 'music'])) return _show(_Panel.music);

    _say(tr('مش فاهم. جرّب: وديني على مكان، اتصل بحد، شغّل الراديو، أو السرعة كام'));
  }

  /// Hand the trip to Google Maps; this app floats on top with the gauges.
  Future<void> _googleMaps([LatLng? to]) async {
    App.nav.stop(); // avoid two voices giving directions
    setState(() => _results = null);
    final ok = await App.obd.bt
        .openGoogleMaps(to?.latitude, to?.longitude)
        .catchError((_) => false);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(tr('Google Maps مش متثبت'))));
    }
  }

  Future<void> _go(Place place) async {
    final p = _pos;
    if (p == null) return;
    setState(() {
      _results = null;
      _follow = true;
    });
    FocusScope.of(context).unfocus();
    await App.nav.start(place, LatLng(p.latitude, p.longitude));
  }
  final _mapCtl = MapController();
  StreamSubscription<Position>? _gps;
  Position? _pos;
  final List<LatLng> _path = [];
  bool _follow = true;
  bool _headingUp = true; // map turns with the car, like Waze
  double _heading = 0;

  Future<void> _startGps() async {
    if (_gps == null) {
      final perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        return;
      }
      _gps = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.bestForNavigation,
          distanceFilter: 5,
        ),
      ).listen((p) {
        if (!mounted) return;
        final at = LatLng(p.latitude, p.longitude);
        setState(() {
          _pos = p;
          if (p.accuracy < 30) _path.add(at);
        });
        App.nav.update(at); // turn-by-turn keeps running on any panel
        if (_map && _follow) {
          // Zoom out a little at speed so more road ahead is visible.
          final kmh = p.speed * 3.6;
          final zoom = kmh > 90 ? 15.5 : kmh > 50 ? 16.5 : 17.5;
          if (p.speed > 1.5 && !p.heading.isNaN) _heading = p.heading;
          try {
            _mapCtl.moveAndRotate(at, zoom, _headingUp ? 360 - _heading : 0);
          } catch (_) {}
        }
      });
    }
  }

  Widget _liveMap(BuildContext context) {
    final p = _pos;
    final scheme = Theme.of(context).colorScheme;
    if (p == null) {
      return Card(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(tr('بيدوّر على موقعك…')),
          ]),
        ),
      );
    }
    final at = LatLng(p.latitude, p.longitude);
    final nav = App.nav;
    final step = nav.next;
    final s = App.settings;
    final kmh = App.obd.values[Pids.speed] ?? p.speed * 3.6;
    final limit = App.road.effectiveLimit;
    final over = s.speedAlertMode != 'off' && kmh > limit;
    const wazeBlue = Color(0xFF33CCFF);
    const wazeNavy = Color(0xFF0A2A4A);

    void recenter() {
      setState(() => _follow = true);
      try {
        _mapCtl.moveAndRotate(at, 17.5, _headingUp ? 360 - _heading : 0);
      } catch (_) {}
    }

    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Stack(children: [
        FlutterMap(
          mapController: _mapCtl,
          options: MapOptions(
            initialCenter: at,
            initialZoom: 17.5,
            initialRotation: _headingUp ? 360 - _heading : 0,
            interactionOptions: const InteractionOptions(
              flags: InteractiveFlag.all & ~InteractiveFlag.rotate,
            ),
            onPositionChanged: (_, byUser) {
              if (byUser && _follow) setState(() => _follow = false);
            },
          ),
          children: [
            mapTiles(context),
            if (nav.route.length > 1)
              PolylineLayer(polylines: [
                Polyline(
                    points: nav.route,
                    color: wazeBlue,
                    strokeWidth: 10,
                    borderColor: const Color(0xFF1565C0),
                    borderStrokeWidth: 3),
              ]),
            MarkerLayer(markers: [
              for (final c in App.road.cameras)
                Marker(
                  point: c.at,
                  width: 34,
                  height: 34,
                  rotate: true,
                  child: mapPin(const Color(0xFFD32F2F), Icons.camera_alt,
                      size: 17),
                ),
              if (nav.destination != null)
                Marker(
                  point: nav.destination!.at,
                  width: 40,
                  height: 40,
                  rotate: true,
                  child: mapPin(const Color(0xFF2E7D32), Icons.flag, size: 20),
                ),
              // The car: a white puck with a bright arrow, pointing the way.
              Marker(
                point: at,
                width: 54,
                height: 54,
                child: Transform.rotate(
                  angle: _heading * math.pi / 180,
                  child: Container(
                    decoration: const BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      boxShadow: [
                        BoxShadow(blurRadius: 8, color: Colors.black38)
                      ],
                    ),
                    child: const Icon(Icons.navigation,
                        size: 38, color: Color(0xFF1E88E5)),
                  ),
                ),
              ),
            ]),
            mapAttribution(),
          ],
        ),
        // Big turn card while navigating, "where to?" otherwise.
        if (nav.active && step != null)
          PositionedDirectional(
            top: 8,
            start: 8,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 380),
              child: Material(
                color: wazeNavy,
                borderRadius: BorderRadius.circular(18),
                elevation: 6,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 18, 10),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(step.icon, size: 52, color: Colors.white),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(NavService.fmtDist(nav.toNextM),
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 30,
                                  fontWeight: FontWeight.w900)),
                          Text(tr(step.text),
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 16)),
                        ],
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          )
        else
          PositionedDirectional(
            top: 8,
            start: 8,
            end: 64,
            child: Material(
              elevation: 4,
              borderRadius: BorderRadius.circular(28),
              color: scheme.surface,
              child: TextField(
                controller: _search,
                textInputAction: TextInputAction.search,
                onSubmitted: _doSearch,
                decoration: InputDecoration(
                  hintText: tr('رايح فين؟'),
                  prefixIcon: _searching
                      ? const Padding(
                          padding: EdgeInsets.all(12),
                          child: SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2)))
                      : const Icon(Icons.search),
                  suffixIcon: _results != null
                      ? IconButton(
                          icon: const Icon(Icons.close),
                          onPressed: () => setState(() => _results = null))
                      : IconButton(
                          tooltip: tr('افتح Google Maps'),
                          icon: const Icon(Icons.assistant_navigation),
                          onPressed: () => _googleMaps()),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(vertical: 14),
                ),
              ),
            ),
          ),
        // Compass: heading-up (map turns with you) or north-up.
        PositionedDirectional(
          top: 8,
          end: 8,
          child: _roundBtn(
            tooltip: _headingUp ? tr('الشمال لفوق') : tr('اتجاه السير لفوق'),
            onTap: () {
              setState(() => _headingUp = !_headingUp);
              recenter();
            },
            child: Transform.rotate(
              angle: _headingUp ? -_heading * math.pi / 180 : 0,
              child: Icon(Icons.navigation,
                  color: _headingUp ? const Color(0xFFD32F2F) : scheme.onSurface),
            ),
          ),
        ),
        if (_results != null && !nav.active)
          PositionedDirectional(
            top: 64,
            start: 8,
            end: 8,
            bottom: 8,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(14),
              color: scheme.surface,
              child: _results!.isEmpty
                  ? Center(child: Text(tr('ما لقيتش نتايج')))
                  : ListView(children: [
                      for (final r in _results!)
                        ListTile(
                          leading: const Icon(Icons.place),
                          title: Text(r.name,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(r.detail,
                              maxLines: 1, overflow: TextOverflow.ellipsis),
                          onTap: () => _go(r),
                          trailing: IconButton.filledTonal(
                            tooltip: tr('ابدأ في Google Maps'),
                            icon: const Icon(Icons.assistant_navigation),
                            onPressed: () => _googleMaps(r.at),
                          ),
                        ),
                    ]),
            ),
          ),
        if (nav.routing) const Center(child: CircularProgressIndicator()),
        if (nav.error != null)
          PositionedDirectional(
            bottom: 90,
            start: 8,
            end: 8,
            child: Card(
                child: ListTile(
                    leading: const Icon(Icons.wifi_off),
                    title: Text(nav.error!))),
          ),
        // Speedometer bubble + limit sign, bottom corner (like Waze).
        if (_results == null || nav.active)
          PositionedDirectional(
            start: 10,
            bottom: nav.active ? 82 : 12,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Container(
                  width: 74,
                  height: 74,
                  decoration: BoxDecoration(
                    color: over ? const Color(0xFFD32F2F) : Colors.white,
                    shape: BoxShape.circle,
                    border: Border.all(
                        color: over ? Colors.white : const Color(0xFF263238),
                        width: 3),
                    boxShadow: const [
                      BoxShadow(blurRadius: 8, color: Colors.black38)
                    ],
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Text('${kmh.round()}',
                          style: TextStyle(
                              fontSize: 28,
                              height: 1,
                              fontWeight: FontWeight.w900,
                              color: over ? Colors.white : Colors.black87)),
                      Text(tr('كم/س'),
                          style: TextStyle(
                              fontSize: 11,
                              color: over ? Colors.white : Colors.black54)),
                    ],
                  ),
                ),
                if (s.speedAlertMode != 'off') ...[
                  const SizedBox(width: 6),
                  GestureDetector(
                    onTap: () => _fixRoadLimit(context),
                    child: Container(
                    width: 46,
                    height: 46,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: Colors.white,
                      shape: BoxShape.circle,
                      border:
                          Border.all(color: const Color(0xFFD32F2F), width: 5),
                      boxShadow: const [
                        BoxShadow(blurRadius: 6, color: Colors.black26)
                      ],
                    ),
                    child: Text('${limit.round()}',
                        style: const TextStyle(
                            color: Colors.black,
                            fontSize: 16,
                            fontWeight: FontWeight.w900)),
                  ),
                  ),
                ],
              ],
            ),
          ),
        // Radar ahead: distance, with "no radar here" to remove a wrong one.
        if (App.road.nextCamera != null &&
            (App.road.nextCameraM ?? 9999) <= 1000)
          PositionedDirectional(
            top: nav.active ? 96 : 64,
            start: 8,
            child: Material(
              color: const Color(0xFFD32F2F),
              borderRadius: BorderRadius.circular(22),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(12, 2, 2, 2),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  const Icon(Icons.camera_alt, color: Colors.white, size: 18),
                  const SizedBox(width: 6),
                  Text(
                      tr('رادار ${(App.road.nextCameraM! / 10).round() * 10} متر'),
                      style: const TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                  TextButton(
                    onPressed: () =>
                        App.road.removeCamera(App.road.nextCamera!),
                    child: Text(tr('مش رادار'),
                        style: const TextStyle(color: Colors.white70)),
                  ),
                ]),
              ),
            ),
          ),
        // Report a radar at this spot (saved on the phone).
        PositionedDirectional(
          end: 10,
          bottom: (nav.active ? 86 : 14) + (_follow ? 0 : 60),
          child: FloatingActionButton.small(
            heroTag: 'addCam',
            backgroundColor: Colors.white,
            tooltip: tr('فيه رادار هنا'),
            onPressed: () async {
              await App.road.addCameraHere();
              if (!context.mounted) return;
              ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                  content: Text(tr('اتسجّل رادار في المكان ده'))));
            },
            child: const Icon(Icons.add_a_photo, color: Color(0xFFD32F2F)),
          ),
        ),
        if (!_follow)
          PositionedDirectional(
            end: 10,
            bottom: nav.active ? 86 : 14,
            child: FloatingActionButton.extended(
              heroTag: 'recenter',
              backgroundColor: Colors.white,
              foregroundColor: const Color(0xFF1565C0),
              onPressed: recenter,
              icon: const Icon(Icons.navigation),
              label: Text(tr('رجّع الخريطة')),
            ),
          ),
        // Arrival bar: ETA clock, minutes, km, stop.
        if (nav.active)
          PositionedDirectional(
            start: 8,
            end: 8,
            bottom: 8,
            child: Material(
              elevation: 6,
              borderRadius: BorderRadius.circular(20),
              color: scheme.surface,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                child: Row(children: [
                  IconButton.filledTonal(
                    tooltip: tr('إنهاء'),
                    style: IconButton.styleFrom(
                        backgroundColor: const Color(0x22D32F2F)),
                    onPressed: nav.stop,
                    icon: Icon(Icons.close, color: AppColors.danger(context)),
                  ),
                  Expanded(
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          _clock(DateTime.now().add(nav.remaining)),
                          style: const TextStyle(
                              fontSize: 26, fontWeight: FontWeight.w900),
                        ),
                        const SizedBox(width: 14),
                        Text(
                          '${nav.remaining.inMinutes} ${tr('د')}  •  ${NavService.fmtDist(nav.remainingM)}',
                          style: TextStyle(
                              fontSize: 16, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                  IconButton(
                    tooltip: tr('كمّل في Google Maps'),
                    icon: const Icon(Icons.assistant_navigation),
                    onPressed: () => _googleMaps(nav.destination!.at),
                  ),
                ]),
              ),
            ),
          ),
      ]),
    );
  }

  /// Tap on the limit sign: correct the limit of the road we're on.
  Future<void> _fixRoadLimit(BuildContext context) async {
    final road = App.road;
    if (road.roadId == null) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('مش عارف انت على أنهي طريق دلوقتي'))));
      return;
    }
    final picked = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حد السرعة للطريق ده')),
        content: Wrap(spacing: 8, runSpacing: 8, children: [
          for (final v in const [40.0, 50.0, 60.0, 70.0, 80.0, 90.0, 100.0, 120.0])
            ChoiceChip(
              label: Text('${v.round()}'),
              selected: road.roadLimit == v,
              onSelected: (_) => Navigator.pop(ctx, v),
            ),
        ]),
        actions: [
          if (road.thisRoadFixed)
            TextButton(
                onPressed: () => Navigator.pop(ctx, -1.0),
                child: Text(tr('رجّع الأصلي'))),
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('إلغاء'))),
        ],
      ),
    );
    if (picked == null) return;
    await road.setLimitForThisRoad(picked < 0 ? null : picked);
    if (mounted) setState(() {});
  }

  static String _clock(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  Widget _roundBtn(
          {required Widget child,
          required VoidCallback onTap,
          String? tooltip}) =>
      Tooltip(
        message: tooltip ?? '',
        child: Material(
          color: Theme.of(context).colorScheme.surface,
          shape: const CircleBorder(),
          elevation: 4,
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 48, height: 48, child: Center(child: child)),
          ),
        ),
      );

  @override
  void initState() {
    super.initState();
    // Needed to show who's calling and to answer / hang up from here.
    Permission.phone.request().then((_) async {
      final p = await SharedPreferences.getInstance();
      if (p.getBool('askedCallerId') != true) {
        await p.setBool('askedCallerId', true);
        await App.obd.bt.requestCallerId().catchError((_) => false);
      }
    });
    SystemChrome.setPreferredOrientations(
        [DeviceOrientation.landscapeLeft, DeviceOrientation.landscapeRight]);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky);
    WakelockPlus.enable(); // screen stays on only in drive mode
    _startGps();
    App.road.start();
    App.obd.bt.setPipAllowed(true).catchError((_) {});
  }

  @override
  void dispose() {
    SystemChrome.setPreferredOrientations(DeviceOrientation.values);
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    WakelockPlus.disable();
    _gps?.cancel();
    _search.dispose();
    App.obd.bt.setPipAllowed(false).catchError((_) {});
    super.dispose();
  }

  /// Tiny floating window over Google Maps: speed, limit, coolant.
  Widget _pipView(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([App.obd, App.road, App.settings]),
      builder: (context, _) {
        final v = App.obd.values;
        final speed = v[Pids.speed];
        final limit = App.road.effectiveLimit;
        final over = (speed ?? 0) > limit && App.settings.speedAlertMode != 'off';
        final coolant = v[Pids.coolant];
        final hot = coolant != null && coolant >= App.settings.coolantAlert;
        return Container(
          color: Colors.black,
          padding: const EdgeInsets.all(6),
          child: Row(children: [
            Expanded(
              flex: 3,
              child: FittedBox(
                child: Text(fmt(speed),
                    style: TextStyle(
                        color: over ? const Color(0xFFFF3B30) : Colors.white,
                        fontWeight: FontWeight.w900,
                        fontStyle: FontStyle.italic)),
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Expanded(
                    child: FittedBox(
                      child: Container(
                        width: 44,
                        height: 44,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Colors.white,
                          border: Border.all(
                              color: const Color(0xFFD32F2F), width: 5),
                        ),
                        child: Text('${limit.round()}',
                            style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ),
                  Expanded(
                    child: FittedBox(
                      child: Text('${fmt(coolant)}°',
                          style: TextStyle(
                              color: hot
                                  ? const Color(0xFFFF3B30)
                                  : Colors.white70,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            ),
          ]),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: BtChannel.pip,
      builder: (context, inPip, _) =>
          inPip ? _pipView(context) : _fullView(context),
    );
  }

  Widget _fullView(BuildContext context) {
    final obd = App.obd;
    final trips = App.trips;
    final s = App.settings;
    final scheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: SafeArea(
        child: ListenableBuilder(
          listenable: Listenable.merge([obd, trips, App.maintenance, App.fuel, s, App.nav, App.road]),
          builder: (context, _) {
            final v = obd.values;
            final rpm = v[Pids.rpm];
            final coolant = v[Pids.coolant];
            final litres = App.fuel.litresNow;
            final level = litres == null ? null : litres / s.tankLiters * 100;
            final avg = App.fuel.realAvgL100 ?? trips.avgL100 ?? s.defaultL100;
            final range = litres == null ? null : litres / avg * 100;
            final hot = coolant != null && coolant >= 105;
            final redline = rpm != null && rpm >= 6000;

            Widget big(String label, String value, String unit,
                    {Color? color, double size = 64}) =>
                Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(label,
                        style: TextStyle(
                            fontSize: 16, color: scheme.onSurfaceVariant)),
                    FittedBox(
                      child: Text(value,
                          style: TextStyle(
                              fontSize: size,
                              height: 1.1,
                              fontWeight: FontWeight.w900,
                              fontStyle: isSport(context)
                                  ? FontStyle.italic
                                  : FontStyle.normal,
                              color: color)),
                    ),
                    Text(unit,
                        style: TextStyle(
                            fontSize: 14, color: scheme.onSurfaceVariant)),
                  ],
                );

            return Padding(
              padding: EdgeInsets.all(12),
              child: Column(
                children: [
                  Row(
                    children: [
                      IconButton(
                        tooltip: tr('خروج'),
                        iconSize: 28,
                        onPressed: () => Navigator.pop(context),
                        icon: Icon(Icons.close),
                      ),
                      VehicleAvatar(s.vehicle, size: 32),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Text(
                            _listening
                                ? '🎙️ ${_heard.isEmpty ? tr('بسمعك…') : _heard}'
                                : '${s.vehicle.name} • ${obd.status}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                      ),
                      if (App.maintenance.odometerKm != null)
                        Text(tr('العداد ${fmt(App.maintenance.odometerKm)} كم'),
                            style: TextStyle(color: scheme.onSurfaceVariant)),
                    ],
                  ),
                  // Shift light: 12 blocks, green → amber → red up to 6000 rpm.
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Row(
                      children: [
                        for (var i = 0; i < 12; i++)
                          Expanded(
                            child: Container(
                              height: 10,
                              margin: const EdgeInsets.symmetric(horizontal: 2),
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(3),
                                color: (rpm ?? 0) >= 6000 * (i + 1) / 12
                                    ? (i < 7
                                        ? AppColors.ok(context)
                                        : i < 10
                                            ? AppColors.warning(context)
                                            : AppColors.danger(context))
                                    : scheme.outlineVariant,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Speed: the biggest number on screen.
                        // (Hidden on the map: it goes full width like Waze.)
                        if (!_map)
                        Expanded(
                          flex: 3,
                          child: Card(
                            child: Column(children: [
                              Expanded(
                                child: big(
                                  tr('السرعة'),
                                  fmt(v[Pids.speed]),
                                  tr('كم/س'),
                                  size: 140,
                                  color: (v[Pids.speed] ?? 0) > App.road.effectiveLimit &&
                                          s.speedAlertMode != 'off'
                                      ? AppColors.danger(context)
                                      : null,
                                ),
                              ),
                              // Quick speed-limit control for the current road.
                              Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  IconButton(
                                    tooltip: '-10',
                                    iconSize: 32,
                                    onPressed: () =>
                                        s.setSpeedLimit(s.speedLimit - 10),
                                    icon: const Icon(Icons.remove_circle_outline),
                                  ),
                                  Container(
                                    width: 56,
                                    height: 56,
                                    alignment: Alignment.center,
                                    decoration: BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                      border: Border.all(
                                          color: const Color(0xFFD32F2F),
                                          width: 6),
                                    ),
                                    child: Text(
                                      s.speedAlertMode == 'off'
                                          ? '—'
                                          : '${App.road.effectiveLimit.round()}',
                                      style: const TextStyle(
                                          color: Colors.black,
                                          fontSize: 18,
                                          fontWeight: FontWeight.w900),
                                    ),
                                  ),
                                  IconButton(
                                    tooltip: '+10',
                                    iconSize: 32,
                                    onPressed: () =>
                                        s.setSpeedLimit(s.speedLimit + 10),
                                    icon: const Icon(Icons.add_circle_outline),
                                  ),
                                ],
                              ),
                              // Where the limit comes from, and the next camera.
                              Text(
                                App.road.limitIsAuto
                                    ? tr('حد الطريق تلقائي')
                                    : tr('الحد يدوي'),
                                style: TextStyle(
                                    fontSize: 12,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant),
                              ),
                              if (App.road.nextCameraM != null &&
                                  App.road.nextCameraM! <= 1000)
                                Container(
                                  margin: const EdgeInsets.only(top: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 10, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFD32F2F),
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      const Icon(Icons.camera_alt,
                                          color: Colors.white, size: 16),
                                      const SizedBox(width: 6),
                                      Text(
                                        tr('رادار ${(App.road.nextCameraM! / 10).round() * 10} متر'),
                                        style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                              const SizedBox(height: 8),
                            ]),
                          ),
                        ),
                        Expanded(
                          flex: 4,
                          child: _panel == _Panel.map
                              ? _liveMap(context)
                              : _panel == _Panel.music
                                  ? const MusicPanel()
                                  : _panel == _Panel.radio
                                      ? const RadioPanel()
                                  : _panel == _Panel.phone
                                      ? const PhonePanel()
                                      : Column(
                            children: [
                              Expanded(
                                child: Row(children: [
                                  Expanded(
                                    child: Card(
                                      child: big('RPM', fmt(rpm), tr('لفة/د'),
                                          color: redline
                                              ? AppColors.danger(context)
                                              : null),
                                    ),
                                  ),
                                  Expanded(
                                    child: Card(
                                      child: big(tr('حرارة المياه'), fmt(coolant),
                                          '°C',
                                          color: hot
                                              ? AppColors.danger(context)
                                              : null),
                                    ),
                                  ),
                                ]),
                              ),
                              Expanded(
                                child: Row(children: [
                                  Expanded(
                                    child: Card(
                                      child: big(
                                        tr('البنزين'),
                                        fmt(litres, 1),
                                        range == null
                                            ? tr('لتر')
                                            : tr('لتر • ~${fmt(range)} كم'),
                                        color: level != null && level < 15
                                            ? AppColors.warning(context)
                                            : null,
                                      ),
                                    ),
                                  ),
                                  Expanded(
                                    child: Card(
                                      child: obd.instantL100 != null
                                          ? big(tr('الاستهلاك'),
                                              fmt(obd.instantL100, 1), tr('ل/100كم'))
                                          : big(tr('الاستهلاك'),
                                              fmt(obd.fuelRateLh, 2), tr('ل/ساعة')),
                                    ),
                                  ),
                                  Expanded(
                                    child: Card(
                                      child: big(
                                        tr('الرحلة'),
                                        fmt(trips.distanceKm, 1),
                                        trips.active
                                            ? tr('كم • ${fmt(trips.fuelL * s.fuelPrice)} ج.م')
                                            : tr('كم'),
                                      ),
                                    ),
                                  ),
                                ]),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Car-home dock, like a head unit: other apps + media.
                  const SizedBox(height: 8),
                  _Dock(
                      current: _panel,
                      onPanel: (p) => _show(p, toggle: true),
                      onVoice: _voice,
                      listening: _listening),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

class _Dock extends StatelessWidget {
  final _Panel current;
  final void Function(_Panel) onPanel;
  final VoidCallback onVoice;
  final bool listening;
  const _Dock(
      {required this.current,
      required this.onPanel,
      required this.onVoice,
      required this.listening});

  @override
  Widget build(BuildContext context) {
    final bt = App.obd.bt;
    final scheme = Theme.of(context).colorScheme;

    Widget btn(IconData icon, String label, VoidCallback onTap,
            {bool active = false, VoidCallback? onLongPress}) =>
        Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Material(
              color: active ? scheme.primary : scheme.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(14),
              child: InkWell(
                borderRadius: BorderRadius.circular(14),
                onTap: () {
                  HapticFeedback.selectionClick();
                  onTap();
                },
                onLongPress: onLongPress,
                child: SizedBox(
                  height: 56,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(icon,
                          size: 28,
                          color: active ? scheme.onPrimary : scheme.onSurface),
                      if (label.isNotEmpty) ...[
                        const SizedBox(width: 6),
                        Flexible(
                          child: Text(label,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                  fontWeight: FontWeight.w600,
                                  color: active
                                      ? scheme.onPrimary
                                      : scheme.onSurface)),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
        );

    return Row(children: [
      btn(Icons.speed, tr('العدادات'), () => onPanel(_Panel.gauges),
          active: current == _Panel.gauges),
      btn(Icons.navigation, tr('خرائط'), () => onPanel(_Panel.map),
          active: current == _Panel.map),
      btn(Icons.library_music, tr('موسيقى'), () => onPanel(_Panel.music),
          active: current == _Panel.music),
      btn(Icons.radio, tr('راديو'), () => onPanel(_Panel.radio),
          active: current == _Panel.radio),
      btn(Icons.call, tr('مكالمة'), () => onPanel(_Panel.phone),
          active: current == _Panel.phone),
      btn(Icons.play_arrow, '', () => bt.mediaControl('play_pause')),
      // Tap: our voice commands. Long-press: the phone's own assistant.
      btn(Icons.mic, tr('المساعد'), onVoice,
          active: listening, onLongPress: () => bt.launch('assistant')),
    ]);
  }
}
