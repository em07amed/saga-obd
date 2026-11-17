import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../obd/obd_service.dart';
import '../obd/pids.dart';
import 'widgets.dart';
import '../l10n.dart';

/// Every PID the car reports as supported, with its live value.
class ReadingsPage extends StatelessWidget {
  const ReadingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final obd = App.obd;
    return Column(
      children: [
        ConnectionBar(),
        ListenableBuilder(
          listenable: obd,
          builder: (context, _) => ListTile(
            dense: true,
            title: Text(tr('${obd.supportedDefs.length} قراءة مدعومة')),
            subtitle: Text(
                tr('بروتوكول ${obd.protocol.isEmpty ? '—' : obd.protocol} • ${obd.adapterVersion}')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: tr('فحص العداد'),
                onPressed: obd.isConnected
                    ? () => Navigator.of(context).push(MaterialPageRoute(
                        builder: (_) => OdometerProbePage()))
                    : null,
                icon: Icon(Icons.speed),
              ),
              FilledButton.tonalIcon(
              onPressed: obd.isConnected
                  ? () => Navigator.of(context).push(MaterialPageRoute(
                      builder: (_) => DtcPage()))
                  : null,
              icon: Icon(Icons.warning_amber),
              label: Text(tr('الأعطال')),
            ),
            ]),
          ),
        ),
        Divider(height: 1),
        Expanded(
          child: ListenableBuilder(
            listenable: obd,
            builder: (context, _) {
              final defs = obd.supportedDefs;
              if (defs.isEmpty) {
                return Center(
                    child: Text(tr('اتصل بالعربية عشان تظهر القراءات')));
              }
              return ListView(
                children: [
                  if (obd.vin != null)
                    ListTile(
                      leading: Icon(Icons.badge_outlined),
                      title: Text(tr('رقم الشاسيه (VIN)')),
                      subtitle: Text(obd.vin!,
                          textDirection: TextDirection.ltr),
                    ),
                  for (final d in defs)
                    ListTile(
                      title: Text(tr(d.name)),
                      subtitle: Text(d.hex),
                      trailing: ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: 190),
                        child: Text(
                          _valueText(obd, d),
                          textAlign: TextAlign.end,
                          // Numbers with units read left-to-right ("841 RPM").
                          textDirection:
                              d.text == null || !Pids.byId.containsKey(d.pid)
                                  ? TextDirection.ltr
                                  : null,
                          style: Theme.of(context).textTheme.titleMedium,
                        ),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  static String _valueText(ObdService obd, PidDef d) {
    final raw = obd.rawBytes[d.pid];
    if (raw == null) return '…';
    if (d.text != null) return tr(d.text!(raw));
    return '${fmt(obd.values[d.pid], d.decimals)} ${d.unit}'.trim();
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
        title: Text(tr('مسح الأعطال؟')),
        content: Text(
            tr('هيتم مسح الأكواد ولمبة Check Engine، وكمان قراءات الـ readiness '
            'هتتصفر. لو العطل لسه موجود هيرجع تاني. اعمل كده والموتور واقف '
            'والكونتاكت شغال.')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('امسح'))),
        ],
      ),
    );
    if (ok != true) return;
    setState(() => _busy = true);
    try {
      final done = await App.obd.clearDtcs();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(done ? tr('تم المسح') : tr('الكمبيوتر ما أكدش المسح'))));
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
        title: Text(tr('أكواد الأعطال')),
        actions: [
          IconButton(
              onPressed: _busy ? null : _read, icon: Icon(Icons.refresh)),
        ],
      ),
      body: _busy && codes == null
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(12),
              children: [
                if (_error != null)
                  Card(
                      child: ListTile(
                          leading: Icon(Icons.error_outline),
                          title: Text(_error!))),
                if (codes != null && codes.isEmpty)
                  Card(
                    child: ListTile(
                      leading: Icon(Icons.check_circle, color: AppColors.ok(context)),
                      title: Text(tr('مفيش أعطال مخزنة')),
                    ),
                  ),
                if (codes != null)
                  for (final c in codes)
                    Card(
                      child: ListTile(
                        leading: Icon(Icons.warning_amber,
                            color: AppColors.warning(context)),
                        title: Text(c,
                            style: TextStyle(
                                fontSize: 22, fontWeight: FontWeight.bold)),
                        subtitle: Text(_describe(c)),
                      ),
                    ),
                SizedBox(height: 16),
                if (codes != null && codes.isNotEmpty)
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                        backgroundColor: AppColors.danger(context),
                        foregroundColor: Colors.white),
                    onPressed: _busy ? null : _clear,
                    icon: Icon(Icons.delete_forever),
                    label: Text(tr('مسح الأعطال')),
                  ),
              ],
            ),
    );
  }

  static String _describe(String code) {
    final system = switch (code[0]) {
      'P' => tr('محرك / فتيس'),
      'C' => tr('شاسيه'),
      'B' => tr('بودي'),
      _ => tr('شبكة'),
    };
    final generic = code.length > 1 && code[1] == '0' ? tr('كود عام (SAE)') : tr('كود خاص بالشركة');
    return tr('$system • $generic — ابحث عن الكود لمعرفة التفاصيل');
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
        title: Text(tr('فحص العداد')),
        actions: [
          IconButton(
            tooltip: tr('نسخ النتيجة'),
            onPressed: results == null
                ? null
                : () {
                    Clipboard.setData(ClipboardData(text: _report));
                    ScaffoldMessenger.of(context).showSnackBar(
                        SnackBar(content: Text(tr('اتنسخت'))));
                  },
            icon: Icon(Icons.copy),
          ),
          IconButton(
              onPressed: _busy ? null : _run,
              icon: Icon(Icons.refresh)),
        ],
      ),
      body: results == null
          ? Center(child: CircularProgressIndicator())
          : ListView(
              padding: EdgeInsets.all(12),
              children: [
                Card(
                  color: Theme.of(context).colorScheme.primaryContainer,
                  child: ListTile(
                    title: Text(found != null && found.isNotEmpty
                        ? tr('العداد: ${fmt(found.first.km, 1)} كم')
                        : tr('العربية ما ردتش بقراءة العداد بالطرق القياسية')),
                    subtitle: Text(
                        tr('قارن الرقم بعداد التابلوه. لو مفيش نتيجة، انسخ الردود وابعتها.')),
                  ),
                ),
                for (final r in results)
                  Card(
                    child: ListTile(
                      title: Text(r.label),
                      subtitle: Text(tr('${r.cmd}\n${r.raw.isEmpty ? '(فاضي)' : r.raw}'),
                          textDirection: TextDirection.ltr),
                      isThreeLine: true,
                      trailing: Text(
                          r.km == null ? tr('مش مدعوم') : tr('${fmt(r.km, 1)} كم'),
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                  ),
              ],
            ),
    );
  }
}
