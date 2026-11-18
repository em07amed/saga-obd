import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../settings.dart';
import '../car_catalog.dart';
import '../vehicle.dart';
import 'brand_badge.dart';
import 'vehicle_avatar.dart';
import '../l10n.dart';

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
  String? _imagePath;

  Future<void> _pickImage() async {
    final p = await pickVehicleImage();
    if (p != null) setState(() => _imagePath = p);
  }

  @override
  void initState() {
    super.initState();
    final v = widget.vehicle;
    _name = TextEditingController(text: v?.name ?? '');
    _make = TextEditingController(text: v?.make ?? '')
      ..addListener(() => setState(() {})); // badge + model list follow make
    _model = TextEditingController(text: v?.model ?? '');
    _year = TextEditingController(text: v?.year?.toString() ?? '');
    _tank = TextEditingController(text: _num(v?.tankL));
    _engine = TextEditingController(text: _num(v?.displacementL));
    _grade = v?.fuelGrade ?? '92';
    _imagePath = App.settings.vehicleImage(v?.id);
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(tr('اكتب سعة التانك وسعة الموتور (من كتيب العربية)'))));
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
      name: name.isEmpty ? tr('عربيتي') : name,
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
    if (_imagePath != s.vehicleImage(v.id)) {
      await s.setVehicleImage(v.id!, _imagePath);
    }
    if (mounted) Navigator.pop(context);
  }

  Future<void> _delete() async {
    final v = widget.vehicle!;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(tr('حذف ${v.name}؟')),
        content: Text(tr('هيتمسح معاها كل الرحلات وسجل الصيانة بتاعها.')),
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
        title: Text(widget.vehicle == null ? tr('عربية جديدة') : tr('تعديل العربية')),
        actions: [
          if (canDelete)
            IconButton(
                tooltip: tr('حذف'),
                onPressed: _delete,
                icon: Icon(Icons.delete_outline)),
        ],
      ),
      body: ListView(
        padding: EdgeInsets.all(16),
        children: [
          Row(children: [
            GestureDetector(
              onTap: _pickImage,
              child: Stack(clipBehavior: Clip.none, children: [
                _imagePath != null
                    ? ClipOval(
                        child: Image.file(File(_imagePath!),
                            width: 56, height: 56, fit: BoxFit.cover))
                    : BrandBadge(_make.text, size: 56),
                PositionedDirectional(
                  end: -4,
                  bottom: -4,
                  child: CircleAvatar(
                    radius: 12,
                    child: Icon(Icons.photo_camera, size: 14),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: DropdownMenu<String>(
                controller: _make,
                expandedInsets: EdgeInsets.zero,
                enableFilter: true,
                requestFocusOnTap: true,
                menuHeight: 320,
                label: Text(tr('الماركة')),
                hintText: tr('اختار أو اكتب'),
                dropdownMenuEntries: [
                  for (final m in carCatalog.keys)
                    DropdownMenuEntry(
                      value: m,
                      label: m,
                      leadingIcon: BrandBadge(m, size: 28),
                    ),
                ],
                onSelected: (_) => setState(() => _model.clear()),
              ),
            ),
          ]),
          const SizedBox(height: 12),
          DropdownMenu<String>(
            key: ValueKey(_make.text), // refresh models when make changes
            controller: _model,
            expandedInsets: EdgeInsets.zero,
            enableFilter: true,
            requestFocusOnTap: true,
            menuHeight: 320,
            label: Text(tr('الموديل')),
            hintText: tr('اختار أو اكتب'),
            dropdownMenuEntries: [
              for (final m in carCatalog[_make.text.trim()] ?? const <String>[])
                DropdownMenuEntry(value: m, label: m),
            ],
          ),
          const SizedBox(height: 4),
          TextField(
            controller: _year,
            keyboardType: TextInputType.number,
            inputFormatters: [FilteringTextInputFormatter.digitsOnly],
            decoration: InputDecoration(labelText: tr('سنة الصنع')),
          ),
          TextField(
            controller: _name,
            decoration: InputDecoration(
                labelText: tr('اسم تعرفها بيه (اختياري)'),
                hintText: tr('مثلاً: عربية البيت')),
          ),
          SizedBox(height: 16),
          TextField(
            controller: _tank,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: InputDecoration(
                labelText: tr('سعة التانك'), suffixText: tr('لتر')),
          ),
          TextField(
            controller: _engine,
            keyboardType: TextInputType.number,
            inputFormatters: digits,
            decoration: InputDecoration(
              labelText: tr('سعة الموتور'),
              suffixText: tr('لتر'),
              helperText: tr('مثلاً 1.6 لموتور 1600 سي سي'),
            ),
          ),
          SizedBox(height: 16),
          Text(tr('نوع البنزين')),
          SizedBox(height: 8),
          SegmentedButton<String>(
            segments: [
              for (final g in AppSettings.gradePrices.keys)
                ButtonSegment(value: g, label: Text(tr('بنزين $g'))),
            ],
            selected: {_grade},
            onSelectionChanged: (sel) => setState(() => _grade = sel.first),
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
