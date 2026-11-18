import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n.dart';
import '../main.dart';
import '../obd/bt_channel.dart';
import '../radio/radio_service.dart';

/// Now playing from any music app, with controls, inside drive mode.
class MusicPanel extends StatefulWidget {
  const MusicPanel({super.key});

  @override
  State<MusicPanel> createState() => _MusicPanelState();
}

class _MusicPanelState extends State<MusicPanel> {
  NowPlaying? _np;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _poll();
    _timer = Timer.periodic(const Duration(seconds: 1), (_) => _poll());
  }

  Future<void> _poll() async {
    try {
      final np = await App.obd.bt.nowPlaying();
      if (mounted) setState(() => _np = np);
    } catch (_) {}
  }

  Future<void> _act(String a) async {
    await App.obd.bt.mediaControl(a).catchError((_) {});
    await Future<void>.delayed(const Duration(milliseconds: 300));
    _poll();
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final np = _np;
    final scheme = Theme.of(context).colorScheme;
    if (np == null) {
      return const Card(child: Center(child: CircularProgressIndicator()));
    }
    final noInfo = !np.access;
    Widget ctl(IconData i, String a, {double size = 44, bool main = false}) =>
        IconButton.filled(
          iconSize: size,
          style: IconButton.styleFrom(
            backgroundColor:
                main ? scheme.primary : scheme.surfaceContainerHighest,
            foregroundColor: main ? scheme.onPrimary : scheme.onSurface,
            padding: const EdgeInsets.all(14),
          ),
          onPressed: () => _act(a),
          icon: Icon(i),
        );
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Row(children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(12),
            child: SizedBox(
              width: 140,
              height: 140,
              child: np.art != null
                  ? Image.memory(np.art!, fit: BoxFit.cover, gaplessPlayback: true)
                  : Container(
                      color: scheme.surfaceContainerHighest,
                      child: const Icon(Icons.music_note, size: 56)),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                    noInfo
                        ? tr('التحكم في الموسيقى')
                        : np.title ?? tr('مفيش حاجة شغالة'),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontWeight: FontWeight.bold)),
                if (np.artist != null)
                  Text(np.artist!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleMedium),
                if (np.app != null)
                  Text(np.app!,
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                if (noInfo)
                  Text(tr('شغّل الموسيقى من أي تطبيق وتحكّم فيها من هنا'),
                      style: TextStyle(color: scheme.onSurfaceVariant)),
                const SizedBox(height: 12),
                Row(children: [
                  ctl(Icons.skip_previous, 'prev'),
                  const SizedBox(width: 12),
                  ctl(
                      noInfo
                          ? Icons.play_arrow
                          : np.playing
                              ? Icons.pause
                              : Icons.play_arrow,
                      'play_pause',
                      size: 52, main: true),
                  const SizedBox(width: 12),
                  ctl(Icons.skip_next, 'next'),
                ]),
              ],
            ),
          ),
        ]),
      ),
    );
  }
}

/// Favourite contacts as big buttons, plus search, calling directly.
class PhonePanel extends StatefulWidget {
  const PhonePanel({super.key});

  @override
  State<PhonePanel> createState() => _PhonePanelState();
}

class _PhonePanelState extends State<PhonePanel> {
  List<Contact>? _all;
  bool _denied = false;
  String _q = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final st = await Permission.contacts.request();
    if (!st.isGranted) {
      if (mounted) setState(() => _denied = true);
      return;
    }
    final list = await App.obd.bt.contacts().catchError((_) => <Contact>[]);
    if (mounted) setState(() => _all = list);
  }

  Future<void> _call(Contact c) async {
    if (!(await Permission.phone.request()).isGranted) return;
    await App.obd.bt.call(c.number).catchError((_) {});
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    if (_denied) {
      return Card(
        child: Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Text(tr('محتاج صلاحية جهات الاتصال')),
            const SizedBox(height: 8),
            FilledButton(onPressed: openAppSettings, child: Text(tr('افتح الإعدادات'))),
          ]),
        ),
      );
    }
    final all = _all;
    if (all == null) {
      return const Card(child: Center(child: CircularProgressIndicator()));
    }
    final q = _q.trim().toLowerCase();
    final favs = all.where((c) => c.starred).take(8).toList();
    final results = q.isEmpty
        ? const <Contact>[]
        : all
            .where((c) =>
                c.name.toLowerCase().contains(q) ||
                c.number.replaceAll(' ', '').contains(q))
            
            .toList();
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(10),
        child: Column(children: [
          TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: tr('دوّر على اسم أو رقم'),
              border: const OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _q = v),
          ),
          const SizedBox(height: 8),
          Expanded(
            child: _list(context, q.isNotEmpty ? results : all,
                favs: q.isEmpty ? favs : const []),
          ),
        ]),
      ),
    );
  }

  Widget _list(BuildContext context, List<Contact> items,
      {required List<Contact> favs}) {
    final scheme = Theme.of(context).colorScheme;
    if (items.isEmpty) {
      return Center(child: Text(tr('مفيش أسماء')));
    }
    final hasFavs = favs.isNotEmpty;
    return ListView.builder(
      itemCount: items.length + (hasFavs ? 2 : 1),
      itemBuilder: (context, i) {
        if (hasFavs && i == 0) {
          // Favourites as big buttons on top.
          return Wrap(spacing: 8, runSpacing: 8, children: [
            for (final c in favs)
              ActionChip(
                avatar: Icon(Icons.star, color: scheme.primary, size: 18),
                label: Text(c.name),
                onPressed: () => _call(c),
                padding: const EdgeInsets.all(10),
              ),
          ]);
        }
        final header = hasFavs ? 1 : 0;
        if (i == header) {
          return Padding(
            padding: const EdgeInsets.fromLTRB(4, 10, 4, 4),
            child: Text(tr('كل الأسماء (${items.length})'),
                style: TextStyle(
                    color: scheme.primary, fontWeight: FontWeight.bold)),
          );
        }
        final c = items[i - header - 1];
        return ListTile(
          dense: true,
          leading: CircleAvatar(
            radius: 16,
            child: Text(c.name.characters.first),
          ),
          title: Text(c.name),
          subtitle: Text(c.number, textDirection: TextDirection.ltr),
          trailing: IconButton.filled(
            icon: const Icon(Icons.call),
            onPressed: () => _call(c),
          ),
          onTap: () => _call(c),
        );
      },
    );
  }
}

/// Internet radio: Egyptian stations, search, favourites, now playing.
class RadioPanel extends StatefulWidget {
  const RadioPanel({super.key});

  @override
  State<RadioPanel> createState() => _RadioPanelState();
}

class _RadioPanelState extends State<RadioPanel> {
  List<Station>? _list;
  String? _err;
  bool _favsOnly = false;
  final _q = TextEditingController();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([String? q]) async {
    setState(() {
      _list = null;
      _err = null;
    });
    try {
      final r = q == null || q.trim().isEmpty
          ? await App.radio.egypt()
          : await App.radio.search(q.trim());
      if (mounted) setState(() => _list = r);
    } catch (_) {
      if (mounted) setState(() => _err = tr('الراديو محتاج نت'));
    }
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

  Widget _logo(Station s, double size) => ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: s.favicon.startsWith('http')
            ? Image.network(s.favicon,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (_, __, ___) =>
                    Icon(Icons.radio, size: size * 0.8))
            : Icon(Icons.radio, size: size * 0.8),
      );

  @override
  Widget build(BuildContext context) {
    final r = App.radio;
    final scheme = Theme.of(context).colorScheme;
    return ListenableBuilder(
      listenable: r,
      builder: (context, _) {
        final items = _favsOnly ? r.favourites : (_list ?? const <Station>[]);
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(children: [
              // Now playing.
              if (r.current != null)
                Container(
                  padding: const EdgeInsets.all(8),
                  margin: const EdgeInsets.only(bottom: 8),
                  decoration: BoxDecoration(
                    color: scheme.primaryContainer,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Row(children: [
                    _logo(r.current!, 44),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(r.current!.name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 16)),
                          Text(
                              r.error != null
                                  ? tr(r.error!)
                                  : r.loading
                                      ? tr('بيوصل…')
                                      : r.playing
                                          ? tr('شغال')
                                          : tr('واقف'),
                              style: TextStyle(color: scheme.onSurfaceVariant)),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: tr('مفضلة'),
                      icon: Icon(r.isFav(r.current!)
                          ? Icons.star
                          : Icons.star_border),
                      onPressed: () => r.toggleFav(r.current!),
                    ),
                    IconButton.filled(
                      iconSize: 36,
                      onPressed: r.loading ? null : r.toggle,
                      icon: Icon(r.playing ? Icons.stop : Icons.play_arrow),
                    ),
                  ]),
                ),
              Row(children: [
                Expanded(
                  child: TextField(
                    controller: _q,
                    textInputAction: TextInputAction.search,
                    onSubmitted: (v) {
                      setState(() => _favsOnly = false);
                      _load(v);
                    },
                    decoration: InputDecoration(
                      isDense: true,
                      prefixIcon: const Icon(Icons.search),
                      hintText: tr('دوّر على محطة'),
                      border: const OutlineInputBorder(),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                FilterChip(
                  label: Text(tr('المفضلة')),
                  avatar: const Icon(Icons.star, size: 16),
                  selected: _favsOnly,
                  onSelected: (v) => setState(() => _favsOnly = v),
                ),
              ]),
              const SizedBox(height: 6),
              Expanded(
                child: _err != null && !_favsOnly
                    ? Center(child: Text(_err!))
                    : _list == null && !_favsOnly
                        ? const Center(child: CircularProgressIndicator())
                        : items.isEmpty
                            ? Center(
                                child: Text(_favsOnly
                                    ? tr('دوس ⭐ على أي محطة عشان تتحفظ هنا')
                                    : tr('ما لقيتش محطات')))
                            : ListView.builder(
                                itemCount: items.length,
                                itemBuilder: (context, i) {
                                  final s = items[i];
                                  final on = r.current?.id == s.id;
                                  return ListTile(
                                    dense: true,
                                    selected: on,
                                    leading: _logo(s, 36),
                                    title: Text(s.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis),
                                    subtitle: s.tags.isEmpty
                                        ? null
                                        : Text(s.tags,
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis),
                                    trailing: IconButton(
                                      icon: Icon(r.isFav(s)
                                          ? Icons.star
                                          : Icons.star_border),
                                      onPressed: () => r.toggleFav(s),
                                    ),
                                    onTap: () => r.play(s),
                                  );
                                },
                              ),
              ),
            ]),
          ),
        );
      },
    );
  }
}
