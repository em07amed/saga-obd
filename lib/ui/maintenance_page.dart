import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../main.dart';
import '../maintenance/maintenance.dart';
import 'widgets.dart';
import '../l10n.dart';

DateFormat get _day => DateFormat('d MMM yyyy', Lang.code);

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final m = App.maintenance;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: Icon(Icons.add),
        label: Text(tr('صيانة جديدة')),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([m, App.obd]),
        builder: (context, _) {
          final due = m.due;
          return ListView(
            padding: EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              _OdometerCard(m: m),
              if (due.isNotEmpty) ...[
                _Section(tr('المواعيد الجاية')),
                for (final d in due) _DueTile(d: d),
              ],
              _Section(tr('السجل (${m.entries.length}) • '
                  'إجمالي ${fmt(m.totalCost)} ج.م')),
              if (m.entries.isEmpty)
                Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text(tr('لسه مفيش صيانات متسجلة'))),
                ),
              for (final e in m.entries)
                Card(
                  child: ListTile(
                    leading: Icon(Icons.build_circle_outlined),
                    title: Text(tr(e.type)),
                    subtitle: Text([
                      _day.format(e.date),
                      if (e.km != null) tr('${fmt(e.km)} كم'),
                      if (e.notes != null && e.notes!.isNotEmpty) e.notes!,
                    ].join(' • ')),
                    trailing: Text(tr('${fmt(e.cost)} ج.م'),
                        style: Theme.of(context).textTheme.titleSmall),
                    onTap: () => _openEditor(context, e),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static void _openEditor(BuildContext context, MaintenanceEntry? e) {
    Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => MaintenanceEditor(entry: e)));
  }
}

class _Section extends StatelessWidget {
  final String text;
  const _Section(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );
}

class _OdometerCard extends StatelessWidget {
  final MaintenanceService m;
  _OdometerCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final km = m.odometerKm;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tr('العداد'), style: Theme.of(context).textTheme.labelLarge),
                  Text(km == null ? '—' : tr('${fmt(km)} كم'),
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(
                    km == null
                        ? tr('اكتب رقم عداد التابلوه مرة واحدة')
                        : switch (m.odometerSource) {
                            'obd' => tr('من كمبيوتر العربية'),
                            'ecu' => tr('من كمبيوتر العربية (بعد المعايرة) • لحظي'),
                            'ecu_raw' =>
                              tr('تقريبي من كمبيوتر العربية • دوس تحديث واكتب رقم التابلوه للدقة'),
                            _ => tr('تقديري: آخر قراءة + الرحلات المسجلة'),
                          },
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (!m.odometerFromObd)
              FilledButton.tonal(
                onPressed: () => _editOdometer(context),
                child: Text(km == null ? tr('إدخال') : tr('تحديث')),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _editOdometer(BuildContext context) async {
    final c = TextEditingController(
        text: m.odometerKm == null ? '' : m.odometerKm!.round().toString());
    final v = await showDialog<double>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('رقم العداد من التابلوه')),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: InputDecoration(suffixText: tr('كم')),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: Text(tr('إلغاء'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)),
              child: Text(tr('حفظ'))),
        ],
      ),
    );
    if (v != null && v > 0) await App.maintenance.setDashboardOdometer(v);
  }
}

class _DueTile extends StatelessWidget {
  final DueItem d;
  _DueTile({required this.d});

  @override
  Widget build(BuildContext context) {
    final color = d.overdue
        ? AppColors.danger(context)
        : d.soon
            ? AppColors.warning(context)
            : AppColors.ok(context);
    final parts = <String>[
      if (d.kmLeft != null)
        d.kmLeft! <= 0
            ? tr('متأخر ${fmt(-d.kmLeft!)} كم')
            : tr('فاضل ${fmt(d.kmLeft)} كم'),
      if (d.daysLeft != null)
        d.daysLeft! <= 0
            ? tr('متأخر ${-d.daysLeft!} يوم')
            : tr('فاضل ${d.daysLeft} يوم'),
    ];
    return Card(
      child: ListTile(
        leading: Icon(
            d.overdue ? Icons.error_outline : Icons.schedule,
            color: color),
        title: Text(tr(d.entry.type)),
        subtitle: Text(parts.join(' • ')),
        trailing: Text(
          [
            if (d.entry.nextKm != null) tr('${fmt(d.entry.nextKm)} كم'),
            if (d.entry.nextDate != null) _day.format(d.entry.nextDate!),
          ].join('\n'),
          textAlign: TextAlign.end,
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ),
    );
  }
}

class MaintenanceEditor extends StatefulWidget {
  final MaintenanceEntry? entry;
  const MaintenanceEditor({super.key, this.entry});

  @override
  State<MaintenanceEditor> createState() => _MaintenanceEditorState();
}

class _MaintenanceEditorState extends State<MaintenanceEditor> {
  late String _type;
  late final TextEditingController _customType;
  late DateTime _date;
  late final TextEditingController _km;
  late final TextEditingController _cost;
  late final TextEditingController _notes;
  late final TextEditingController _everyKm;
  DateTime? _nextDate;

  @override
  void initState() {
    super.initState();
    final e = widget.entry;
    final isKnown = e == null || maintenanceTypes.contains(e.type);
    _type = e == null ? maintenanceTypes.first : (isKnown ? e.type : 'أخرى');
    _customType = TextEditingController(text: isKnown ? '' : e.type);
    _date = e?.date ?? DateTime.now();
    final odo = App.maintenance.odometerKm;
    _km = TextEditingController(
        text: (e?.km ?? odo)?.round().toString() ?? '');
    _cost = TextEditingController(
        text: e == null || e.cost == 0 ? '' : e.cost.toStringAsFixed(0));
    _notes = TextEditingController(text: e?.notes ?? '');
    _everyKm = TextEditingController(
        text: e?.nextKm != null && e?.km != null
            ? (e!.nextKm! - e.km!).round().toString()
            : '');
    _nextDate = e?.nextDate;
  }

  @override
  void dispose() {
    for (final c in [_customType, _km, _cost, _notes, _everyKm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickDate({required bool next}) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: next ? (_nextDate ?? now.add(Duration(days: 180))) : _date,
      firstDate: DateTime(now.year - 20),
      lastDate: DateTime(now.year + 10),
    );
    if (picked != null) {
      setState(() {
        if (next) {
          _nextDate = picked;
        } else {
          _date = picked;
        }
      });
    }
  }

  Future<void> _save() async {
    final type = _type == 'أخرى' && _customType.text.trim().isNotEmpty
        ? _customType.text.trim()
        : _type;
    final km = double.tryParse(_km.text);
    final every = double.tryParse(_everyKm.text);
    await App.maintenance.save(MaintenanceEntry(
      id: widget.entry?.id,
      date: _date,
      km: km,
      type: type,
      cost: double.tryParse(_cost.text) ?? 0,
      notes: _notes.text.trim().isEmpty ? null : _notes.text.trim(),
      nextKm: km != null && every != null && every > 0 ? km + every : null,
      nextDate: _nextDate,
    ));
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذف الصيانة دي؟')),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('حذف'))),
        ],
      ),
    );
    if (ok == true) {
      await App.maintenance.delete(widget.entry!.id!);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.entry == null ? tr('صيانة جديدة') : tr('تعديل الصيانة')),
        actions: [
          if (widget.entry != null)
            IconButton(
                tooltip: tr('حذف'),
                onPressed: _delete,
                icon: Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: InputDecoration(labelText: tr('النوع')),
            items: [
              for (final t in maintenanceTypes)
                DropdownMenuItem(value: t, child: Text(tr(t))),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          if (_type == 'أخرى')
            TextField(
              controller: _customType,
              decoration: InputDecoration(labelText: tr('اكتب النوع')),
            ),
          SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event),
            title: Text(tr('التاريخ')),
            trailing: Text(_day.format(_date)),
            onTap: () => _pickDate(next: false),
          ),
          TextField(
            controller: _km,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: InputDecoration(
                labelText: tr('العداد وقت الصيانة'), suffixText: tr('كم')),
          ),
          TextField(
            controller: _cost,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration:
                InputDecoration(labelText: tr('التكلفة'), suffixText: tr('ج.م')),
          ),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: InputDecoration(
                labelText: tr('ملاحظات'), hintText: tr('نوع الزيت، المركز، القطعة…')),
          ),
          SizedBox(height: 16),
          Text(tr('الميعاد الجاي (اختياري)'),
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold)),
          TextField(
            controller: _everyKm,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: InputDecoration(
              labelText: tr('بعد كام كيلو'),
              suffixText: tr('كم'),
              helperText: tr('حسب كتيب الصيانة أو كلام الميكانيكي'),
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: Icon(Icons.event_repeat),
            title: Text(tr('أو في تاريخ')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_nextDate == null ? '—' : _day.format(_nextDate!)),
              if (_nextDate != null)
                IconButton(
                    tooltip: tr('إلغاء التاريخ'),
                    onPressed: () => setState(() => _nextDate = null),
                    icon: Icon(Icons.close)),
            ]),
            onTap: () => _pickDate(next: true),
          ),
          SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: Icon(Icons.save),
            label: Text(tr('حفظ')),
          ),
        ],
      ),
    );
  }
}
