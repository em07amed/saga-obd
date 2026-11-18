import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../l10n.dart';
import '../main.dart';
import '../obd/bt_channel.dart';

/// Sits above every screen: a big answer/decline card while the phone rings,
/// and a slim in-call bar (timer, mute, speaker, hang up) during a call.
class CallOverlay extends StatefulWidget {
  final Widget child;
  const CallOverlay({super.key, required this.child});

  @override
  State<CallOverlay> createState() => _CallOverlayState();
}

class _CallOverlayState extends State<CallOverlay> {
  Timer? _tick;
  String _announced = '';

  @override
  void initState() {
    super.initState();
    BtChannel.phoneCall.addListener(_changed);
    App.obd.bt.refreshCall().catchError((_) {});
  }

  @override
  void dispose() {
    BtChannel.phoneCall.removeListener(_changed);
    _tick?.cancel();
    super.dispose();
  }

  void _changed() {
    final c = BtChannel.phoneCall.value;
    if (c.ringing) {
      final key = 'ring${c.who}';
      if (_announced != key && App.settings.voiceAlerts) {
        _announced = key;
        App.obd.bt
            .speak(
                c.who.isEmpty ? tr('مكالمة واردة') : tr('مكالمة من ${c.who}'),
                Lang.code,
                flush: true)
            .catchError((_) {});
      }
    } else if (c.idle) {
      _announced = '';
    }
    _tick?.cancel();
    if (c.state == 'offhook') {
      _tick = Timer.periodic(
          const Duration(seconds: 1), (_) => mounted ? setState(() {}) : null);
    }
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final c = BtChannel.phoneCall.value;
    return Stack(children: [
      widget.child,
      if (c.ringing) _ringing(c),
      if (c.state == 'offhook')
        Positioned(top: 0, left: 0, right: 0, child: _inCall(c)),
    ]);
  }

  Widget _ringing(CallInfo c) {
    final bt = App.obd.bt;
    return Positioned.fill(
      child: Material(
        color: Colors.black.withValues(alpha: 0.85),
        child: SafeArea(
          child: Center(
            child: Column(mainAxisSize: MainAxisSize.min, children: [
              const Icon(Icons.ring_volume, color: Colors.white70, size: 56),
              const SizedBox(height: 12),
              Text(tr('مكالمة واردة'),
                  style: const TextStyle(color: Colors.white70, fontSize: 18)),
              const SizedBox(height: 8),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(c.who.isEmpty ? tr('رقم غير معروف') : c.who,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 34,
                        fontWeight: FontWeight.bold)),
              ),
              if (c.name != null && c.number != null)
                Text(c.number!,
                    textDirection: TextDirection.ltr,
                    style: const TextStyle(color: Colors.white60, fontSize: 18)),
              const SizedBox(height: 48),
              Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
                _round(Icons.call_end, Colors.red, tr('رفض'), () async {
                  if (!await bt.endCall()) _noControl();
                }),
                _round(Icons.call, Colors.green, tr('رد'), () async {
                  if (!await bt.answerCall()) _noControl();
                }),
              ]),
            ]),
          ),
        ),
      ),
    );
  }

  Widget _inCall(CallInfo c) {
    final bt = App.obd.bt;
    final d = c.since == null
        ? Duration.zero
        : DateTime.now().difference(c.since!);
    final t =
        '${d.inMinutes.toString().padLeft(2, '0')}:${(d.inSeconds % 60).toString().padLeft(2, '0')}';
    return Material(
      color: const Color(0xFF1B5E20),
      elevation: 6,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          child: Row(children: [
            const Icon(Icons.call, color: Colors.white),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(c.who.isEmpty ? tr('مكالمة') : c.who,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 16)),
                    Text(t,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(color: Colors.white70)),
                  ]),
            ),
            IconButton(
              tooltip: tr('كتم'),
              color: Colors.white,
              icon: Icon(c.muted ? Icons.mic_off : Icons.mic),
              onPressed: () async {
                final m = await bt.setMute(!c.muted);
                _patch(c, muted: m);
              },
            ),
            IconButton(
              tooltip: tr('سبيكر'),
              color: Colors.white,
              icon: Icon(c.speaker ? Icons.volume_up : Icons.hearing),
              onPressed: () async {
                final s = await bt.setSpeaker(!c.speaker);
                _patch(c, speaker: s);
              },
            ),
            const SizedBox(width: 4),
            FilledButton(
              style: FilledButton.styleFrom(
                  backgroundColor: Colors.red,
                  shape: const CircleBorder(),
                  padding: const EdgeInsets.all(12)),
              onPressed: () async {
                HapticFeedback.mediumImpact();
                if (!await bt.endCall()) _noControl();
              },
              child: const Icon(Icons.call_end, color: Colors.white),
            ),
          ]),
        ),
      ),
    );
  }

  void _patch(CallInfo c, {bool? muted, bool? speaker}) {
    BtChannel.phoneCall.value = CallInfo(c.state, c.number, c.name, c.incoming,
        c.since, speaker ?? c.speaker, muted ?? c.muted);
  }

  void _noControl() {
    App.obd.bt
        .speak(tr('مش قادر أتحكم في المكالمة. اسمح بإذن الهاتف'), Lang.code,
            flush: true)
        .catchError((_) {});
  }

  Widget _round(IconData icon, Color color, String label, VoidCallback onTap) =>
      Column(mainAxisSize: MainAxisSize.min, children: [
        SizedBox(
          width: 84,
          height: 84,
          child: FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: color,
                shape: const CircleBorder(),
                padding: EdgeInsets.zero),
            onPressed: () {
              HapticFeedback.heavyImpact();
              onTap();
            },
            child: Icon(icon, color: Colors.white, size: 40),
          ),
        ),
        const SizedBox(height: 8),
        Text(label, style: const TextStyle(color: Colors.white, fontSize: 16)),
      ]);
}
