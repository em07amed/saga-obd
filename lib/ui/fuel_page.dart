import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' show DateFormat;

import '../fuel/fuel_log.dart';
import '../l10n.dart';
import '../main.dart';
import 'widgets.dart';

DateFormat get _day => DateFormat('d MMM yyyy', Lang.code);

class FuelPage extends StatelessWidget {
  const FuelPage({super.key});

  @override
  Widget build(BuildContext context) {
    final f = App.fuel;
    final s = App.settings;
    return Scaffold(
      appBar: AppBar(title: Text(tr('سجل البنزين'))),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _add(context),
        icon: const Icon(Icons.local_gas_station),
        label: Text(tr('فوّلت')),
      ),
      body: ListenableBuilder(
        listenable: Listenable.merge([f, App.obd, App.trips]),
        builder: (context, _) {
          final litres = f.litresNow;
          final avg = f.realAvgL100 ?? App.trips.avgL100 ?? s.defaultL100;
          final ve = f.suggestedVe;
          return ListView(
            padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
            children: [
              Row(children: [
                Expanded(
                  child: StatTile(
                    label: tr('في التانك'),
                    icon: Icons.local_gas_station,
                    value: fmt(litres, 1),
                    unit: tr('لتر'),
                    sub: litres == null
                        ? tr('سجّل تفويلة فُل عشان يبدأ الحساب')
                        : f.fromSensor
                            ? tr('من حساس العربية')
                            : tr('تقديري من آخر تفويلة'),
                  ),
                ),
                Expanded(
                  child: StatTile(
                    label: tr('يكفي'),
                    icon: Icons.route,
                    value: litres == null ? '—' : fmt(litres / avg * 100),
                    unit: tr('كم'),
                    sub: tr('على ${fmt(avg, 1)} ل/100كم'),
                  ),
                ),
              ]),
              if (f.realAvgL100 != null)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.eco),
                    title: Text(tr('الاستهلاك الحقيقي')),
                    subtitle: Text(tr('من آخر تفويلات فُل')),
                    trailing: Text('${fmt(f.realAvgL100, 1)} L/100km',
                        textDirection: TextDirection.ltr,
                        style: Theme.of(context).textTheme.titleMedium),
                  ),
                ),
              if (ve != null && (ve - s.volumetricEff).abs() > 0.02)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.tune),
                    title: Text(tr('معايرة الاستهلاك')),
                    subtitle: Text(tr(
                        'التطبيق حاسب ${ve > s.volumetricEff ? 'أقل' : 'أكتر'} من البنزينة. الـ VE المقترحة ${ve.toStringAsFixed(3)}')),
                    trailing: FilledButton(
                      onPressed: () => s.setNumber('volumetricEff', ve),
                      child: Text(tr('طبّق')),
                    ),
                  ),
                ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 16, 4, 6),
                child: Text(tr('التفويلات'),
                    style: TextStyle(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.bold)),
              ),
              if (f.fills.isEmpty)
                Padding(
                  padding: const EdgeInsets.all(24),
                  child: Center(
                      child: Text(tr(
                          'لسه مفيش تفويلات. فوّل التانك فُل ودوس «فوّلت».'))),
                ),
              for (final x in f.fills)
                Card(
                  child: ListTile(
                    leading: Icon(x.full
                        ? Icons.local_gas_station
                        : Icons.local_gas_station_outlined),
                    title: Text(tr('${fmt(x.litres, 1)} لتر • ${fmt(x.cost)} ج.م')),
                    subtitle: Text(tr([
                      _day.format(x.date),
                      x.full ? 'فُل' : 'جزئي',
                      ..._statFor(f, x),
                    ].join(' • '))),
                    trailing: IconButton(
                      tooltip: tr('حذف'),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => f.delete(x.id!),
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  static List<String> _statFor(FuelLogService f, FillUp x) {
    for (final st in f.stats) {
      if (st.fill.id == x.id && st.l100 != null) {
        return ['${fmt(st.km)} كم', '${fmt(st.l100, 1)} ل/100كم'];
      }
    }
    return const [];
  }

  static Future<void> _add(BuildContext context) async {
    final litres = TextEditingController();
    final cost = TextEditingController();
    var full = true;
    final price = App.settings.fuelPrice;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: Text(tr('فوّلت')),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              TextField(
                controller: litres,
                autofocus: true,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                decoration: InputDecoration(
                    labelText: tr('اللترات'), suffixText: tr('لتر')),
                onChanged: (v) {
                  final l = double.tryParse(v);
                  if (l != null && price > 0) {
                    cost.text = (l * price).toStringAsFixed(0);
                  }
                },
              ),
              TextField(
                controller: cost,
                keyboardType:
                    const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))
                ],
                decoration: InputDecoration(
                    labelText: tr('المبلغ'), suffixText: tr('ج.م')),
              ),
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(tr('فوّلت التانك فُل')),
                value: full,
                onChanged: (v) => setState(() => full = v),
              ),
            ],
          ),
          actions: [
            TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: Text(tr('إلغاء'))),
            FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: Text(tr('حفظ'))),
          ],
        ),
      ),
    );
    final l = double.tryParse(litres.text);
    if (ok == true && l != null && l > 0) {
      await App.fuel.add(FillUp(
        date: DateTime.now(),
        litres: l,
        cost: double.tryParse(cost.text) ?? l * price,
        full: full,
      ));
    }
  }
}
