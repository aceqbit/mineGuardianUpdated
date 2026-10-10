import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../core/models/mine_layout.dart';
import '../bloc/sos_state.dart';

LatLng _ll(GeoPoint p) => LatLng(p.lat, p.lng);

/// Live map for the SOS / evacuation screen: your moving position, the explicit target exit, up to three
/// self-computed routes (re-planned as you move) and the control room's route when one arrives.
/// Online it draws OpenStreetMap tiles under the mine layout; offline the layout lines still draw on a plain background.
class LiveNavMap extends StatefulWidget {
  const LiveNavMap({super.key, required this.state, required this.onSelectRoute});
  final SosState state;
  final ValueChanged<String> onSelectRoute;

  @override
  State<LiveNavMap> createState() => _LiveNavMapState();
}

class _LiveNavMapState extends State<LiveNavMap> {
  final _controller = MapController();
  bool _follow = true;
  bool _ready = false;

  @override
  void didUpdateWidget(LiveNavMap old) {
    super.didUpdateWidget(old);
    final f = widget.state.fix;
    if (_ready && _follow && f != null && (f.lat != old.state.fix?.lat || f.lng != old.state.fix?.lng)) {
      _controller.move(LatLng(f.lat, f.lng), _controller.camera.zoom);
    }
  }

  @override
  void dispose() {
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
    final s = widget.state;
    setState(() => _follow = true);
    final f = s.fix;
    if (f != null) _controller.move(LatLng(f.lat, f.lng), math.max(_controller.camera.zoom, 17));
  }

  @override
  Widget build(BuildContext context) {
    final s = widget.state;
    final layout = s.layout!;
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final route = s.offlineRoute;
    final control = s.activeControlRoute;
    final bounds = _bounds(s);
    final centre = s.fix != null ? LatLng(s.fix!.lat, s.fix!.lng) : _ll(layout.anchor);
    final target = control != null ? null : route;

    final tunnelLines = <Polyline>[
      for (final tn in layout.tunnels)
        Polyline(
          points: tn.coords.map(_ll).toList(),
          strokeWidth: 3,
          color: tn.blocked ? c.danger : (tn.airway == 'intake' ? c.info : c.slate500).withValues(alpha: 0.7),
          pattern: tn.blocked ? StrokePattern.dashed(segments: const [6, 6]) : const StrokePattern.solid(),
        ),
    ];
    final altLines = <Polyline>[
      for (final r in s.alternatives)
        if (r.exit.id != route?.exit.id) Polyline(points: r.points.map(_ll).toList(), strokeWidth: 5, color: c.amber500.withValues(alpha: 0.45), pattern: StrokePattern.dashed(segments: const [10, 8])),
    ];

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
              initialCameraFit: bounds == null ? null : CameraFit.bounds(bounds: bounds, padding: const EdgeInsets.fromLTRB(48, 120, 48, 120), maxZoom: 19),
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
              if (route != null) PolylineLayer(polylines: [Polyline(points: route.points.map(_ll).toList(), strokeWidth: 7, color: c.amber500, borderStrokeWidth: 2, borderColor: c.ink900)]),
              if (control != null) PolylineLayer(polylines: [Polyline(points: control.points.map(_ll).toList(), strokeWidth: 8, color: c.success, borderStrokeWidth: 2, borderColor: c.ink900)]),
              if (s.fix != null) CircleLayer(circles: [CircleMarker(point: LatLng(s.fix!.lat, s.fix!.lng), radius: s.fix!.accuracyM.clamp(3, 80).toDouble(), useRadiusInMeter: true, color: const Color(0xFF2563EB).withValues(alpha: 0.15), borderColor: const Color(0xFF2563EB), borderStrokeWidth: 1)]),
              MarkerLayer(markers: [
                for (final h in s.hazards.where((h) => h.blocking)) Marker(point: _ll(h.point), width: 34, height: 34, child: Icon(Icons.warning_rounded, color: c.danger, size: 30)),
                for (final r in layout.refuges) Marker(point: _ll(r.point), width: 30, height: 30, child: Icon(Icons.home_work, color: c.info, size: 26)),
                for (final e in layout.exits)
                  if (e.id != (target?.exit.id)) Marker(point: _ll(e.point), width: 30, height: 30, child: Icon(Icons.exit_to_app, color: c.success, size: 26)),
                if (target != null) Marker(point: _ll(target.exit.point), width: 120, height: 84, child: _TargetPin(label: target.exit.name, colors: c)),
                if (s.fix != null) Marker(point: LatLng(s.fix!.lat, s.fix!.lng), width: 28, height: 28, child: const _YouDot()),
              ]),
            ],
          ),
        ),
        Positioned(left: Space.md, right: Space.md, top: Space.md, child: _TopCard(state: s, colors: c, text: t)),
        if (s.alternatives.length > 1 && control == null)
          Positioned(
            left: Space.md,
            right: Space.md,
            bottom: Space.md,
            child: _RouteChips(state: s, colors: c, onSelect: widget.onSelectRoute),
          ),
        Positioned(
          right: Space.md,
          bottom: s.alternatives.length > 1 && control == null ? 72 : Space.md,
          child: FloatingActionButton.small(heroTag: null, tooltip: 'Centre on me', backgroundColor: _follow ? c.amber500 : c.surface, foregroundColor: c.ink900, onPressed: _recentre, child: Icon(_follow ? Icons.my_location : Icons.location_searching)),
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

class _YouDot extends StatelessWidget {
  const _YouDot();
  @override
  Widget build(BuildContext context) {
    final dot = Container(decoration: BoxDecoration(color: const Color(0xFF2563EB), shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: Shadows.level(2)));
    return _Breathe(scale: 0.15, child: dot);
  }
}

class _TargetPin extends StatelessWidget {
  const _TargetPin({required this.label, required this.colors});
  final String label;
  final MgColors colors;

  @override
  Widget build(BuildContext context) {
    final icon = Icon(Icons.flag_circle, color: colors.success, size: 40);
    return Column(mainAxisSize: MainAxisSize.min, children: [
      Container(
        padding: const EdgeInsets.symmetric(horizontal: Space.sm, vertical: Space.xs),
        decoration: BoxDecoration(color: colors.success, borderRadius: BorderRadius.circular(Radii.pill), boxShadow: Shadows.level(2)),
        child: Text('TARGET · $label', maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(color: Colors.white, fontSize: 10, fontWeight: FontWeight.w800)),
      ),
      _Breathe(scale: 0.12, child: icon),
    ]);
  }
}

class _TopCard extends StatelessWidget {
  const _TopCard({required this.state, required this.colors, required this.text});
  final SosState state;
  final MgColors colors;
  final TextTheme text;

  @override
  Widget build(BuildContext context) {
    final s = state;
    final control = s.activeControlRoute;
    final route = s.offlineRoute;
    String title;
    String sub;
    Color bg = colors.amber500, fg = colors.ink900;
    IconData icon = Icons.directions_walk;
    if (s.arrived) {
      title = 'You have reached ${route?.exit.name ?? 'the exit'}';
      sub = 'Report to your supervisor so you are counted safe';
      bg = colors.success;
      fg = Colors.white;
      icon = Icons.verified;
    } else if (control != null) {
      title = 'Control room route · ${control.exitName}';
      sub = '~${(control.etaSec / 60).ceil().clamp(1, 999)} min';
      bg = colors.success;
      fg = Colors.white;
      icon = Icons.alt_route;
    } else if (route != null) {
      final left = s.distanceToTargetM;
      title = 'Go to ${route.exit.name}';
      sub = '${route.distanceM.round()} m by tunnel · ~${route.etaMin} min${left == null ? '' : ' · ${left.round()} m straight line'}';
    } else {
      title = 'No safe route found';
      sub = 'Follow signs to the nearest exit';
      bg = colors.warning;
      fg = Colors.white;
      icon = Icons.warning_amber;
    }
    return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Semantics(
        liveRegion: true,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
          decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(Radii.sm), boxShadow: Shadows.level(2)),
          child: Row(children: [
            Icon(icon, color: fg, size: 22),
            const SizedBox(width: Space.sm),
            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: text.titleSmall?.copyWith(color: fg, fontWeight: FontWeight.w800)),
              Text(sub, maxLines: 2, overflow: TextOverflow.ellipsis, style: text.bodySmall?.copyWith(color: fg)),
            ])),
          ]),
        ),
      ),
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
