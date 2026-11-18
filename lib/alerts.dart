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
  bool _speeding = false;
  DateTime? _lastSpeedWarn;
  DateTime? _lastHotWarn;

  /// While a condition lasts, repeat a short warning this often.
  static const _repeat = Duration(seconds: 3);

  bool _dueAgain(DateTime? last) =>
      last == null || DateTime.now().difference(last) >= _repeat;

  /// Short repeat: a few spoken words, or a beep if voice is off.
  void _nag(String words, {required bool voice}) {
    HapticFeedback.heavyImpact();
    if (voice) {
      bt.speak(words, Lang.code, flush: true).catchError((_) {});
    } else {
      bt.beep().catchError((_) {});
    }
  }

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

    _checkSpeed(v[Pids.speed]);

    // Coolant: fire at the configured limit, re-arm 5 °C below it.
    final coolant = v[Pids.coolant];
    final limit = settings.coolantAlert;
    if (coolant != null) {
      if (!_hot && coolant >= limit) {
        _hot = true;
        _lastHotWarn = DateTime.now();
        _fire('hot', tr('حرارة الموتور عالية'),
            tr('حرارة المياه ${coolant.toStringAsFixed(0)}°C. اركن وطفي التكييف.'),
            speech: tr('تحذير. حرارة الموتور وصلت ${coolant.toStringAsFixed(0)} درجة. '
                'اركن على جنب وطفي التكييف.'),
            force: true);
      } else if (_hot && coolant < limit) {
        _hot = false; // back to normal: stop repeating
      } else if (_hot && _dueAgain(_lastHotWarn)) {
        // Still hot: keep warning every few seconds until it cools down.
        // The first message is long, so give it time to finish.
        if (DateTime.now().difference(_lastHotWarn!) >=
            const Duration(seconds: 6)) {
          _lastHotWarn = DateTime.now();
          _nag(tr('الحرارة ${coolant.toStringAsFixed(0)}'),
              voice: settings.voiceAlerts);
        }
      }
    }

    // Charging: only judge after the engine has run for a minute.
    final volt = v[Pids.voltage];
    final settled = _engineOnSince != null &&
        DateTime.now().difference(_engineOnSince!) > const Duration(minutes: 1);
    if (volt != null && settled) {
      if (volt < 12.8) {
        _fire('lowvolt', tr('مشكلة في الشحن'),
            tr('البطارية ${volt.toStringAsFixed(1)}V والموتور شغال. افحص الدينامو.'),
            speech: tr('تحذير. البطارية مش بتشحن كويس. افحص الدينامو.'));
      } else if (volt > 15.2) {
        _fire('highvolt', tr('فولت عالي'),
            tr('البطارية ${volt.toStringAsFixed(1)}V. افحص منظم الدينامو.'),
            speech: tr('تحذير. فولت الشحن عالي. افحص منظم الدينامو.'));
      }
    }

    // New stored trouble code (count from PID 01).
    final dtc = (v[Pids.status] ?? 0).round();
    if (dtc > _lastDtcCount) {
      _fire('dtc', tr('عطل جديد'),
          tr('الكمبيوتر سجّل $dtc كود. افتح القراءات ← الأعطال.'),
          speech: tr('انتباه. كمبيوتر العربية سجّل عطل جديد.'),
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
            speech: tr(d.overdue
                ? 'تذكير. ميعاد ${d.entry.type} فات.'
                : 'تذكير. ميعاد ${d.entry.type} قرّب.'),
            sound: false);
      }
    }
  }

  /// Warn when speed goes over the driver's limit; repeat every 20 s while
  /// still over, re-arm once 3 km/h back under the limit.
  void _checkSpeed(double? speed) {
    final mode = settings.speedAlertMode;
    if (speed == null || mode == 'off') return;
    final limit = settings.speedLimit;
    final now = DateTime.now();
    if (speed > limit) {
      if (!_speeding) {
        // First warning: full sentence.
        _speeding = true;
        _lastSpeedWarn = now.add(const Duration(seconds: 2)); // let it finish
        HapticFeedback.heavyImpact();
        if (mode == 'beep') {
          bt.beep().catchError((_) {});
        } else {
          bt
              .speak(
                  tr('انتبه. سرعتك ${speed.round()}، والحد ${limit.round()}.'),
                  Lang.code,
                  flush: true)
              .catchError((_) {});
        }
      } else if (_dueAgain(_lastSpeedWarn)) {
        // Still over: repeat every 3 s until back under the limit.
        _lastSpeedWarn = now;
        _nag('${speed.round()}', voice: mode == 'voice');
      }
    } else {
      _speeding = false; // back to normal: stop repeating
    }
  }

  void _fire(String key, String title, String text,
      {String? speech, bool force = false, bool sound = true}) {
    final now = DateTime.now();
    final last = _last[key];
    if (!force && last != null && now.difference(last) < _cooldown) return;
    _last[key] = now;
    HapticFeedback.heavyImpact();
    bt.notify(title, text, sound: sound).catchError((_) {});
    if (settings.voiceAlerts && speech != null) {
      bt.speak(speech, Lang.code).catchError((_) {});
    }
  }

  void dispose() => obd.removeListener(_check);
}
