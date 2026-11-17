import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../obd/obd_service.dart';
import '../obd/pids.dart';
import 'widgets.dart';

/// Every PID the car reports as supported, with its live value.
class ReadingsPage extends StatelessWidget {
  const ReadingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final obd = App.obd;
    return Column(
      children: [
        const ConnectionBar(),
        ListenableBuilder(
          listenable: obd,
          builder: (context, _) => ListTile(
            dense: true,
            title: Text('${obd.supported.length} قراءة مدعومة'),
            subtitle: Text(
                'بروتوكول ${obd.protocol.isEmpty ? '—' : obd.protocol} • ${obd.adapterVersion}'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: 'فحص العداد',
                onPressed: obd.isConnected
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => const OdometerProbePage()))
                    : null,
                icon: const Icon(Icons.speed),
              ),
              FilledButton.tonalIcon(
              onPressed: obd.isConnected
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => const DtcPage()))
                  : null,
              icon: const Icon(Icons.warning_amber),
              label: const Text('الأعطال'),
            ),
            ]),
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: ListenableBuilder(
            listenable: obd,
            builder: (context, _) {
              final defs =
                  Pids.all.where((p) => obd.supported.contains(p.pid)).toList();
              final unknown = obd.supported
                  .where((id) => !Pids.byId.containsKey(id) && id % 0x20 != 0)
                  .toList()
                ..sort();
              if (defs.isEmpty) {
                return const Center(
                    child: Text('اتصل بالعربية عشان تظهر القراءات'));
              }
              return ListView(
                children: [
                  for (final d in defs)
                    ListTile(
                      title: Text(d.name),
                      subtitle: Text(d.hex),
                      trailing: Text(
                        '${fmt(obd.values[d.pid], d.decimals)} ${d.unit}',
                        style: Theme.of(context).textTheme.titleMedium,
                      ),
                    ),
                  if (unknown.isNotEmpty)
                    ListTile(
                      title: const Text('PIDs مدعومة من غير معادلة في التطبيق'),
                      subtitle: Text(unknown
                          .map((e) =>
                              '01${e.toRadixString(16).padLeft(2, '0').toUpperCase()}')
                          .join('  ')),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

class DtcPage extends StatefulWidget {
  const DtcPage({super.key});

  @override
  State<DtcPage> createState() => _DtcPageState();
}

class _DtcPageState extends State<DtcPage> {
  List<String>? _codes;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _read();
  }

  Future<void> _read() async {
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final codes = await App.obd.readDtcs();
      if (mounted) setState(() => _codes = codes);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _clear() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('مسح الأعطال؟'),
        content: const Text(
            'هيتم مسح الأكواد ولمبة Check Engine، وكمان قراءات الـ readiness '
            'هتتصفر. لو العطل لسه موجود هيرجع تاني. اعمل كده والموتور واقف '
            'والكونتاكت شغال.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('امسح')),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final done = await App.obd.clearDtcs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(done ? 'تم المسح' : 'الكمبيوتر ما أكدش المسح')));
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
    await _read();
  }

  @override
  Widget build(BuildContext context) {
    final codes = _codes;
    return Scaffold(
      appBar: AppBar(
        title: const Text('أكواد الأعطال'),
        actions: [
          IconButton(
              onPressed: _busy ? null : _read, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _busy && codes == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                if (_error != null)
                  Card(
                      child: ListTile(
                          leading: const Icon(Icons.error_outline),
                          title: Text(_error!))),
                if (codes != null && codes.isEmpty)
                  const Card(
                    child: ListTile(
                      leading: Icon(Icons.check_circle, color: AppColors.ok),
                      title: Text('مفيش أعطال مخزنة'),
                    ),
                  ),
                if (codes != null)
                  for (final c in codes)
                    Card(
                      child: ListTile(
                        leading: const Icon(Icons.warning_amber,
                            color: AppColors.warning),
                        title: Text(c,
                            style: const TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                        subtitle: Text(_describe(c)),
                      ),
                    ),
                const SizedBox(height: 16),
                if (codes != null && codes.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger,
                        foregroundColor: Colors.white),
                    onPressed: _busy ? null : _clear,
                    icon: const Icon(Icons.delete_forever),
                    label: const Text('مسح الأعطال'),
                  ),
              ],
            ),
    );
  }

  static String _describe(String code) {
    final system = switch (code[0]) {
      'P' => 'محرك / فتيس',
      'C' => 'شاسيه',
      'B' => 'بودي',
      _ => 'شبكة',
    };
    final generic = code.length > 1 && code[1] == '0' ? 'كود عام (SAE)' : 'كود خاص بالشركة';
    return '$system • $generic — ابحث عن الكود لمعرفة التفاصيل';
  }
}

class OdometerProbePage extends StatefulWidget {
  const OdometerProbePage({super.key});

  @override
  State<OdometerProbePage> createState() => _OdometerProbePageState();
}

class _OdometerProbePageState extends State<OdometerProbePage> {
  List<ProbeResult>? _results;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    _run();
  }

  Future<void> _run() async {
    setState(() => _busy = true);
    final r = await App.obd.probeOdometer();
    if (mounted) {
      setState(() {
        _results = r;
        _busy = false;
      });
    }
  }

  String get _report => (_results ?? [])
      .map((r) => '${r.cmd} → ${r.raw.replaceAll('\n', ' | ')}')
      .join('\n');

  @override
  Widget build(BuildContext context) {
    final results = _results;
    final found = results?.where((r) => r.km != null && r.cmd != '0131');
    return Scaffold(
      appBar: AppBar(
        title: const Text('فحص العداد'),
        actions: [
          IconButton(
            tooltip: 'نسخ النتيجة',
            onPressed: results == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _report));
                    ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('اتنسخت')));
                  },
            icon: const Icon(Icons.copy),
          ),
          IconButton(
              onPressed: _busy ? null : _run,
              icon: const Icon(Icons.refresh)),
        ],
      ),
      body: results == null
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(12),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: ListTile(
                    title: Text(found != null && found.isNotEmpty
                        ? 'العداد: ${fmt(found.first.km, 1)} كم'
                        : 'العربية ما ردتش بقراءة العداد بالطرق القياسية'),
                    subtitle: const Text(
                        'قارن الرقم بعداد التابلوه. لو مفيش نتيجة، انسخ الردود وابعتها.'),
                  ),
                ),
                for (final r in results)
                  Card(
                    child: ListTile(
                      title: Text(r.label),
                      subtitle: Text('${r.cmd}\n${r.raw.isEmpty ? '(فاضي)' : r.raw}',
                          textDirection: TextDirection.ltr),
                      isThreeLine: true,
                      trailing: Text(
                          r.km == null ? 'مش مدعوم' : '${fmt(r.km, 1)} كم',
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
              ],
            ),
    );
  }
}
