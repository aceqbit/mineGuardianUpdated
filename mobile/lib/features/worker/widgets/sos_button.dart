import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';

/// Press and hold for 2 s: a ring fills, a haptic tick fires every 0.5 s, releasing early cancels with a shake.
class SosButton extends StatefulWidget {
  const SosButton({super.key, required this.onTriggered, this.size = 72});
  final VoidCallback onTriggered;
  final double size;

  @override
  State<SosButton> createState() => _SosButtonState();
}

class _SosButtonState extends State<SosButton> with TickerProviderStateMixin {
  late final AnimationController _hold = AnimationController(vsync: this, duration: const Duration(seconds: 2));
  late final AnimationController _shake = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  int _ticks = 0;

  @override
  void initState() {
    super.initState();
    _hold.addListener(_onTick);
    _hold.addStatusListener((s) {
      if (s == AnimationStatus.completed) {
        HapticFeedback.heavyImpact();
        _hold.value = 0;
        _ticks = 0;
        widget.onTriggered();
      }
    });
  }

  void _onTick() {
    final n = (_hold.value * 4).floor(); // every 0.5 s
    if (n > _ticks && n < 4) {
      _ticks = n;
      HapticFeedback.selectionClick();
    }
  }

  void _start() {
    _ticks = 0;
    HapticFeedback.lightImpact();
    _hold.forward(from: 0);
  }

  void _cancel() {
    if (_hold.status == AnimationStatus.completed || !_hold.isAnimating && _hold.value == 0) return;
    _hold.stop();
    _hold.value = 0;
    if (!Motion.reduce(context)) _shake.forward(from: 0);
  }

  @override
  void dispose() {
    _hold.dispose();
    _shake.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return Semantics(
      button: true,
      label: 'Hold for 2 seconds to send SOS',
      excludeSemantics: true,
      // Raw pointer events: tap + long-press recognizers would cancel the hold at ~500 ms (the long press wins the arena).
      child: Listener(
        behavior: HitTestBehavior.opaque,
        onPointerDown: (_) => _start(),
        onPointerUp: (_) => _cancel(),
        onPointerCancel: (_) => _cancel(),
        child: AnimatedBuilder(
          animation: Listenable.merge([_hold, _shake]),
          builder: (context, _) {
            final dx = math.sin(_shake.value * 3 * 2 * math.pi) * 5 * (1 - _shake.value);
            return Transform.translate(
              offset: Offset(dx, 0),
              child: SizedBox(
                width: widget.size,
                height: widget.size,
                child: Stack(alignment: Alignment.center, children: [
                  Container(
                    width: widget.size - 8,
                    height: widget.size - 8,
                    decoration: BoxDecoration(color: c.danger, shape: BoxShape.circle, boxShadow: Shadows.level(2)),
                    alignment: Alignment.center,
                    child: Text('SOS', style: Theme.of(context).textTheme.titleMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
                  ),
                  SizedBox(width: widget.size, height: widget.size, child: CircularProgressIndicator(value: _hold.value, strokeWidth: 5, color: Colors.white, backgroundColor: Colors.transparent)),
                ]),
              ),
            );
          },
        ),
      ),
    );
  }
}
