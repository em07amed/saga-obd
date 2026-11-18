import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../main.dart';
import '../obd/bt_channel.dart';
import '../settings.dart';
import 'vehicle_avatar.dart';
import 'vehicle_editor.dart';
import 'widgets.dart';
import '../l10n.dart';

class SettingsPage extends StatelessWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context) {
    final s = App.settings;
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) => ListView(
        children: [
          _Header(tr('المظهر')),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: 'sport',
                    label: Text(tr('رياضي')),
                    icon: Icon(Icons.sports_score)),
                ButtonSegment(
                    value: 'system',
                    label: Text(tr('تلقائي')),
                    icon: Icon(Icons.brightness_auto)),
                ButtonSegment(
                    value: 'light',
                    label: Text(tr('فاتح')),
                    icon: Icon(Icons.light_mode)),
                ButtonSegment(
                    value: 'dark',
                    label: Text(tr('داكن')),
                    icon: Icon(Icons.dark_mode)),
              ],
              selected: {s.themeMode},
              onSelectionChanged: (sel) => s.setThemeMode(sel.first),
            ),
          ),
          SwitchListTile(
            secondary: Icon(Icons.notifications_active_outlined),
            title: Text(tr('تنبيهات وإنت سايق')),
            subtitle: Text(tr('الحرارة، الشحن، الأعطال، مواعيد الصيانة')),
            value: s.alertsOn,
            onChanged: s.setAlerts,
          ),
          _Header(tr('تنبيه السرعة')),
          ListTile(
            leading: Icon(Icons.speed),
            title: Text(tr('الحد الأقصى')),
            subtitle: Text(tr('غيّره بسرعة من وضع القيادة')),
            trailing: Row(mainAxisSize: MainAxisSize.min, children: [
              IconButton(
                tooltip: '-10',
                onPressed: () => s.setSpeedLimit(s.speedLimit - 10),
                icon: Icon(Icons.remove_circle_outline),
              ),
              Text('${s.speedLimit.round()}',
                  textDirection: TextDirection.ltr,
                  style: Theme.of(context).textTheme.titleLarge),
              IconButton(
                tooltip: '+10',
                onPressed: () => s.setSpeedLimit(s.speedLimit + 10),
                icon: Icon(Icons.add_circle_outline),
              ),
            ]),
          ),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              showSelectedIcon: false,
              segments: [
                ButtonSegment(
                    value: 'voice',
                    label: Text(tr('رسالة صوتية')),
                    icon: Icon(Icons.record_voice_over)),
                ButtonSegment(
                    value: 'beep',
                    label: Text(tr('صفارة بس')),
                    icon: Icon(Icons.notifications_active)),
                ButtonSegment(
                    value: 'off',
                    label: Text(tr('مقفول')),
                    icon: Icon(Icons.notifications_off)),
              ],
              selected: {s.speedAlertMode},
              onSelectionChanged: (sel) => s.setSpeedAlertMode(sel.first),
            ),
          ),
          SwitchListTile(
            secondary: Icon(Icons.add_road),
            title: Text(tr('استخدم حد الطريق تلقائياً')),
            subtitle: Text(tr('من خرائط OpenStreetMap. لو الطريق مش متسجل حده، بيستخدم الحد اليدوي.')),
            value: s.autoRoadLimit,
            onChanged: s.setAutoRoadLimit,
          ),
          SwitchListTile(
            secondary: Icon(Icons.camera_alt_outlined),
            title: Text(tr('تنبيه الرادارات')),
            subtitle: Text(tr('قبل الرادار بـ 600 متر، والبيانات ممكن تكون ناقصة')),
            value: s.cameraAlerts,
            onChanged: s.setCameraAlerts,
          ),
          ListTile(
            leading: Icon(Icons.play_circle_outline),
            title: Text(tr('جرّب تنبيه السرعة')),
            onTap: () => s.speedAlertMode == 'beep'
                ? App.obd.bt.beep().catchError((_) {})
                : App.obd.bt
                    .speak(
                        tr('انتبه. سرعتك ${(s.speedLimit + 12).round()}، والحد ${s.speedLimit.round()}.'),
                        Lang.code)
                    .catchError((_) {}),
          ),
          _Header(tr('تنبيهات العربية')),
          SwitchListTile(
            secondary: Icon(Icons.record_voice_over_outlined),
            title: Text(tr('اقرا التنبيه بصوت')),
            value: s.voiceAlerts,
            onChanged: s.alertsOn ? s.setVoiceAlerts : null,
          ),
          ListTile(
            leading: Icon(Icons.volume_up_outlined),
            title: Text(tr('جرّب التنبيه الصوتي')),
            onTap: () => App.obd.bt
                .speak(tr('تحذير. حرارة الموتور وصلت ${s.coolantAlert.round()} درجة. اركن على جنب وطفي التكييف.'),
                    Lang.code)
                .catchError((_) {}),
          ),
          ListTile(
            leading: Icon(Icons.thermostat),
            title: Text(tr('تنبيه الحرارة عند')),
            subtitle: Text(tr('الطبيعي 105. خليه أقل عشان تجرّب التنبيه.')),
            trailing: DropdownButton<double>(
              value: s.coolantAlert,
              items: [
                for (final t in [80.0, 90.0, 100.0, 105.0, 110.0])
                  DropdownMenuItem(value: t, child: Text('${t.round()} °C')),
              ],
              onChanged: (v) => s.setCoolantAlert(v ?? 105),
            ),
          ),
          _Header(tr('اللغة')),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: 'ar', label: Text('العربية')),
                ButtonSegment(value: 'en', label: Text('English')),
              ],
              selected: {s.lang},
              onSelectionChanged: (sel) => s.setLang(sel.first),
            ),
          ),
          _Header(tr('جهاز الـ OBD')),
          ListTile(
            leading: Icon(Icons.bluetooth_searching),
            title: Text(s.deviceName ?? tr('لم يتم الاختيار')),
            subtitle: Text(s.deviceAddress ??
                tr('اعمل Pair للجهاز من إعدادات Bluetooth في الموبايل الأول')),
            trailing: Icon(Icons.chevron_left),
            onTap: () => _pickDevice(context),
          ),
          SwitchListTile(
            title: Text(tr('اتصال تلقائي عند فتح التطبيق')),
            value: s.autoConnect,
            onChanged: s.setAutoConnect,
          ),
          _Header(tr('العربيات')),
          for (final v in s.vehicles)
            ListTile(
              leading: Stack(clipBehavior: Clip.none, children: [
                VehicleAvatar(v),
                if (v.id == s.vehicle.id)
                  PositionedDirectional(
                    end: -4,
                    bottom: -4,
                    child: Icon(Icons.check_circle,
                        size: 20,
                        color: Theme.of(context).colorScheme.primary),
                  ),
              ]),
              title: Text(v.name),
              subtitle: v.subtitle.isEmpty ? null : Text(v.subtitle),
              trailing: IconButton(
                tooltip: tr('تعديل'),
                icon: Icon(Icons.edit_outlined),
                onPressed: () => Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => VehicleEditor(vehicle: v))),
              ),
              onTap: () => s.setActiveVehicle(v.id!),
            ),
          ListTile(
            leading: Icon(Icons.add),
            title: Text(tr('إضافة عربية')),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => VehicleEditor())),
          ),
          _Header(tr('بيانات ${s.vehicle.name}')),
          _NumberTile(
              keyName: 'tankLiters',
              label: tr('سعة التانك'),
              unit: tr('لتر'),
              value: s.tankLiters),
          _NumberTile(
              keyName: 'displacementL',
              label: tr('سعة الموتور'),
              unit: tr('لتر'),
              value: s.displacementL),
          _NumberTile(
              keyName: 'volumetricEff',
              label: tr('الكفاءة الحجمية (VE)'),
              unit: '',
              value: s.volumetricEff,
              help: tr('بتستخدم بس لو العربية مفيهاش حساس MAF. عايرها من تفويلة حقيقية.')),
          ListTile(
            leading: Icon(Icons.science_outlined),
            title: Text(tr('معايرة الاستهلاك من تفويلة')),
            subtitle: Text(tr('قارن اللترات اللي فوّلتها باللي التطبيق حسبه')),
            onTap: () => _calibrate(context),
          ),
          _NumberTile(
              keyName: 'defaultL100',
              label: tr('متوسط استهلاك افتراضي (لحساب المسافة المتبقية)'),
              unit: tr('ل/100كم'),
              value: s.defaultL100),
          _Header(tr('التكلفة')),
          Padding(
            padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: SegmentedButton<String>(
              segments: [
                for (final g in AppSettings.gradePrices.keys)
                  ButtonSegment(value: g, label: Text(tr('بنزين $g'))),
              ],
              selected: {s.fuelGrade},
              onSelectionChanged: (sel) => s.setFuelGrade(sel.first),
            ),
          ),
          _NumberTile(
              keyName: 'fuelPrice',
              label: tr('سعر لتر البنزين'),
              unit: tr('ج.م'),
              value: s.fuelPrice,
              help: tr('السعر الرسمي بيتحط تلقائي لما تختار النوع. لو اتغير عدّله من هنا؛ كل رحلة بتتسجل بالسعر وقت بدايتها.')),
          SizedBox(height: 24),
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
            SnackBar(content: Text(tr('مش قادر أقرا الأجهزة: $e'))));
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
            ListTile(
                title: Text(tr('الأجهزة المقترنة')),
                subtitle: Text(tr('جهاز ELM327 غالباً اسمه OBDII أو V-LINK'))),
            if (devices.isEmpty)
              ListTile(title: Text(tr('مفيش أجهزة. اعمل Pair الأول.'))),
            for (final d in devices)
              ListTile(
                leading: Icon(Icons.bluetooth),
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
        title: Text(tr('معايرة الـ VE')),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
                tr('فوّل التانك فُل، امشي مشوار طويل، وفوّل فُل تاني. '
                'اكتب اللترات الحقيقية من البنزينة، وإجمالي لترات الرحلات '
                'اللي بين التفويلتين من التطبيق.')),
            TextField(
              controller: actual,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('لترات البنزينة')),
            ),
            TextField(
              controller: computed,
              keyboardType: TextInputType.numberWithOptions(decimal: true),
              decoration: InputDecoration(labelText: tr('لترات التطبيق')),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: Text(tr('إلغاء'))),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              child: Text(tr('احسب'))),
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
          content: Text(tr('الـ VE الجديدة: ${newVe.toStringAsFixed(3)}'))));
    }
  }
}

class _Header extends StatelessWidget {
  final String text;
  const _Header(this.text);

  @override
  Widget build(BuildContext context) => Padding(
        padding: EdgeInsets.fromLTRB(16, 20, 16, 4),
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
                  TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
              ],
              decoration: InputDecoration(suffixText: unit),
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
        if (v != null && v >= 0) await App.settings.setNumber(keyName, v);
      },
    );
  }
}
