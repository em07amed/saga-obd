import 'package:flutter/services.dart';

import 'l10n.dart';
import 'maintenance/maintenance.dart';
import 'obd/bt_channel.dart';
import 'obd/obd_service.dart';
import 'obd/pids.dart';
import 'settings.dart';

/// Watches live readings and raises a system notification (sound + vibration,
/// works with the screen off) when something needs the driver's attention.
class AlertService {
  final ObdService obd;
  final AppSettings settings;
  final MaintenanceService maintenance;
  final BtChannel bt;

  /// Last time each alert fired, to avoid repeating every polling cycle.
  final Map<String, DateTime> _last = {};
  static const _cooldown = Duration(minutes: 5);

  bool _hot = false;
  int _lastDtcCount = 0;
  bool _maintenanceChecked = false;
  DateTime? _engineOnSince;

  AlertService(this.obd, this.settings, this.maintenance, this.bt) {
    obd.addListener(_check);
  }

  void _check() {
    if (!settings.alertsOn) return;
    if (obd.state != ObdState.connected) {
      _maintenanceChecked = false;
      _engineOnSince = null;
      return;
    }
    final v = obd.values;
    final rpm = v[Pids.rpm] ?? 0;
    final running = rpm > 500;
    if (running) {
      _engineOnSince ??= DateTime.now();
    } else {
      _engineOnSince = null;
    }

    // Coolant: fire at 105 °C, re-arm below 100 °C.
    final coolant = v[Pids.coolant];
    if (coolant != null) {
      if (!_hot && coolant >= 105) {
        _hot = true;
        _fire('hot', tr('حرارة الموتور عالية'),
            tr('حرارة المياه ${coolant.toStringAsFixed(0)}°C. اركن وطفي التكييف.'));
      } else if (_hot && coolant < 100) {
        _hot = false;
      }
    }

    // Charging: only judge after the engine has run for a minute.
    final volt = v[Pids.voltage];
    final settled = _engineOnSince != null &&
        DateTime.now().difference(_engineOnSince!) > const Duration(minutes: 1);
    if (volt != null && settled) {
      if (volt < 12.8) {
        _fire('lowvolt', tr('مشكلة في الشحن'),
            tr('البطارية ${volt.toStringAsFixed(1)}V والموتور شغال. افحص الدينامو.'));
      } else if (volt > 15.2) {
        _fire('highvolt', tr('فولت عالي'),
            tr('البطارية ${volt.toStringAsFixed(1)}V. افحص منظم الدينامو.'));
      }
    }

    // New stored trouble code (count from PID 01).
    final dtc = (v[Pids.status] ?? 0).round();
    if (dtc > _lastDtcCount) {
      _fire('dtc', tr('عطل جديد'),
          tr('الكمبيوتر سجّل $dtc كود. افتح القراءات ← الأعطال.'),
          force: true);
    }
    _lastDtcCount = dtc;

    // Maintenance due: once per connection.
    if (!_maintenanceChecked && maintenance.odometerKm != null) {
      _maintenanceChecked = true;
      final due = maintenance.due.where((d) => d.overdue || d.soon).toList();
      if (due.isNotEmpty) {
        final d = due.first;
        _fire('maint', tr('ميعاد صيانة'),
            tr(d.overdue
                ? '${d.entry.type} فات ميعاده'
                : '${d.entry.type} قرّب'),
            sound: false);
      }
    }
  }

  void _fire(String key, String title, String text,
      {bool force = false, bool sound = true}) {
    final now = DateTime.now();
    final last = _last[key];
    if (!force && last != null && now.difference(last) < _cooldown) return;
    _last[key] = now;
    HapticFeedback.heavyImpact();
    bt.notify(title, text, sound: sound).catchError((_) {});
  }

  void dispose() => obd.removeListener(_check);
}
