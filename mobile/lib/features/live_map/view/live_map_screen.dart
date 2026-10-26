import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:go_router/go_router.dart';
import 'package:latlong2/latlong.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/glass_card.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/skeleton.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/db/cache_repository.dart';
import '../../../core/location/location_service.dart';
import '../../../core/location/tracking_controller.dart';
import '../../../core/models/mine_layout.dart';
import '../../../core/sensors/fusion_engine.dart';
import '../../sos/data/nav_logic.dart';
import '../bloc/live_map_bloc.dart';
import '../data/live_map_repository.dart';
import '../data/route_modes.dart';
import '../widgets/live_tracking_pill.dart';
import '../widgets/map_launch.dart';
import '../widgets/mine_base_map.dart';
import '../widgets/route_cards.dart';

/// Live positions for the map: the fused tracker while it runs (GPS + motion sensors), otherwise a plain GPS stream.
Stream<MapFix> livePositions(BuildContext context) async* {
  TrackingController? tracking;
  try {
    tracking = RepositoryProvider.of<TrackingController>(context);
  } catch (_) {/* not wired (tests) */}
  final loc = LocationService();
  if (await loc.ensurePermission() != LocationAccess.granted) return;
  MapFix fromFused(FusedFix f) => MapFix(lat: f.lat, lng: f.lng, accuracyM: f.accuracyM, ts: f.ts, source: f.source, headingDeg: f.headingDeg, speedMps: f.speedMps, tunnelId: f.tunnelId);
  final gps = loc.stream(distanceFilter: 2).where((_) => tracking?.status.phase != TrackingPhase.live).map((f) => MapFix(lat: f.lat, lng: f.lng, accuracyM: f.accuracyM, ts: f.ts, headingDeg: f.headingDeg, speedMps: f.speedMps));
  final fused = tracking == null ? const Stream<MapFix>.empty() : tracking.status$.map((s) => s.fix).where((f) => f != null).map((f) => fromFused(f!));
  final ctrl = StreamController<MapFix>();
  final subs = [gps.listen(ctrl.add, onError: (_) {}), fused.listen(ctrl.add, onError: (_) {})];
  ctrl.onCancel = () async {
    for (final s in subs) {
      await s.cancel();
    }
  };
  yield* ctrl.stream;
}

/// `/worker/map`: the miner's live map (CLAUDE.md section 23.4).
class LiveMapScreen extends StatelessWidget {
  const LiveMapScreen({super.key, this.repository, this.positions});
  final LiveMapRepository? repository;
  final Stream<MapFix>? positions;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => LiveMapBloc(
        repo: repository ?? LiveMapRepository(api: ctx.read<ApiClient>(), cache: ctx.read<CacheRepository>()),
        positions: positions ?? livePositions(ctx),
      )..add(const LiveMapStarted()),
      child: const _View(),
    );
  }
}

class _View extends StatefulWidget {
  const _View();
  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  final _map = MapController();
  bool _follow = true;

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _centre(GeoPoint p) {
    try {
      _map.move(toLatLng(p), math.max(_map.camera.zoom, 17));
    } catch (_) {/* map not laid out yet */}
  }

  Future<void> _pickDestination(LiveMapState s) async {
    final id = await showDestinationPicker(context, targets: s.planner!.targets, currentId: s.target?.id);
    if (id != null && mounted) context.read<LiveMapBloc>().add(LiveMapTargetChosen(id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go(Routes.worker)),
        title: const Text('Live map'),
        actions: const [LiveTrackingPill(), SizedBox(width: Space.sm)],
      ),
      body: MapLaunchOverlay(
        child: BlocConsumer<LiveMapBloc, LiveMapState>(
          listenWhen: (a, b) => a.fix?.ts != b.fix?.ts,
          listener: (context, s) {
            if (_follow && s.fix != null && !s.outsideMine) _centre(s.fix!.point);
          },
          builder: (context, s) {
            switch (s.status) {
              case LiveMapStatus.loading:
                return const Padding(padding: EdgeInsets.all(Space.lg), child: SkeletonList(count: 3));
              case LiveMapStatus.noLayout:
                return EmptyState(icon: Icons.map_outlined, title: 'Mine layout not downloaded yet', message: 'Connect to the mine network once so the map can download the real layout. It then works offline.', actionLabel: 'Retry', onAction: () => context.read<LiveMapBloc>().add(const LiveMapStarted()));
              case LiveMapStatus.ready:
                return _readyView(context, s);
            }
          },
        ),
      ),
    );
  }

  Widget _readyView(BuildContext context, LiveMapState s) {
    final c = MgColors.of(context);
    final bloc = context.read<LiveMapBloc>();
    final sel = s.selected;
    final wide = context.sizeClass == SizeClass.expanded;
    final routeLayers = <Widget>[
      PolylineLayer(polylines: [
        for (final r in s.routes)
          if (r.key != sel?.key) Polyline(points: r.points.map(toLatLng).toList(), strokeWidth: 5, color: modeColor(c, r.primary).withValues(alpha: 0.55), pattern: StrokePattern.dashed(segments: const [10, 8])),
        if (sel != null) Polyline(points: sel.points.map(toLatLng).toList(), strokeWidth: 8, color: modeColor(c, sel.primary), borderStrokeWidth: 2, borderColor: c.ink900),
      ]),
      if (s.fix != null && !s.outsideMine) _SelfLayer(fix: s.fix!),
    ];
    final markers = <Marker>[
      if (s.pinnedStart != null) Marker(point: toLatLng(s.pinnedStart!), width: 34, height: 34, child: Icon(Icons.trip_origin, color: c.amberText, size: 30)),
      if (s.target != null) Marker(point: toLatLng(s.target!.point), width: 44, height: 44, alignment: Alignment.topCenter, child: Icon(Icons.flag_circle, color: c.success, size: 40)),
    ];
    final map = MineBaseMap(
      layout: s.layout!,
      controller: _map,
      hazards: s.hazards,
      layers: routeLayers,
      markers: markers,
      highlightTargetId: s.target?.id,
      onTapTarget: (id) => bloc.add(LiveMapTargetChosen(id)),
      onLongPress: (p) => _onLongPress(context, p),
    );
    final mapStack = Listener(
      onPointerDown: (_) {
        if (_follow) setState(() => _follow = false);
      },
      child: Stack(children: [
        Positioned.fill(child: map),
        Positioned(left: Space.md, right: Space.md, top: Space.md, child: _TopCard(state: s)),
        Positioned(
          right: Space.md,
          bottom: wide ? Space.md : 196,
          child: FloatingActionButton.small(
            heroTag: null,
            tooltip: 'Centre on me',
            backgroundColor: _follow ? c.amber500 : c.surface,
            foregroundColor: c.ink900,
            onPressed: () {
              setState(() => _follow = true);
              if (s.fix != null) _centre(s.fix!.point);
            },
            child: Icon(_follow ? Icons.my_location : Icons.location_searching),
          ),
        ),
      ]),
    );
    final panel = _RoutesPanel(state: s, wide: wide, onDestination: () => _pickDestination(s));
    if (wide) {
      return Row(children: [
        SizedBox(width: 380, child: panel),
        VerticalDivider(width: 1, color: c.border),
        Expanded(child: mapStack),
      ]);
    }
    return Column(children: [Expanded(child: mapStack), panel]);
  }

  void _onLongPress(BuildContext context, GeoPoint p) {
    final bloc = context.read<LiveMapBloc>();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          ListTile(leading: const Icon(Icons.flag), title: const Text('Go here'), subtitle: const Text('Route to the nearest junction'), onTap: () {
            bloc.add(LiveMapPointChosen(p));
            Navigator.of(ctx).pop();
          }),
          ListTile(leading: const Icon(Icons.trip_origin), title: const Text('Start from here'), subtitle: const Text('Instead of my live position'), onTap: () {
            bloc.add(LiveMapStartPinned(p));
            Navigator.of(ctx).pop();
          }),
          if (bloc.state.pinnedStart != null)
            ListTile(leading: const Icon(Icons.my_location), title: const Text('Start from my live position'), onTap: () {
              bloc.add(const LiveMapStartPinned(null));
              Navigator.of(ctx).pop();
            }),
        ]),
      ),
    );
  }
}

/// You-are-here with accuracy circle and heading, tweened between fixes (1 s; instant under reduced motion).
class _SelfLayer extends StatefulWidget {
  const _SelfLayer({required this.fix});
  final MapFix fix;
  @override
  State<_SelfLayer> createState() => _SelfLayerState();
}

class _SelfLayerState extends State<_SelfLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(seconds: 1), value: 1);
  late LatLng _from = LatLng(widget.fix.lat, widget.fix.lng);
  late LatLng _to = _from;

  @override
  void didUpdateWidget(covariant _SelfLayer old) {
    super.didUpdateWidget(old);
    final next = LatLng(widget.fix.lat, widget.fix.lng);
    if (next != _to) {
      _from = _now;
      _to = next;
      if (Motion.reduce(context)) {
        _t.value = 1;
      } else {
        _t.forward(from: 0);
      }
    }
  }

  LatLng get _now {
    final v = Curves.easeOut.transform(_t.value);
    return LatLng(_from.latitude + (_to.latitude - _from.latitude) * v, _from.longitude + (_to.longitude - _from.longitude) * v);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final f = widget.fix;
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) => Stack(children: [
        CircleLayer(circles: [CircleMarker(point: _now, radius: f.accuracyM.clamp(2, 80).toDouble(), useRadiusInMeter: true, color: c.positionBlue.withValues(alpha: 0.15), borderColor: c.positionBlue, borderStrokeWidth: 1)]),
        MarkerLayer(markers: [
          Marker(
            point: _now,
            width: 46,
            height: 46,
            child: Semantics(
              label: 'You are here',
              child: Stack(alignment: Alignment.center, children: [
                if (f.headingDeg != null) Transform.rotate(angle: f.headingDeg! * math.pi / 180, child: Align(alignment: Alignment.topCenter, child: Icon(Icons.navigation, size: 18, color: c.positionBlue))),
                Container(width: 22, height: 22, decoration: BoxDecoration(color: c.positionBlue, shape: BoxShape.circle, border: Border.all(color: Colors.white, width: 3), boxShadow: Shadows.level(2))),
              ]),
            ),
          ),
        ]),
      ]),
    );
  }
}

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

String _srcLabel(PositionSource s) => switch (s) { PositionSource.gps => 'GPS', PositionSource.fused => 'GPS + sensors', PositionSource.pdr => 'sensors only' };

/// Next manoeuvre (turn-by-turn on the selected route) or why there is no route yet.
class _TopCard extends StatelessWidget {
  const _TopCard({required this.state});
  final LiveMapState state;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final s = state;
    final sel = s.selected;
    IconData icon = Icons.my_location;
    String title;
    String sub;
    if (s.arrived) {
      icon = Icons.verified;
      title = 'You have reached ${s.target?.name ?? 'your destination'}';
      sub = 'Tell your supervisor where you are';
    } else if (s.target == null) {
      icon = Icons.flag_outlined;
      title = 'Choose a destination';
      sub = 'Tap an exit, refuge or aid point, or long-press the map';
    } else if (s.startNode == null) {
      icon = Icons.location_searching;
      title = s.outsideMine ? 'You are outside the mine' : 'Waiting for your position';
      sub = s.outsideMine ? 'Long-press the map and choose "Start from here" to plan' : 'Location permission and a GPS fix are needed, or pin a start';
    } else if (sel == null) {
      icon = Icons.block;
      title = 'No safe route to ${s.target!.name}';
      sub = 'Every way there is blocked or near a critical hazard. Pick another destination.';
    } else {
      final evac = sel.asEvacRoute;
      final steps = buildSteps(evac);
      final here = s.pinnedStart ?? s.fix?.point;
      final progress = here == null ? null : routeProgress(evac, here);
      final cur = progress == null || steps.isEmpty ? null : currentStep(steps, evac, progress);
      icon = cur == null ? Icons.directions_walk : _turnIcon(cur.step.turn);
      title = cur == null ? 'To ${sel.target.name}' : cur.step.text;
      final left = progress?.remainingM ?? sel.distanceM;
      sub = '${fmtDistance(left)} · ${fmtEta(left / ((s.fix?.speedMps ?? 0) > 0.3 ? s.fix!.speedMps! : defaultWalkMps))} to ${sel.target.name}';
    }
    final fix = s.fix;
    return GlassCard(
      blur: true,
      padding: const EdgeInsets.all(Space.md),
      child: Row(children: [
        Container(padding: const EdgeInsets.all(Space.sm), decoration: BoxDecoration(color: c.amber500, borderRadius: BorderRadius.circular(Radii.sm)), child: Icon(icon, color: c.ink900)),
        const SizedBox(width: Space.md),
        Expanded(
          child: Semantics(
            liveRegion: true,
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, style: t.titleMedium, maxLines: 2, overflow: TextOverflow.ellipsis),
              Text(sub, style: t.bodySmall?.copyWith(color: c.muted), maxLines: 2, overflow: TextOverflow.ellipsis),
              if (fix != null) Text('${_srcLabel(fix.source)} · ±${fix.accuracyM.round()} m${fix.tunnelId == null ? '' : ' · ${fix.tunnelId}'}${s.replans > 0 ? ' · re-planned ${s.replans}×' : ''}', style: t.labelSmall?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
        ),
      ]),
    );
  }
}

class _RoutesPanel extends StatelessWidget {
  const _RoutesPanel({required this.state, required this.wide, required this.onDestination});
  final LiveMapState state;
  final bool wide;
  final VoidCallback onDestination;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final s = state;
    final bloc = context.read<LiveMapBloc>();
    final dest = Row(children: [
      Expanded(child: Text(s.target == null ? 'No destination' : 'To ${s.target!.name}', style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis)),
      MgButton(label: 'Destination', icon: Icons.flag, kind: MgButtonKind.secondary, onPressed: onDestination),
    ]);
    final cards = [
      for (final r in s.routes) RouteCard(route: r, selected: r.key == s.selected?.key, speedMps: s.fix?.speedMps, width: wide ? null : 236, onTap: () => bloc.add(LiveMapRouteSelected(r.key))),
    ];
    if (wide) {
      return ColoredBox(
        color: c.bg,
        child: ListView(padding: const EdgeInsets.all(Space.lg), children: [
          dest,
          const SizedBox(height: Space.lg),
          Text('Routes', style: t.labelLarge?.copyWith(color: c.muted)),
          const SizedBox(height: Space.sm),
          if (cards.isEmpty) Text('Routes appear once a start and a destination are known.', style: t.bodySmall?.copyWith(color: c.muted)),
          for (final card in cards) Padding(padding: const EdgeInsets.only(bottom: Space.md), child: card),
          const SizedBox(height: Space.sm),
          Text('Long-press the map to go somewhere or to start from a point. Tunnels with dashes are unlit.', style: t.bodySmall?.copyWith(color: c.muted)),
        ]),
      );
    }
    return Material(
      color: c.bg,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(Space.lg, Space.md, 0, Space.md),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Padding(padding: const EdgeInsets.only(right: Space.lg), child: dest),
            const SizedBox(height: Space.sm),
            SizedBox(
              height: 150,
              child: cards.isEmpty
                  ? Align(alignment: Alignment.centerLeft, child: Text('Routes appear once a start and a destination are known.', style: t.bodySmall?.copyWith(color: c.muted)))
                  : ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.only(right: Space.lg), itemCount: cards.length, separatorBuilder: (_, _) => const SizedBox(width: Space.md), itemBuilder: (_, i) => cards[i]),
            ),
          ]),
        ),
      ),
    );
  }
}
