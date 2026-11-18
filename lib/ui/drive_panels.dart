import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n.dart';
import '../main.dart';
import '../obd/bt_channel.dart';

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
    if (!np.access) {
      return Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.library_music, size: 48),
              const SizedBox(height: 8),
              Text(
                tr('عشان أعرض الأغنية اللي شغالة وأتحكم فيها، محتاج صلاحية قراءة الإشعارات. فعّل Car OBD في الصفحة اللي هتفتح.'),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: () => App.obd.bt.openNotificationAccess(),
                icon: const Icon(Icons.lock_open),
                label: Text(tr('اسمح')),
              ),
            ],
          ),
        ),
      );
    }
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
                Text(np.title ?? tr('مفيش حاجة شغالة'),
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
                const SizedBox(height: 12),
                Row(children: [
                  ctl(Icons.skip_previous, 'prev'),
                  const SizedBox(width: 12),
                  ctl(np.playing ? Icons.pause : Icons.play_arrow, 'play_pause',
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
            .take(30)
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
            child: q.isNotEmpty
                ? ListView(children: [
                    for (final c in results)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.person),
                        title: Text(c.name),
                        subtitle: Text(c.number,
                            textDirection: TextDirection.ltr),
                        trailing: IconButton.filled(
                          icon: const Icon(Icons.call),
                          onPressed: () => _call(c),
                        ),
                      ),
                  ])
                : favs.isEmpty
                    ? Center(
                        child: Text(
                          tr('مفيش مفضلين. علّم جهات الاتصال بنجمة في تطبيق الأسماء، أو دوّر فوق.'),
                          textAlign: TextAlign.center,
                        ),
                      )
                    : GridView.count(
                        crossAxisCount: 4,
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: 1.6,
                        children: [
                          for (final c in favs)
                            Material(
                              color: scheme.surfaceContainerHighest,
                              borderRadius: BorderRadius.circular(12),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(12),
                                onTap: () => _call(c),
                                child: Padding(
                                  padding: const EdgeInsets.all(6),
                                  child: Column(
                                    mainAxisAlignment: MainAxisAlignment.center,
                                    children: [
                                      CircleAvatar(
                                        radius: 16,
                                        backgroundColor: scheme.primary,
                                        child: Text(
                                            c.name.characters.first,
                                            style: TextStyle(
                                                color: scheme.onPrimary)),
                                      ),
                                      const SizedBox(height: 4),
                                      Text(c.name,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                        ],
                      ),
          ),
        ]),
      ),
    );
  }
}
