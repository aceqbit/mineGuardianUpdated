import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/models/mine_layout.dart';
import '../bloc/sos_state.dart';
import '../data/evac_graph.dart';
import '../data/nav_logic.dart';

LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);

/// Live map for the SOS / evacuation screen: your moving position (smoothly animated, with heading), the explicit target
/// exit, up to three self-computed routes re-planned as you move, turn-by-turn guidance, and the control room's route
/// when one arrives. Online it draws OpenStreetMap tiles under the mine layout; offline the layout lines still draw.
class LiveNavMap extends StatefulWidget {
  const LiveNavMap({super.key, required this.state, required this.onSelectRoute, this.onToggleSimulate});
  final SosState state;
  final ValueChanged<String> onSelectRoute;

  /// When set, a "Simulate walk" control is shown (evacuation view in debug builds or with NAV_SIMULATE).
  final VoidCallback? onToggleSimulate;

  @override
  State<LiveNavMap> createState() => _LiveNavMapState();
}

class _LiveNavMapState extends State<LiveNavMap> with SingleTickerProviderStateMixin {
  final _controller = MapController();
  late final AnimationController _move = AnimationController(vsync: this, duration: const Duration(milliseconds: 600));
  LatLng? _from, _to;
  bool _follow = true;
  bool _ready = false;

  LatLng? get _shown {
    final to = _to;
    if (to == null) return null;
    final from = _from ?? to;
    final t = Curves.easeOut.transform(_move.value);
    return LatLng(from.latitude + (to.latitude - from.latitude) * t, from.longitude + (to.longitude - from.longitude) * t);
  }

  @override
  void initState() {
    super.initState();
    final f = widget.state.fix;
    if (f != null) {
      _to = LatLng(f.lat, f.lng);
      _move.value = 1;
    }
    _move.addListener(_onTick);
  }

  void _onTick() {
    if (!mounted) return;
    final p = _shown;
    if (_ready && _follow && p != null) _controller.move(p, _controller.camera.zoom);
    setState(() {});
  }

  @override
  void didUpdateWidget(LiveNavMap old) {
    super.didUpdateWidget(old);
    final f = widget.state.fix;
    if (f == null) return;
    final next = LatLng(f.lat, f.lng);
    if (_to == null || next.latitude != _to!.latitude || next.longitude != _to!.longitude) {
      _from = _shown ?? next;
      _to = next;
      if (Motion.reduce(context)) {
        _move.value = 1;
      } else {
        _move.forward(from: 0);
      }
    }
  }

  @override
  void dispose() {
    _move.dispose();
    _controller.dispose();
    super.dispose();
  }

  LatLngBounds? _bounds(SosState s) {
    final pts = <LatLng>[
      if (s.fix != null) LatLng(s.fix!.lat, s.fix!.lng),
      if (s.offlineRoute != null) ...s.offlineRoute!.points.map(_ll),
      if (s.offlineRoute == null && s.layout != null) ...s.layout!.exits.map((e) => _ll(e.point)),
    ];
    return pts.length < 2 ? null : LatLngBounds.fromPoints(pts);
  }

  void _recentre() {
    setState(() => _follow = true);
    final p = _shown;
    if (p != null) _controller.move(p, math.max(_controller.camera.zoom, 17));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final layout = s.layout!;
    final c = MgColors.of(context);
    final route = s.offlineRoute;
    final control = s.activeControlRoute;
    final bounds = _bounds(s);
    final me = _shown;
    final centre = me ?? _ll(layout.anchor);
    final target = control != null ? null : route;
    final progress = (route != null && s.fix != null) ? routeProgress(route, GeoPoint(s.fix!.lat, s.fix!.lng)) : null;
    final steps = route == null ? const <NavStep>[] : buildSteps(route);

    final tunnelLines = <Polyline>[
      for (final tn in layout.tunnels)
        Polyline(
          points: tn.coords.map(_ll).toList(),
          strokeWidth: 3,
          color: (tn.blocked ? c.danger : (tn.airway == 'intake' ? c.info : c.slate500)).withValues(alpha: 0.7),
          pattern: tn.blocked ? StrokePattern.dashed(segments: const [6, 6]) : const StrokePattern.solid(),
        ),
    ];
    final altLines = <Polyline>[
      for (final r in s.alternatives)
        if (r.exit.id != route?.exit.id) Polyline(points: r.points.map(_ll).toList(), strokeWidth: 5, color: c.amber500.withValues(alpha: 0.45), pattern: StrokePattern.dashed(segments: const [10, 8])),
    ];
    final remainingPts = progress?.remaining ?? route?.points;
    final showChips = s.alternatives.length > 1 && control == null;

    return ClipRRect(
      borderRadius: BorderRadius.circular(Radii.card),
      child: Stack(children: [
        Positioned.fill(
          child: FlutterMap(
            mapController: _controller,
            options: MapOptions(
              backgroundColor: c.slate100,
              initialCenter: centre,
              initialZoom: 17,
              minZoom: 14,
              maxZoom: 20,
              initialCameraFit: bounds == null ? null : CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(48, 150, 48, 120), maxZoom: 19),
              onMapReady: () => _ready = true,
              onPositionChanged: (_, hasGesture) {
                if (hasGesture && _follow) setState(() => _follow = false);
              },
              interactionOptions: const InteractionOptions(flags: InteractiveFlag.all & ~InteractiveFlag.rotate),
            ),
            children: [
              TileLayer(
                urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                userAgentPackageName: 'app.mineguardian.mobile',
                maxNativeZoom: 19,
                errorTileCallback: (tile, error, stack) {}, // offline: leave the tile blank, the mine layout still draws
              ),
              PolylineLayer(polylines: tunnelLines),
              PolylineLayer(polylines: altLines),
              if (progress != null && progress.travelled.length > 1) PolylineLayer(polylines: [Polyline(points: progress.travelled.map(_ll).toList(), strokeWidth: 6, color: c.slate400.withValues(alpha: 0.8))]),
              if (remainingPts != null && remainingPts.length > 1) PolylineLayer(polylines: [Polyline(points: remainingPts.map(_ll).toList(), strokeWidth: 7, color: c.amber500, borderStrokeWidth: 2, borderColor: c.ink900)]),
              if (control != null) PolylineLayer(polylines: [Polyline(points: control.points.map(_ll).toList(), strokeWidth: 8, color: c.success, borderStrokeWidth: 2, borderColor: c.ink900)]),
              if (me != null) CircleLayer(circles: [CircleMarker(point: me, radius: s.fix!.accuracyM.clamp(3, 80).toDouble(), useRadiusInMeter: true, color: c.positionBlue.withValues(alpha: 0.15), borderColor: c.positionBlue, borderStrokeWidth: 1)]),
              MarkerLayer(markers: [
                for (final h in s.hazards.where((h) => h.blocking)) Marker(point: _ll(h.point), width: 34, height: 34, child: Icon(Icons.warning_rounded, color: c.danger, size: 30)),
                for (final r in layout.refuges) Marker(point: _ll(r.point), width: 30, height: 30, child: Icon(Icons.home_work, color: c.info, size: 26)),
                for (final e in layout.exits)
                  if (e.id != target?.exit.id) Marker(point: _ll(e.point), width: 30, height: 30, child: Icon(Icons.exit_to_app, color: c.success, size: 26)),
                if (target != null) Marker(point: _ll(target.exit.point), width: 120, height: 84, child: _TargetPin(label: target.exit.name, colors: c)),
                if (me != null) Marker(point: me, width: 44, height: 44, child: _YouMarker(heading: s.fix?.headingDeg, color: c.positionBlue)),
              ]),
            ],
          ),
        ),
        Positioned(left: Space.md, right: Space.md, top: Space.md, child: _TopCard(state: s, colors: c, steps: steps, progress: progress, route: route)),
        if (showChips) Positioned(left: Space.md, right: Space.md, bottom: Space.md, child: _RouteChips(state: s, colors: c, onSelect: widget.onSelectRoute)),
        Positioned(
          right: Space.md,
          bottom: showChips ? 72 : Space.md,
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            if (widget.onToggleSimulate != null) ...[
              FloatingActionButton.small(
                heroTag: null,
                tooltip: s.simulating ? 'Stop simulated walk' : 'Simulate walk to the exit',
                backgroundColor: s.simulating ? c.danger : c.surface,
                foregroundColor: s.simulating ? Colors.white : c.ink900,
                onPressed: widget.onToggleSimulate,
                child: Icon(s.simulating ? Icons.stop : Icons.directions_walk),
              ),
              const SizedBox(height: Space.sm),
            ],
            FloatingActionButton.small(heroTag: null, tooltip: 'Centre on me', backgroundColor: _follow ? c.amber500 : c.surface, foregroundColor: c.ink900, onPressed: _recentre, child: Icon(_follow ? Icons.my_location : Icons.location_searching)),
          ]),
        ),
        const Positioned(left: 6, bottom: 2, child: _Attribution()),
      ]),
    );
  }
}

class _Attribution extends StatelessWidget {
  const _Attribution();
  @override
  Widget build(BuildContext context) => Text('© OpenStreetMap contributors', style: Theme.of(context).textTheme.labelSmall?.copyWith(fontSize: 9, color: Colors.black54));
}

/// Position dot with an optional heading arrow and a soft pulse.
class _YouMarker extends StatelessWidget {
  const _YouMarker({required this.heading, required this.color});
  final double? heading;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final dot = Container(width: 24, height: 24, decoration: BoxDecoration(color: color, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: Shadows.level(2)));
    return _Breathe(
      scale: 0.12,
      child: Stack(alignment: Alignment.center, children: [
        if (heading != null) Transform.rotate(angle: heading! * math.pi / 180, child: Align(alignment: Alignment.topCenter, child: Icon(Icons.navigation, size: 18, color: color))),
        dot,
      ]),
    );
  }
}

class _TargetPin extends StatelessWidget {
  const _TargetPin({required this.label, required this.colors});
  final String label;
  final MgColors colors;

  @override
  Widget build(BuildContext context) {
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
        decoration: BoxDecoration(color: colors.successFill, borderRadius: BorderRadius.circular(Radii.pill), boxShadow: Shadows.level(2)),
        child: Text('TARGET · $label', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
      ),
      _Breathe(scale: 0.12, child: Icon(Icons.flag_circle, color: colors.success, size: 40)),
    ]);
  }
}

String _reasonText(TargetReason r) => switch (r) {
      TargetReason.controlRoom => 'Route set by the control room',
      TargetReason.designated => 'Emergency exit set by your admin',
      TargetReason.designatedUnavailable => "Your admin's exit is blocked: using the nearest safe exit",
      TargetReason.nearest => 'Nearest safe exit',
      TargetReason.workerChoice => 'Route you chose',
    };

IconData _turnIcon(Turn t) => switch (t) {
      Turn.start => Icons.directions_walk,
      Turn.straight => Icons.arrow_upward,
      Turn.slightLeft => Icons.turn_slight_left,
      Turn.left => Icons.turn_left,
      Turn.sharpLeft => Icons.turn_sharp_left,
      Turn.slightRight => Icons.turn_slight_right,
      Turn.right => Icons.turn_right,
      Turn.sharpRight => Icons.turn_sharp_right,
      Turn.arrive => Icons.flag,
    };

class _TopCard extends StatelessWidget {
  const _TopCard({required this.state, required this.colors, required this.steps, required this.progress, required this.route});
  final SosState state;
  final MgColors colors;
  final List<NavStep> steps;
  final RouteProgress? progress;
  final EvacRoute? route;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final s = state;
    final control = s.activeControlRoute;
    String title;
    String sub;
    Color bg = colors.amber500, fg = colors.ink900;
    IconData icon = Icons.directions_walk;
    if (s.arrived) {
      title = 'You have reached ${route?.exit.name ?? 'the exit'}';
      sub = 'Report to your supervisor so you are counted safe';
      bg = colors.successFill;
      fg = Colors.white;
      icon = Icons.verified;
    } else if (control != null) {
      title = 'Control room route · ${control.exitName}';
      sub = '~${(control.etaSec / 60).ceil().clamp(1, 999)} min';
      bg = colors.successFill;
      fg = Colors.white;
      icon = Icons.alt_route;
    } else if (route != null) {
      final remaining = progress?.remainingM ?? route!.distanceM;
      final eta = math.max(1, (remaining / walkSpeedMps / 60).ceil());
      title = 'Go to ${route!.exit.name}';
      sub = '${remaining.round()} m left · ~$eta min · ${_reasonText(s.targetReason)}';
    } else {
      title = 'No safe route found';
      sub = 'Follow signs to the nearest exit';
      bg = colors.warningFill;
      fg = Colors.white;
      icon = Icons.warning_amber;
    }
    final cs = (route != null && progress != null && steps.isNotEmpty && !s.arrived && control == null) ? currentStep(steps, route!, progress!) : null;
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.sm), boxShadow: Shadows.level(2)),
          child: Row(children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w800)),
                Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: fg)),
              ]),
            ),
          ]),
        ),
      ),
      if (cs != null) ...[
        const SizedBox(height: Space.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          decoration: BoxDecoration(color: colors.ink900, borderRadius: BorderRadius.circular(Radii.sm), boxShadow: Shadows.level(2)),
          child: Row(children: [
            Icon(_turnIcon(cs.next?.turn ?? cs.step.turn), color: colors.amber500, size: 26),
            const SizedBox(width: Space.md),
            Expanded(
              child: Text(
                cs.next == null || cs.next!.turn == Turn.arrive ? 'In ${cs.metresToNext.round()} m: arrive at ${route!.exit.name}' : 'In ${cs.metresToNext.round()} m: ${cs.next!.text.split(', then').first.toLowerCase()}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: text.titleSmall?.copyWith(color: Colors.white),
              ),
            ),
          ]),
        ),
      ],
      if (s.offRoute && !s.arrived && control == null) ...[
        const SizedBox(height: Space.xs),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.xs),
          decoration: BoxDecoration(color: colors.dangerBg, borderRadius: BorderRadius.circular(Radii.sm), border: Border.all(color: colors.danger)),
          child: Row(children: [
            Icon(Icons.wrong_location, color: colors.danger, size: 18),
            const SizedBox(width: Space.sm),
            Expanded(child: Text('Off route by ${s.offRouteM!.round()} m — route is being re-planned', style: text.labelMedium?.copyWith(color: colors.danger))),
          ]),
        ),
      ],
      if (s.positionUnknown) ...[
        const SizedBox(height: Space.xs),
        Align(alignment: Alignment.centerLeft, child: Container(padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs), decoration: BoxDecoration(color: colors.warningBg, borderRadius: BorderRadius.circular(Radii.sm)), child: Text('Position unknown — route starts from your zone', style: text.labelMedium?.copyWith(color: colors.warning)))),
      ],
    ]);
  }
}

class _RouteChips extends StatelessWidget {
  const _RouteChips({required this.state, required this.colors, required this.onSelect});
  final SosState state;
  final MgColors colors;
  final ValueChanged<String> onSelect;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context).textTheme;
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(children: [
        for (var i = 0; i < state.alternatives.length; i++)
          Padding(
            padding: const EdgeInsets.only(right: Space.sm),
            child: ChoiceChip(
              selected: state.alternatives[i].exit.id == state.selectedExitId,
              selectedColor: colors.amber500,
              backgroundColor: colors.surface,
              label: Text('Route ${String.fromCharCode(65 + i)} · ${state.alternatives[i].exit.name} · ${state.alternatives[i].distanceM.round()} m · ${state.alternatives[i].etaMin} min', style: t.labelMedium?.copyWith(color: state.alternatives[i].exit.id == state.selectedExitId ? colors.ink900 : colors.text)),
              onSelected: (_) => onSelect(state.alternatives[i].exit.id),
            ),
          ),
      ]),
    );
  }
}

/// Gentle looping scale pulse; static when the user asked for reduced motion.
class _Breathe extends StatefulWidget {
  const _Breathe({required this.child, required this.scale});
  final Widget child;
  final double scale;

  @override
  State<_Breathe> createState() => _BreatheState();
}

class _BreatheState extends State<_Breathe> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduce(context)) {
      _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => ScaleTransition(scale: Tween(begin: 1.0, end: 1.0 + widget.scale).animate(CurvedAnimation(parent: _c, curve: Curves.easeInOut)), child: widget.child);
}
