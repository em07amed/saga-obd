import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../obd/bt_channel.dart';
import '../settings.dart';
import 'vehicle_editor.dart';
import 'widgets.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = App.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => ListView(
        children: [
          const _Header('المظهر'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(
                    value: 'system',
                    label: Text('تلقائي'),
                    icon: Icon(Icons.brightness_auto)),
                ButtonSegment(
                    value: 'light',
                    label: Text('فاتح'),
                    icon: Icon(Icons.light_mode)),
                ButtonSegment(
                    value: 'dark',
                    label: Text('داكن'),
                    icon: Icon(Icons.dark_mode)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (sel) => s.setThemeMode(sel.first),
            ),
          ),
          const _Header('جهاز الـ OBD'),
          ListTile(
            leading: const Icon(Icons.bluetooth_searching),
            title: Text(s.deviceName ?? 'لم يتم الاختيار'),
            subtitle: Text(s.deviceAddress ??
                'اعمل Pair للجهاز من إعدادات Bluetooth في الموبايل الأول'),
            trailing: const Icon(Icons.chevron_left),
            onTap: () => _pickDevice(context),
          ),
          SwitchListTile(
            title: const Text('اتصال تلقائي عند فتح التطبيق'),
            value: s.autoConnect,
            onChanged: s.setAutoConnect,
          ),
          const _Header('العربيات'),
          for (final v in s.vehicles)
            ListTile(
              leading: Icon(
                v.id == s.vehicle.id
                    ? Icons.radio_button_checked
                    : Icons.radio_button_unchecked,
                color: v.id == s.vehicle.id
                    ? Theme.of(context).colorScheme.primary
                    : null,
              ),
              title: Text(v.name),
              subtitle: v.subtitle.isEmpty ? null : Text(v.subtitle),
              trailing: IconButton(
                tooltip: 'تعديل',
                icon: const Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => VehicleEditor(vehicle: v))),
              ),
              onTap: () => s.setActiveVehicle(v.id!),
            ),
          ListTile(
            leading: const Icon(Icons.add),
            title: const Text('إضافة عربية'),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => const VehicleEditor())),
          ),
          _Header('بيانات ${s.vehicle.name}'),
          _NumberTile(
              keyName: 'tankLiters',
              label: 'سعة التانك',
              unit: 'لتر',
              value: s.tankLiters),
          _NumberTile(
              keyName: 'displacementL',
              label: 'سعة الموتور',
              unit: 'لتر',
              value: s.displacementL),
          _NumberTile(
              keyName: 'volumetricEff',
              label: 'الكفاءة الحجمية (VE)',
              unit: '',
              value: s.volumetricEff,
              help: 'بتستخدم بس لو العربية مفيهاش حساس MAF. عايرها من تفويلة حقيقية.'),
          ListTile(
            leading: const Icon(Icons.science_outlined),
            title: const Text('معايرة الاستهلاك من تفويلة'),
            subtitle: const Text('قارن اللترات اللي فوّلتها باللي التطبيق حسبه'),
            onTap: () => _calibrate(context),
          ),
          _NumberTile(
              keyName: 'defaultL100',
              label: 'متوسط استهلاك افتراضي (لحساب المسافة المتبقية)',
              unit: 'ل/100كم',
              value: s.defaultL100),
          const _Header('التكلفة'),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: [
                for (final g in AppSettings.gradePrices.keys)
                  ButtonSegment(value: g, label: Text('بنزين $g')),
              ],
              selected: {s.fuelGrade},
              onSelectionChanged: (sel) => s.setFuelGrade(sel.first),
            ),
          ),
          _NumberTile(
              keyName: 'fuelPrice',
              label: 'سعر لتر البنزين',
              unit: 'ج.م',
              value: s.fuelPrice,
              help: 'السعر الرسمي بيتحط تلقائي لما تختار النوع. لو اتغير عدّله من هنا؛ كل رحلة بتتسجل بالسعر وقت بدايتها.'),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  Future<void> _pickDevice(BuildContext context) async {
    List<BtDevice> devices;
    try {
      devices = await App.obd.bt.bondedDevices();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text('مش قادر أقرا الأجهزة: $e')));
      }
      return;
    }
    if (!context.mounted) return;
    final picked = await showModalBottomSheet<BtDevice>(
      context: context,
      builder: (ctx) => SafeArea(
        child: ListView(
          shrinkWrap: true,
          children: [
            const ListTile(
                title: Text('الأجهزة المقترنة'),
                subtitle: Text('جهاز ELM327 غالباً اسمه OBDII أو V-LINK')),
            if (devices.isEmpty)
              const ListTile(title: Text('مفيش أجهزة. اعمل Pair الأول.')),
            for (final d in devices)
              ListTile(
                leading: const Icon(Icons.bluetooth),
                title: Text(d.name),
                subtitle: Text(d.address),
                onTap: () => Navigator.pop(ctx, d),
              ),
          ],
        ),
      ),
    );
    if (picked != null) {
      await App.settings.setDevice(picked.name, picked.address);
    }
  }

  Future<void> _calibrate(BuildContext context) async {
    final actual = TextEditingController();
    final computed = TextEditingController();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('معايرة الـ VE'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'فوّل التانك فُل، امشي مشوار طويل، وفوّل فُل تاني. '
                'اكتب اللترات الحقيقية من البنزينة، وإجمالي لترات الرحلات '
                'اللي بين التفويلتين من التطبيق.'),
            TextField(
              controller: actual,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'لترات البنزينة'),
            ),
            TextField(
              controller: computed,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              decoration: const InputDecoration(labelText: 'لترات التطبيق'),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('احسب')),
        ],
      ),
    );
    if (ok != true) return;
    final a = double.tryParse(actual.text);
    final c = double.tryParse(computed.text);
    if (a == null || c == null || a <= 0 || c <= 0) return;
    final s = App.settings;
    final newVe = (s.volumetricEff * a / c).clamp(0.4, 1.2);
    await s.setNumber('volumetricEff', newVe);
    if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text('الـ VE الجديدة: ${newVe.toStringAsFixed(3)}')));
    }
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
        child: Text(text,
            style: TextStyle(
                color: Theme.of(context).colorScheme.primary,
                fontWeight: FontWeight.bold)),
      );
}

class _NumberTile extends StatelessWidget {
  final String keyName;
  final String label;
  final String unit;
  final double value;
  final String? help;

  const _NumberTile({
    required this.keyName,
    required this.label,
    required this.unit,
    required this.value,
    this.help,
  });

  @override
  Widget build(BuildContext context) {
    return ListTile(
      title: Text(label),
      subtitle: help == null ? null : Text(help!),
      trailing: Text('${fmt(value, value % 1 == 0 ? 0 : 3)} $unit',
          style: Theme.of(context).textTheme.titleMedium),
      onTap: () async {
        final c = TextEditingController(text: value.toString());
        final v = await showDialog<double>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: Text(label),
            content: TextField(
              controller: c,
              autofocus: true,
              keyboardType:
                  const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: InputDecoration(suffixText: unit),
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
        if (v != null && v >= 0) await App.settings.setNumber(keyName, v);
      },
    );
  }
}
