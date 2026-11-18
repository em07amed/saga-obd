import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:speech_to_text/speech_to_text.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart' show LatLng;
import 'package:flutter/services.dart';
import 'package:wakelock_plus/wakelock_plus.dart';

import '../main.dart';
import '../obd/bt_channel.dart';
import '../obd/pids.dart';
import '../nav/nav_service.dart';
import 'drive_panels.dart';
import 'neon_dash.dart';
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

  final _stt = SpeechToText();
  bool _listening = false;
  String _heard = '';

  Future<void> _voice() async {
    if (_listening) {
      await _stt.stop();
      setState(() => _listening = false);
      return;
    }
    final ok = await _stt.initialize(
      onError: (_) {
        if (mounted) setState(() => _listening = false);
      },
      onStatus: (st) {
        if ((st == 'done' || st == 'notListening') && mounted) {
          setState(() => _listening = false);
        }
      },
    );
    if (!ok) {
      _say(tr('التعرف على الصوت مش متاح على الموبايل ده'));
      return;
    }
    setState(() {
      _listening = true;
      _heard = '';
    });
    await _stt.listen(
      localeId: Lang.isEn ? 'en_US' : 'ar_EG',
      pauseFor: const Duration(seconds: 3),
      listenFor: const Duration(seconds: 15),
      onResult: (r) {
        if (!mounted) return;
        setState(() => _heard = r.recognizedWords);
        if (r.finalResult) {
          setState(() => _listening = false);
          _handle(r.recognizedWords);
        }
      },
    );
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
          final zoom = kmh > 90 ? 15.0 : kmh > 50 ? 16.0 : 17.0;
          try {
            _mapCtl.move(at, zoom);
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
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Stack(children: [
        FlutterMap(
          mapController: _mapCtl,
          options: MapOptions(
            initialCenter: at,
            initialZoom: 17,
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
                    color: const Color(0xFF1E88E5),
                    strokeWidth: 8,
                    borderColor: Colors.white,
                    borderStrokeWidth: 2),
              ]),
            if (_path.length > 1)
              PolylineLayer(polylines: [
                Polyline(points: _path, color: scheme.primary, strokeWidth: 5),
              ]),
            MarkerLayer(markers: [
              for (final c in App.road.cameras)
                Marker(
                  point: c.at,
                  width: 30,
                  height: 30,
                  child: mapPin(const Color(0xFFD32F2F), Icons.camera_alt,
                      size: 15),
                ),
              if (nav.destination != null)
                Marker(
                  point: nav.destination!.at,
                  width: 34,
                  height: 34,
                  child: mapPin(const Color(0xFFD32F2F), Icons.flag),
                ),
              Marker(
                point: at,
                width: 40,
                height: 40,
                child: Transform.rotate(
                  angle: (p.heading.isNaN ? 0 : p.heading) * 3.14159265 / 180,
                  child: Icon(Icons.navigation,
                      size: 40,
                      color: scheme.primary,
                      shadows: const [
                        Shadow(blurRadius: 6, color: Colors.black54)
                      ]),
                ),
              ),
            ]),
            mapAttribution(),
          ],
        ),
        // Turn-by-turn banner while navigating, search bar otherwise.
        if (nav.active && step != null)
          PositionedDirectional(
            top: 8,
            start: 8,
            end: 8,
            child: Material(
              color: const Color(0xFF1E88E5),
              borderRadius: BorderRadius.circular(14),
              elevation: 4,
              child: Padding(
                padding: const EdgeInsets.all(10),
                child: Row(children: [
                  Icon(step.icon, size: 44, color: Colors.white),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(NavService.fmtDist(nav.toNextM),
                            style: const TextStyle(
                                color: Colors.white,
                                fontSize: 24,
                                fontWeight: FontWeight.w900)),
                        Text(tr(step.text),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                                color: Colors.white, fontSize: 16)),
                      ],
                    ),
                  ),
                ]),
              ),
            ),
          )
        else
          PositionedDirectional(
            top: 8,
            start: 8,
            end: 8,
            child: Material(
              elevation: 3,
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
        if (nav.routing)
          const Center(child: CircularProgressIndicator()),
        if (nav.error != null)
          PositionedDirectional(
            bottom: 60,
            start: 8,
            end: 8,
            child: Card(
                child: ListTile(
                    leading: const Icon(Icons.wifi_off),
                    title: Text(nav.error!))),
          ),
        // Remaining distance / time and stop button.
        if (nav.active)
          PositionedDirectional(
            bottom: 8,
            start: 8,
            child: Material(
              elevation: 3,
              borderRadius: BorderRadius.circular(24),
              color: scheme.surface,
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Text(
                      '${NavService.fmtDist(nav.remainingM)} • ${nav.remaining.inMinutes} ${tr('د')}',
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                  const SizedBox(width: 8),
                  IconButton(
                    tooltip: tr('كمّل في Google Maps'),
                    icon: const Icon(Icons.assistant_navigation),
                    onPressed: () => _googleMaps(nav.destination!.at),
                  ),
                  TextButton.icon(
                    onPressed: nav.stop,
                    icon: Icon(Icons.close, color: AppColors.danger(context)),
                    label: Text(tr('إنهاء'),
                        style: TextStyle(color: AppColors.danger(context))),
                  ),
                ]),
              ),
            ),
          ),
        if (!_follow)
          PositionedDirectional(
            bottom: 12,
            end: 12,
            child: FloatingActionButton.small(
              heroTag: 'recenter',
              tooltip: tr('تتبّع موقعي'),
              onPressed: () {
                setState(() => _follow = true);
                _mapCtl.move(at, 17);
              },
              child: const Icon(Icons.my_location),
            ),
          ),
      ]),
    );
  }

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
      backgroundColor: App.settings.driveStyle == 'neon' ? neonBg : null,
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
            final neon = s.driveStyle == 'neon';
            final neonFull = neon && _panel == _Panel.gauges;

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
                      IconButton(
                        tooltip: tr('شكل العدادات'),
                        onPressed: () => s.setDriveStyle(
                            neon ? 'classic' : 'neon'),
                        icon: Icon(neon
                            ? Icons.grid_view_rounded
                            : Icons.speed_rounded,
                            color: neon ? neonCyan : null),
                      ),
                    ],
                  ),
                  // Shift light: 12 blocks, green → amber → red up to 6000 rpm.
                  if (!neonFull) Padding(
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
                  if (neonFull)
                    const Expanded(child: Padding(
                      padding: EdgeInsets.only(top: 6),
                      child: NeonDash(),
                    ))
                  else
                  Expanded(
                    child: Row(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        // Speed: the biggest number on screen.
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
