import 'dart:async';

import 'package:flutter/material.dart';
import 'package:permission_handler/permission_handler.dart';

import '../l10n.dart';
import '../main.dart';

/// Android Auto on the car's own screen (CarbitLink / QDLink head units),
/// using the AA Bridge engine over a USB cable.
class CarScreenPage extends StatefulWidget {
  const CarScreenPage({super.key});

  @override
  State<CarScreenPage> createState() => _CarScreenPageState();
}

class _CarScreenPageState extends State<CarScreenPage> {
  Map<String, dynamic> _st = const {};
  Timer? _t;

  @override
  void initState() {
    super.initState();
    [Permission.notification, Permission.microphone, Permission.locationWhenInUse]
        .request();
    _refresh();
    _t = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    final m = await App.obd.bt.aaStatus().catchError((_) => <String, dynamic>{});
    if (mounted) setState(() => _st = m);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final installed = _st['aaInstalled'] == true;
    final server = _st['server'] == true;
    final phase = '${_st['phase'] ?? 'DISCONNECTED'}';
    final onCar = phase == 'ATTACHED' || phase == 'STREAMING';
    final bt = App.obd.bt;

    Widget step(int n, bool done, String title, String body,
            {Widget? action}) =>
        Card(
          child: ListTile(
            leading: CircleAvatar(
              backgroundColor: done ? Colors.green : scheme.surfaceContainerHighest,
              child: done
                  ? const Icon(Icons.check, color: Colors.white)
                  : Text('$n'),
            ),
            title: Text(title, style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text(body),
            trailing: action,
          ),
        );

    return Scaffold(
      appBar: AppBar(title: Text(tr('شاشة العربية'))),
      body: ListView(padding: const EdgeInsets.all(12), children: [
        Card(
          color: onCar
              ? Colors.green.withValues(alpha: 0.15)
              : scheme.surfaceContainerHigh,
          child: ListTile(
            leading: Icon(onCar ? Icons.cast_connected : Icons.cast,
                size: 36, color: onCar ? Colors.green : null),
            title: Text(
                onCar
                    ? tr('متوصّل بشاشة العربية')
                    : server
                        ? tr('جاهز. وصّل الكابل في العربية')
                        : tr('محتاج تشغّل سيرفر Android Auto'),
                style: const TextStyle(fontWeight: FontWeight.bold)),
            subtitle: Text([
              if (_st['car'] != null) '${_st['car']}',
              phase,
              if (_st['error'] != null) '${_st['error']}',
            ].join(' • ')),
            trailing: onCar
                ? TextButton(onPressed: bt.aaStop, child: Text(tr('افصل')))
                : null,
          ),
        ),
        const SizedBox(height: 8),
        step(1, installed, tr('Android Auto متسطّب'),
            tr('لو مش موجود نزّله من Play Store')),
        step(2, server, tr('وضع المطوّر وسيرفر الشاشة'),
            tr('افتح إعدادات Android Auto ← دوس على Version 10 مرات ← ⋮ ← Start head unit server. بيقف كل ما الموبايل يعمل ريستارت.'),
            action: IconButton.filledTonal(
              tooltip: tr('افتح إعدادات Android Auto'),
              icon: const Icon(Icons.open_in_new),
              onPressed: () => bt.aaOpenSettings(),
            )),
        step(3, onCar, tr('وصّل الكابل'),
            tr('كابل بيانات في USB العربية، والشاشة على صفحة CarbitLink. لما يسأل يفتح بأنهي تطبيق اختار Car OBD ثم Always.')),
        step(4, false, tr('Car OBD على الشاشة'),
            tr('في إعدادات المطوّر بتاعة Android Auto فعّل Unknown sources، هتلاقي Car OBD في قايمة التطبيقات على شاشة العربية.')),
        const SizedBox(height: 12),
        Text(
          tr('محرّك التوصيل مأخوذ من مشروع AA Bridge مفتوح المصدر (Ali Morgan، رخصة GPL-3.0). وضع المطوّر في Android Auto مش رسمي، وتحديث من جوجل ممكن يوقفه.'),
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12),
        ),
      ]),
    );
  }
}
