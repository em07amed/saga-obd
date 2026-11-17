import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../main.dart';
import '../maintenance/maintenance.dart';
import 'widgets.dart';

final _day = DateFormat('d MMM yyyy', 'ar');

class MaintenancePage extends StatelessWidget {
  const MaintenancePage({super.key});

  @override
  Widget build(BuildContext context) {
    final m = App.maintenance;
    return Scaffold(
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openEditor(context, null),
        icon: const Icon(Icons.add),
        label: const Text('صيانة جديدة'),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([m, App.obd]),
        builder: (context, _) {
          final due = m.due;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              _OdometerCard(m: m),
              if (due.isNotEmpty) ...[
                const _Section('المواعيد الجاية'),
                for (final d in due) _DueTile(d: d),
              ],
              _Section('السجل (${m.entries.length}) • '
                  'إجمالي ${fmt(m.totalCost)} ج.م'),
              if (m.entries.isEmpty)
                const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('لسه مفيش صيانات متسجلة')),
                ),
              for (final e in m.entries)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.build_circle_outlined),
                    title: Text(e.type),
                    subtitle: Text([
                      _day.format(e.date),
                      if (e.km != null) '${fmt(e.km)} كم',
                      if (e.notes != null && e.notes!.isNotEmpty) e.notes!,
                    ].join(' • ')),
                    trailing: Text('${fmt(e.cost)} ج.م',
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
        padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );
}

class _OdometerCard extends StatelessWidget {
  final MaintenanceService m;
  const _OdometerCard({required this.m});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final km = m.odometerKm;
    return Card(
      color: scheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('العداد', style: Theme.of(context).textTheme.labelLarge),
                  Text(km == null ? '—' : '${fmt(km)} كم',
                      style: Theme.of(context)
                          .textTheme
                          .headlineMedium
                          ?.copyWith(fontWeight: FontWeight.bold)),
                  Text(
                    km == null
                        ? 'اكتب رقم عداد التابلوه مرة واحدة'
                        : switch (m.odometerSource) {
                            'obd' => 'من كمبيوتر العربية',
                            'ecu' => 'من كمبيوتر العربية (بعد المعايرة) • لحظي',
                            'ecu_raw' =>
                              'تقريبي من كمبيوتر العربية • دوس تحديث واكتب رقم التابلوه للدقة',
                            _ => 'تقديري: آخر قراءة + الرحلات المسجلة',
                          },
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
            ),
            if (!m.odometerFromObd)
              FilledButton.tonal(
                onPressed: () => _editOdometer(context),
                child: Text(km == null ? 'إدخال' : 'تحديث'),
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
        title: const Text('رقم العداد من التابلوه'),
        content: TextField(
          controller: c,
          autofocus: true,
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly],
          decoration: const InputDecoration(suffixText: 'كم'),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, double.tryParse(c.text)),
              child: const Text('حفظ')),
        ],
      ),
    );
    if (v != null && v > 0) await App.maintenance.setDashboardOdometer(v);
  }
}

class _DueTile extends StatelessWidget {
  final DueItem d;
  const _DueTile({required this.d});

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
            ? 'متأخر ${fmt(-d.kmLeft!)} كم'
            : 'فاضل ${fmt(d.kmLeft)} كم',
      if (d.daysLeft != null)
        d.daysLeft! <= 0
            ? 'متأخر ${-d.daysLeft!} يوم'
            : 'فاضل ${d.daysLeft} يوم',
    ];
    return Card(
      child: ListTile(
        leading: Icon(
            d.overdue ? Icons.error_outline : Icons.schedule,
            color: color),
        title: Text(d.entry.type),
        subtitle: Text(parts.join(' • ')),
        trailing: Text(
          [
            if (d.entry.nextKm != null) '${fmt(d.entry.nextKm)} كم',
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
      initialDate: next ? (_nextDate ?? now.add(const Duration(days: 180))) : _date,
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
        title: const Text('حذف الصيانة دي؟'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف')),
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
        title: Text(widget.entry == null ? 'صيانة جديدة' : 'تعديل الصيانة'),
        actions: [
          if (widget.entry != null)
            IconButton(
                tooltip: 'حذف',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          DropdownButtonFormField<String>(
            initialValue: _type,
            decoration: const InputDecoration(labelText: 'النوع'),
            items: [
              for (final t in maintenanceTypes)
                DropdownMenuItem(value: t, child: Text(t)),
            ],
            onChanged: (v) => setState(() => _type = v ?? _type),
          ),
          if (_type == 'أخرى')
            TextField(
              controller: _customType,
              decoration: const InputDecoration(labelText: 'اكتب النوع'),
            ),
          const SizedBox(height: 8),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event),
            title: const Text('التاريخ'),
            trailing: Text(_day.format(_date)),
            onTap: () => _pickDate(next: false),
          ),
          TextField(
            controller: _km,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: const InputDecoration(
                labelText: 'العداد وقت الصيانة', suffixText: 'كم'),
          ),
          TextField(
            controller: _cost,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration:
                const InputDecoration(labelText: 'التكلفة', suffixText: 'ج.م'),
          ),
          TextField(
            controller: _notes,
            maxLines: 3,
            decoration: const InputDecoration(
                labelText: 'ملاحظات', hintText: 'نوع الزيت، المركز، القطعة…'),
          ),
          const SizedBox(height: 16),
          Text('الميعاد الجاي (اختياري)',
              style: TextStyle(
                  color: Theme.of(context).colorScheme.primary,
                  fontWeight: FontWeight.bold)),
          TextField(
            controller: _everyKm,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: const InputDecoration(
              labelText: 'بعد كام كيلو',
              suffixText: 'كم',
              helperText: 'حسب كتيب الصيانة أو كلام الميكانيكي',
            ),
          ),
          ListTile(
            contentPadding: EdgeInsets.zero,
            leading: const Icon(Icons.event_repeat),
            title: const Text('أو في تاريخ'),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              Text(_nextDate == null ? '—' : _day.format(_nextDate!)),
              if (_nextDate != null)
                IconButton(
                    tooltip: 'إلغاء التاريخ',
                    onPressed: () => setState(() => _nextDate = null),
                    icon: const Icon(Icons.close)),
            ]),
            onTap: () => _pickDate(next: true),
          ),
          const SizedBox(height: 24),
          FilledButton.icon(
            onPressed: _save,
            icon: const Icon(Icons.save),
            label: const Text('حفظ'),
          ),
        ],
      ),
    );
  }
}
