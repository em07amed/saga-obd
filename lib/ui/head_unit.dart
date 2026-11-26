part of 'drive_mode_page.dart';

// Head-unit look for drive mode: black, glassy cards, glowing amber accents.
const _huBg = Color(0xFF000000);
const _huCard = Color(0xFF0E0E0F);
const _huLine = Color(0x22FFFFFF);
const _huRed = Color(0xFFFF453A);

/// Glowing amber accent, same as the app icon.
const _huAccent = Color(0xFFFF9904);
const _huMuted = Color(0xFF9AA7B4);

BoxDecoration _huBox({Gradient? gradient, Color? border}) => BoxDecoration(
      color: gradient == null ? _huCard : null,
      gradient: gradient,
      borderRadius: BorderRadius.circular(18),
      border: Border.all(color: border ?? _huLine),
    );

/// Top bar: car + link status, clock with city/temperature, BT + battery.
class _HeadStatusBar extends StatefulWidget {
  final VoidCallback onClose;
  final String subtitle;
  const _HeadStatusBar({required this.onClose, required this.subtitle});

  @override
  State<_HeadStatusBar> createState() => _HeadStatusBarState();
}

class _HeadStatusBarState extends State<_HeadStatusBar> {
  Timer? _clock, _slow;
  int? _battery;
  String? _city;
  double? _temp;

  @override
  void initState() {
    super.initState();
    _clock = Timer.periodic(const Duration(seconds: 20), (_) {
      if (mounted) setState(() {});
    });
    _refreshSlow();
    _slow = Timer.periodic(const Duration(minutes: 5), (_) => _refreshSlow());
  }

  @override
  void dispose() {
    _clock?.cancel();
    _slow?.cancel();
    super.dispose();
  }

  Future<void> _refreshSlow() async {
    final b = await App.obd.bt.battery().catchError((_) => null);
    if (mounted) setState(() => _battery = b);
    // Weather + city at most every 30 min (free, no key).
    if (_temp != null && DateTime.now().minute % 30 > 4) return;
    try {
      final p = await Geolocator.getLastKnownPosition();
      if (p == null) return;
      final w = await http.get(Uri.https('api.open-meteo.com', '/v1/forecast', {
        'latitude': '${p.latitude}',
        'longitude': '${p.longitude}',
        'current': 'temperature_2m',
      })).timeout(const Duration(seconds: 8));
      final t = (jsonDecode(w.body)['current']?['temperature_2m'] as num?)
          ?.toDouble();
      String? city;
      try {
        final r = await http.get(Uri.https('photon.komoot.io', '/reverse', {
          'lat': '${p.latitude}',
          'lon': '${p.longitude}',
        })).timeout(const Duration(seconds: 8));
        final pr = (jsonDecode(r.body)['features'] as List).first['properties'];
        city = (pr['city'] ?? pr['county'] ?? pr['state']) as String?;
      } catch (_) {}
      if (mounted) {
        setState(() {
          _temp = t;
          _city = city ?? _city;
        });
      }
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final s = App.settings;
    final now = DateTime.now();
    final h = now.hour % 12 == 0 ? 12 : now.hour % 12;
    final ampm = Lang.isEn ? (now.hour < 12 ? 'AM' : 'PM') : (now.hour < 12 ? 'ص' : 'م');
    final time = '$h:${now.minute.toString().padLeft(2, '0')} $ampm';
    final place = [
      if (_city != null) _city!,
      if (_temp != null) '${_temp!.round()}°',
    ].join(' • ');
    final connected = App.obd.isConnected;
    final b = _battery;
    return Container(
      height: 64,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: _huLine)),
      ),
      child: Row(children: [
        IconButton(
          tooltip: tr('خروج'),
          onPressed: widget.onClose,
          icon: const Icon(Icons.close, color: _huMuted),
        ),
        VehicleAvatar(s.vehicle, size: 44),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(s.vehicle.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold)),
              Text(widget.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: _huMuted, fontSize: 13)),
            ],
          ),
        ),
        Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          Text(time,
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 24,
                  fontWeight: FontWeight.bold)),
          if (place.isNotEmpty)
            Text(place, style: const TextStyle(color: _huMuted, fontSize: 13)),
        ]),
        Expanded(
          child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
            Icon(connected ? Icons.bluetooth_connected : Icons.bluetooth,
                color: connected ? _huAccent : _huMuted),
            const SizedBox(width: 14),
            if (b != null) ...[
              Icon(
                  b > 80
                      ? Icons.battery_full
                      : b > 50
                          ? Icons.battery_5_bar
                          : b > 20
                              ? Icons.battery_3_bar
                              : Icons.battery_alert,
                  color: b <= 20 ? _huRed : Colors.white),
              Text('$b%',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.w600)),
            ],
            const SizedBox(width: 8),
          ]),
        ),
      ]),
    );
  }
}

/// Bottom navigation of the head unit, active tab underlined in red.
class _HeadNav extends StatelessWidget {
  final _Panel current;
  final void Function(_Panel) onPanel;
  final VoidCallback onVoice;
  final bool listening;
  const _HeadNav(
      {required this.current,
      required this.onPanel,
      required this.onVoice,
      required this.listening});

  @override
  Widget build(BuildContext context) {
    Widget item(IconData icon, String label, VoidCallback onTap,
        {bool active = false, VoidCallback? onLongPress}) {
      return Expanded(
        child: InkWell(
          onTap: () {
            HapticFeedback.selectionClick();
            onTap();
          },
          onLongPress: onLongPress,
          child: Container(
            decoration: BoxDecoration(
              gradient: active
                  ? const LinearGradient(
                      begin: Alignment.bottomCenter,
                      end: Alignment.topCenter,
                      colors: [Color(0x55FF9904), Color(0x00FF9904)])
                  : null,
              border: Border(
                  bottom: BorderSide(
                      color: active ? _huAccent : Colors.transparent, width: 3)),
            ),
            child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(icon, size: 28, color: active ? Colors.white : _huMuted),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: 14,
                      color: active ? Colors.white : _huMuted,
                      fontWeight: active ? FontWeight.bold : null)),
            ]),
          ),
        ),
      );
    }

    return Container(
      height: 76,
      decoration: const BoxDecoration(
        color: Color(0xFF0A0A0B),
        border: Border(top: BorderSide(color: _huLine)),
      ),
      child: Row(children: [
        item(Icons.home_outlined, tr('الرئيسية'), () => onPanel(_Panel.home),
            active: current == _Panel.home),
        item(Icons.map_outlined, tr('الخرائط'), () => onPanel(_Panel.map),
            active: current == _Panel.map),
        item(Icons.music_note_outlined, tr('الموسيقى'),
            () => onPanel(_Panel.music),
            active: current == _Panel.music),
        item(Icons.radio_outlined, tr('الراديو'), () => onPanel(_Panel.radio),
            active: current == _Panel.radio),
        item(Icons.directions_car_outlined, tr('حالة العربية'),
            () => onPanel(_Panel.gauges),
            active: current == _Panel.gauges),
        item(Icons.call_outlined, tr('الهاتف'), () => onPanel(_Panel.phone),
            active: current == _Panel.phone),
        item(listening ? Icons.mic : Icons.mic_none, tr('المساعد'), onVoice,
            active: listening,
            onLongPress: () => App.obd.bt.launch('assistant')),
      ]),
    );
  }
}

/// Now playing: our radio (name, logo, live, favourite) or media keys for
/// whatever app is playing on the phone.
class _HeadMediaCard extends StatelessWidget {
  final VoidCallback onOpen;
  const _HeadMediaCard({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final radio = App.radio;
    final st = radio.current;
    final bt = App.obd.bt;
    Widget ctl(IconData i, VoidCallback f, {bool big = false}) => Material(
          color: Colors.white.withValues(alpha: big ? 0.18 : 0.10),
          borderRadius: BorderRadius.circular(12),
          child: InkWell(
            borderRadius: BorderRadius.circular(12),
            onTap: () {
              HapticFeedback.selectionClick();
              f();
            },
            child: SizedBox(
                width: big ? 60 : 50,
                height: big ? 56 : 48,
                child: Icon(i, color: Colors.white, size: big ? 34 : 28)),
          ),
        );
    final art = st != null && st.favicon.isNotEmpty
        ? Image.network(st.favicon,
            fit: BoxFit.cover,
            errorBuilder: (_, __, ___) =>
                const Icon(Icons.radio, color: Colors.white70, size: 34))
        : Icon(st != null ? Icons.radio : Icons.music_note,
            color: Colors.white70, size: 34);
    return Container(
      decoration: _huBox(
        gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF6B3E00), Color(0xFF241500)]),
        border: const Color(0x66FF9904),
      ),
      padding: const EdgeInsets.all(14),
      child: Column(children: [
        Expanded(
          child: InkWell(
            onTap: onOpen,
            child: Row(children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: Container(
                    width: 64,
                    height: 64,
                    color: Colors.black26,
                    child: Center(child: art)),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(st?.name ?? tr('الموسيقى'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.bold)),
                    Text(
                        st != null
                            ? (radio.loading ? tr('بيحمّل…') : tr('راديو'))
                            : tr('التطبيق اللي شغال على الموبايل'),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70)),
                  ],
                ),
              ),
            ]),
          ),
        ),
        // Live radio has no length: a "live" strip instead of a seek bar.
        if (st != null && radio.playing)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(children: [
              const Icon(Icons.circle, color: _huAccent, size: 10),
              const SizedBox(width: 6),
              Text(tr('مباشر'), style: const TextStyle(color: Colors.white70)),
              const SizedBox(width: 8),
              Expanded(
                  child: Container(
                      height: 3,
                      decoration: BoxDecoration(
                          color: Colors.white70,
                          borderRadius: BorderRadius.circular(2)))),
            ]),
          ),
        Row(mainAxisAlignment: MainAxisAlignment.center, children: [
          if (st != null) ...[
            ctl(radio.playing ? Icons.pause : Icons.play_arrow,
                () => radio.playing ? radio.stop() : radio.play(st),
                big: true),
            const Spacer(),
            ctl(radio.isFav(st) ? Icons.favorite : Icons.favorite_border,
                () => radio.toggleFav(st)),
          ] else ...[
            ctl(Icons.skip_previous, () => bt.mediaKey('prev').catchError((_) {})),
            const SizedBox(width: 12),
            ctl(Icons.play_arrow,
                () => bt.mediaKey('play_pause').catchError((_) {}),
                big: true),
            const SizedBox(width: 12),
            ctl(Icons.skip_next, () => bt.mediaKey('next').catchError((_) {})),
          ],
        ]),
      ]),
    );
  }
}

/// Car health at a glance: fuel, consumption, next service, quick DTC scan.
class _HeadCarCard extends StatelessWidget {
  final VoidCallback onOpen;
  const _HeadCarCard({required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final s = App.settings;
    final obd = App.obd;
    final coolant = obd.values[Pids.coolant];
    final litres = App.fuel.litresNow;
    final avg = App.fuel.realAvgL100 ?? App.trips.avgL100 ?? s.defaultL100;
    final due = App.maintenance.due;
    final next = due.isEmpty ? null : due.first;
    final hot = coolant != null && coolant >= s.coolantAlert;
    final attention = hot || due.any((d) => d.overdue);
    final (label, color) = !obd.isConnected
        ? (tr('مش متصلة'), _huMuted)
        : attention
            ? (tr('محتاجة انتباه'), const Color(0xFFFFB300))
            : (tr('ممتازة'), const Color(0xFF4CAF50));

    Widget line(String t, {Color? c}) => Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Text(t,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: c ?? Colors.white, fontSize: 15)),
        );

    return Container(
      decoration: _huBox(),
      padding: const EdgeInsets.all(14),
      child: InkWell(
        onTap: onOpen,
        child: Row(children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Row(children: [
                  Text(tr('حالة السيارة: '),
                      style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  Text(label,
                      style: TextStyle(
                          color: color,
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(width: 4),
                  if (obd.isConnected)
                    Icon(attention ? Icons.warning_amber : Icons.check,
                        color: color, size: 20),
                ]),
                if (hot) line(tr('حرارة الموتور ${fmt(coolant)}°C'), c: _huRed),
                line(litres == null
                    ? tr('مستوى الوقود: سجّل تفويلة')
                    : tr('مستوى الوقود: ${(litres / s.tankLiters * 100).clamp(0, 100).round()}% (${(litres / avg * 100).round()} كم متبقي)')),
                line(tr('استهلاك الوقود: ${avg.toStringAsFixed(1)} لتر / 100 كم')),
                line(
                    next == null
                        ? tr('الصيانة القادمة: مفيش مواعيد متسجلة')
                        : next.kmLeft != null
                            ? tr('الصيانة القادمة: بعد ${next.kmLeft!.round()} كم (${tr(next.entry.type)})')
                            : tr('الصيانة القادمة: بعد ${next.daysLeft} يوم (${tr(next.entry.type)})'),
                    c: next != null && next.overdue ? _huRed : null),
                const SizedBox(height: 8),
                ActionChip(
                  backgroundColor: Colors.white.withValues(alpha: 0.06),
                  side: const BorderSide(color: _huLine),
                  avatar: const Icon(Icons.check_circle,
                      color: Color(0xFF4CAF50), size: 18),
                  label: Text(tr('فحص الأعطال سريع'),
                      style: const TextStyle(color: Colors.white)),
                  onPressed: () => Navigator.push(context,
                      MaterialPageRoute(builder: (_) => const DtcPage())),
                ),
              ],
            ),
          ),
          const SizedBox(width: 8),
          VehicleAvatar(s.vehicle, size: 110),
        ]),
      ),
    );
  }
}
