import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../settings.dart';
import '../vehicle.dart';

/// Add or edit a vehicle. Any make/model works: the app reads standard OBD2,
/// and only needs tank size and engine size for fuel maths.
class VehicleEditor extends StatefulWidget {
  final Vehicle? vehicle;
  const VehicleEditor({super.key, this.vehicle});

  @override
  State<VehicleEditor> createState() => _VehicleEditorState();
}

class _VehicleEditorState extends State<VehicleEditor> {
  late final TextEditingController _name;
  late final TextEditingController _make;
  late final TextEditingController _model;
  late final TextEditingController _year;
  late final TextEditingController _tank;
  late final TextEditingController _engine;
  late String _grade;

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _name = TextEditingController(text: v?.name ?? '');
    _make = TextEditingController(text: v?.make ?? '');
    _model = TextEditingController(text: v?.model ?? '');
    _year = TextEditingController(text: v?.year?.toString() ?? '');
    _tank = TextEditingController(text: _num(v?.tankL));
    _engine = TextEditingController(text: _num(v?.displacementL));
    _grade = v?.fuelGrade ?? '92';
  }

  static String _num(double? x) =>
      x == null ? '' : (x % 1 == 0 ? x.toStringAsFixed(0) : x.toString());

  @override
  void dispose() {
    for (final c in [_name, _make, _model, _year, _tank, _engine]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _save() async {
    final tank = double.tryParse(_tank.text);
    final engine = double.tryParse(_engine.text);
    if (tank == null || tank <= 0 || engine == null || engine <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('اكتب سعة التانك وسعة الموتور (من كتيب العربية)')));
      return;
    }
    final make = _make.text.trim();
    final model = _model.text.trim();
    final name = _name.text.trim().isNotEmpty
        ? _name.text.trim()
        : [make, model].where((x) => x.isNotEmpty).join(' ');
    final s = App.settings;
    final old = widget.vehicle;
    final v = Vehicle(
      id: old?.id,
      name: name.isEmpty ? 'عربيتي' : name,
      make: make,
      model: model,
      year: int.tryParse(_year.text),
      tankL: tank,
      displacementL: engine,
      ve: old?.ve ?? 0.80,
      fuelGrade: _grade,
      fuelPrice: old != null && old.fuelGrade == _grade
          ? old.fuelPrice
          : AppSettings.gradePrices[_grade] ?? 0,
      defaultL100: old?.defaultL100 ?? 7.0,
      odoBaseKm: old?.odoBaseKm,
      odoBaseAt: old?.odoBaseAt,
    );
    if (old == null) {
      await s.addVehicle(v);
    } else {
      await s.updateVehicle(v);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final v = widget.vehicle!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('حذف ${v.name}؟'),
        content: const Text('هيتمسح معاها كل الرحلات وسجل الصيانة بتاعها.'),
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
      await App.settings.deleteVehicle(v.id!);
      if (mounted) Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final digits = [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))];
    final canDelete =
        widget.vehicle != null && App.settings.vehicles.length > 1;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.vehicle == null ? 'عربية جديدة' : 'تعديل العربية'),
        actions: [
          if (canDelete)
            IconButton(
                tooltip: 'حذف',
                onPressed: _delete,
                icon: const Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          TextField(
            controller: _make,
            decoration: const InputDecoration(
                labelText: 'الماركة', hintText: 'مثلاً: Hyundai، Toyota'),
          ),
          TextField(
            controller: _model,
            decoration: const InputDecoration(
                labelText: 'الموديل', hintText: 'مثلاً: Elantra، Corolla'),
          ),
          TextField(
            controller: _year,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: const InputDecoration(labelText: 'سنة الصنع'),
          ),
          TextField(
            controller: _name,
            decoration: const InputDecoration(
                labelText: 'اسم تعرفها بيه (اختياري)',
                hintText: 'مثلاً: عربية البيت'),
          ),
          const SizedBox(height: 16),
          TextField(
            controller: _tank,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: const InputDecoration(
                labelText: 'سعة التانك', suffixText: 'لتر'),
          ),
          TextField(
            controller: _engine,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: const InputDecoration(
              labelText: 'سعة الموتور',
              suffixText: 'لتر',
              helperText: 'مثلاً 1.6 لموتور 1600 سي سي',
            ),
          ),
          const SizedBox(height: 16),
          const Text('نوع البنزين'),
          const SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              for (final g in AppSettings.gradePrices.keys)
                ButtonSegment(value: g, label: Text('بنزين $g')),
            ],
            selected: {_grade},
            onSelectionChanged: (sel) => setState(() => _grade = sel.first),
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
