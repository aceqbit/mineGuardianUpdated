import 'package:flutter/material.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../bloc/sos_state.dart';
import 'evac_map_painter.dart';

/// Pannable / zoomable offline map (no tiles) with a legend and the route banner.
class EvacMapView extends StatefulWidget {
  const EvacMapView({super.key, required this.state});
  final SosState state;

  @override
  State<EvacMapView> createState() => _EvacMapViewState();
}

class _EvacMapViewState extends State<EvacMapView> with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(vsync: this, duration: const Duration(milliseconds: 1600));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduce(context)) {
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat();
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final layout = s.layout;
    if (layout == null) {
      return Container(
        decoration: BoxDecoration(color: c.surface, borderRadius: BorderRadius.circular(Radii.card), border: Border.all(color: c.border)),
        padding: const EdgeInsets.all(Space.x2),
        alignment: Alignment.center,
        child: Text('Map not downloaded yet.\nOpen the app once with a connection so the evacuation map is saved on this phone.', textAlign: TextAlign.center, style: t.bodyMedium),
      );
    }
    final control = s.activeControlRoute;
    final off = s.offlineRoute;
    final banner = control != null
        ? 'Route from control room · ${control.exitName} · ~${(control.etaSec / 60).ceil().clamp(1, 999)} min'
        : (off != null ? off.summary : 'No safe route found — follow signs to the nearest exit');

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: Container(
        color: c.surface,
        child: Stack(children: [
          Positioned.fill(
            child: InteractiveViewer(
              minScale: 0.8,
              maxScale: 6,
              child: AnimatedBuilder(
                animation: _pulse,
                builder: (context, _) => CustomPaint(
                  painter: EvacMapPainter(
                    layout: layout,
                    colors: c,
                    ownZone: s.zoneCode,
                    fix: s.fix,
                    hazards: s.hazards,
                    offlineRoute: off,
                    controlRoutes: s.controlRoutes,
                    activeControl: control,
                    pulse: _pulse.value,
                  ),
                  size: Size.infinite,
                ),
              ),
            ),
          ),
          Positioned(
            left: Space.md,
            right: Space.md,
            top: Space.md,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
              decoration: BoxDecoration(color: (control != null ? c.success : c.amber500), borderRadius: BorderRadius.circular(Radii.sm), boxShadow: Shadows.level(2)),
              child: Row(children: [
                Icon(control != null ? Icons.alt_route : Icons.directions_walk, color: control != null ? Colors.white : c.ink900, size: 20),
                const SizedBox(width: Space.sm),
                Expanded(child: Text(banner, maxLines: 2, overflow: TextOverflow.ellipsis, style: t.labelLarge?.copyWith(color: control != null ? Colors.white : c.ink900))),
              ]),
            ),
          ),
          if (s.positionUnknown)
            Positioned(
              left: Space.md,
              top: 64,
              child: Container(padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs), decoration: BoxDecoration(color: c.warningBg, borderRadius: BorderRadius.circular(Radii.sm)), child: Text('Position unknown', style: t.labelMedium?.copyWith(color: c.warning))),
            ),
          Positioned(left: Space.md, bottom: Space.md, child: _Legend(colors: c)),
        ]),
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.colors});
  final MgColors colors;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme.labelSmall?.copyWith(color: colors.text, fontSize: 10);
    Widget row(Color color, String label, {bool square = false, bool line = false}) => Padding(
          padding: const EdgeInsets.only(bottom: 2),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            line ? Container(width: 16, height: 4, color: color) : Container(width: 10, height: 10, decoration: BoxDecoration(color: color, shape: square ? BoxShape.rectangle : BoxShape.circle)),
            const SizedBox(width: 6),
            Text(label, style: t),
          ]),
        );
    return Container(
      padding: const EdgeInsets.all(Space.sm),
      decoration: BoxDecoration(color: colors.surface.withValues(alpha: 0.92), borderRadius: BorderRadius.circular(Radii.sm), border: Border.all(color: colors.border)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
        row(colors.positionBlue, 'You'),
        row(colors.success, 'Exit'),
        row(colors.info, 'Refuge', square: true),
        row(colors.amber500, 'Your route', line: true),
        row(colors.info, 'Intake', line: true),
        row(colors.slate500, 'Return', line: true),
        row(colors.danger, 'Blocked / hazard', line: true),
      ]),
    );
  }
}
