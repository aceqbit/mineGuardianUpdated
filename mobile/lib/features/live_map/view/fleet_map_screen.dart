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
import '../../../app/ui/pulse_dot.dart';
import '../../../app/ui/skeleton.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/db/cache_repository.dart';
import '../../../core/socket/socket_service.dart';
import '../../../core/time/ist.dart';
import '../../profiles/data/profiles_repository.dart';
import '../../profiles/widgets/profile_visuals.dart';
import '../../voice_call/widgets/ai_call_button.dart';
import '../bloc/fleet_bloc.dart';
import '../data/live_map_repository.dart';
import '../widgets/map_launch.dart';
import '../widgets/mine_base_map.dart';

String _src(PositionSource s) => switch (s) { PositionSource.gps => 'GPS', PositionSource.fused => 'GPS + sensors', PositionSource.pdr => 'sensors only' };

/// `/admin/live-map` and `/supervisor/live-map` (CLAUDE.md section 23.4): every tracked person the server lets this
/// viewer see, moving live. A supervisor only ever receives their own zone.
class FleetMapScreen extends StatelessWidget {
  const FleetMapScreen({super.key, this.repository, this.profiles});
  final LiveMapRepository? repository;
  final ProfilesRepository? profiles;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionBloc>().state;
    final role = session is SessionAuthenticated ? session.user.role : Role.supervisor;
    final repo = repository ?? LiveMapRepository(api: context.read<ApiClient>(), cache: context.read<CacheRepository>());
    return BlocProvider(
      create: (ctx) => FleetBloc(repo: repo, profiles: profiles ?? ProfilesRepository(api: ctx.read<ApiClient>()), socket: ctx.read<SocketService>())..add(const FleetStarted()),
      child: _View(role: role, repo: repo),
    );
  }
}

class _View extends StatefulWidget {
  const _View({required this.role, required this.repo});
  final Role role;
  final LiveMapRepository repo;
  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  final _map = MapController();
  Map<String, String> _zones = const {};

  @override
  void initState() {
    super.initState();
    if (widget.role == Role.admin) {
      widget.repo.zones().then((z) {
        if (mounted) setState(() => _zones = z);
      });
    }
  }

  @override
  void dispose() {
    _map.dispose();
    super.dispose();
  }

  void _focus(FleetPerson p) {
    try {
      _map.move(toLatLng(p.now.fix.point), math.max(_map.camera.zoom, 18));
    } catch (_) {/* map not attached yet */}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go(Routes.homeFor(widget.role.wire))),
        title: const Text('Live map'),
      ),
      body: MapLaunchOverlay(
        child: BlocConsumer<FleetBloc, FleetState>(
          listenWhen: (a, b) => a.selectedId != b.selectedId && b.selectedId != null,
          listener: (context, s) {
            final p = s.people[s.selectedId];
            if (p != null) _focus(p);
          },
          builder: (context, s) {
            switch (s.status) {
              case FleetStatus.loading:
                return const Padding(padding: EdgeInsets.all(Space.lg), child: SkeletonList(count: 3));
              case FleetStatus.noLayout:
                return EmptyState(icon: Icons.map_outlined, title: 'No mine layout on the server', message: 'Run npm run seed:layout on the backend, then retry.', actionLabel: 'Retry', onAction: () => context.read<FleetBloc>().add(const FleetStarted()));
              case FleetStatus.failure:
              case FleetStatus.ready:
                return _readyView(context, s);
            }
          },
        ),
      ),
    );
  }

  Widget _readyView(BuildContext context, FleetState s) {
    final c = MgColors.of(context);
    final wide = context.sizeClass == SizeClass.expanded;
    final bloc = context.read<FleetBloc>();
    final people = s.visible;
    final sos = people.where((p) => p.now.sosId != null).length;
    final header = Wrap(spacing: Space.sm, runSpacing: Space.sm, crossAxisAlignment: WrapCrossAlignment.center, children: [
      StatusChip(label: '${s.count(Presence.live)} live', tone: ChipTone.success, icon: Icons.sensors),
      StatusChip(label: '${s.count(Presence.stale)} stale', tone: ChipTone.warning),
      StatusChip(label: '${s.count(Presence.offline)} offline'),
      if (sos > 0) StatusChip(label: '$sos SOS', tone: ChipTone.crisis),
      if (widget.role == Role.admin && _zones.isNotEmpty)
        for (final z in [null, ..._zones.keys])
          ChoiceChip(label: Text(z == null ? 'Whole mine' : _zones[z]!), selected: s.zoneId == z, onSelected: (_) => bloc.add(FleetZoneChanged(z))),
    ]);
    final map = Stack(children: [
      Positioned.fill(
        child: MineBaseMap(
          layout: s.layout!,
          controller: _map,
          fitPoints: [for (final p in people) p.now.fix.point],
          layers: [_FleetLayer(people: people, batch: s.batch, selectedId: s.selectedId, onTap: (id) => bloc.add(FleetPersonSelected(id)))],
        ),
      ),
      Positioned(left: Space.md, right: Space.md, top: Space.md, child: GlassCard(blur: true, padding: const EdgeInsets.all(Space.md), child: header)),
      if (s.selectedId != null && s.people[s.selectedId] != null)
        Positioned(left: Space.md, right: Space.md, bottom: wide ? Space.md : Space.md, child: Center(child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: Widths.form), child: _PersonCard(state: s, person: s.people[s.selectedId]!)))),
    ]);
    final list = _PeopleList(people: people, selectedId: s.selectedId, onTap: (id) => bloc.add(FleetPersonSelected(id)), horizontal: !wide);
    if (wide) {
      return Row(children: [
        SizedBox(width: 340, child: ColoredBox(color: c.bg, child: list)),
        VerticalDivider(width: 1, color: c.border),
        Expanded(child: map),
      ]);
    }
    return Column(children: [Expanded(child: map), SizedBox(height: 104, child: ColoredBox(color: c.bg, child: list))]);
  }
}

/// Markers tween from their last drawn position to the new one over 1 s each batch; 60 s trails behind them.
class _FleetLayer extends StatefulWidget {
  const _FleetLayer({required this.people, required this.batch, required this.selectedId, required this.onTap});
  final List<FleetPerson> people;
  final int batch;
  final String? selectedId;
  final ValueChanged<String> onTap;
  @override
  State<_FleetLayer> createState() => _FleetLayerState();
}

class _FleetLayerState extends State<_FleetLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _t = AnimationController(vsync: this, duration: const Duration(seconds: 1), value: 1);
  Map<String, LatLng> _from = {};
  Map<String, LatLng> _to = {};

  @override
  void initState() {
    super.initState();
    _to = {for (final p in widget.people) p.now.userId: toLatLng(p.now.fix.point)};
    _from = _to;
  }

  @override
  void didUpdateWidget(covariant _FleetLayer old) {
    super.didUpdateWidget(old);
    if (old.batch == widget.batch) return;
    _from = {for (final e in _to.entries) e.key: _at(e.key) ?? e.value};
    _to = {for (final p in widget.people) p.now.userId: toLatLng(p.now.fix.point)};
    if (Motion.reduce(context)) {
      _t.value = 1;
    } else {
      _t.forward(from: 0);
    }
  }

  LatLng? _at(String id) {
    final to = _to[id];
    if (to == null) return null;
    final from = _from[id] ?? to;
    final v = Curves.easeInOut.transform(_t.value);
    return LatLng(from.latitude + (to.latitude - from.latitude) * v, from.longitude + (to.longitude - from.longitude) * v);
  }

  @override
  void dispose() {
    _t.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return AnimatedBuilder(
      animation: _t,
      builder: (context, _) => Stack(children: [
        PolylineLayer(polylines: [
          for (final p in widget.people)
            if (p.trail.length > 1) Polyline(points: [...p.trail.map((x) => toLatLng(x.$1)), ?_at(p.now.userId)], strokeWidth: 3, color: presenceColor(c, p.now.presence).withValues(alpha: 0.45)),
        ]),
        MarkerLayer(markers: [
          for (final p in widget.people)
            if (_at(p.now.userId) != null)
              Marker(
                point: _at(p.now.userId)!,
                width: 44,
                height: 44,
                child: Semantics(
                  button: true,
                  label: '${p.now.name}, ${presenceLabel(p.now.presence)}${p.now.sosId != null ? ', SOS' : ''}',
                  child: GestureDetector(
                    onTap: () => widget.onTap(p.now.userId),
                    child: Stack(alignment: Alignment.center, children: [
                      if (p.now.sosId != null) PulseDot(color: c.danger, size: 20),
                      if (p.now.fix.headingDeg != null && p.now.presence == Presence.live)
                        Transform.rotate(angle: p.now.fix.headingDeg! * math.pi / 180, child: Align(alignment: Alignment.topCenter, child: Icon(Icons.navigation, size: 14, color: presenceColor(c, p.now.presence)))),
                      Container(
                        width: p.now.userId == widget.selectedId ? 26 : 20,
                        height: p.now.userId == widget.selectedId ? 26 : 20,
                        decoration: BoxDecoration(color: p.now.sosId != null ? c.dangerFill : presenceColor(c, p.now.presence), shape: BoxShape.circle, border: Border.all(color: p.now.userId == widget.selectedId ? c.amber500 : Colors.white, width: 3), boxShadow: Shadows.level(2)),
                      ),
                    ]),
                  ),
                ),
              ),
        ]),
      ]),
    );
  }
}

class _PeopleList extends StatelessWidget {
  const _PeopleList({required this.people, required this.selectedId, required this.onTap, required this.horizontal});
  final List<FleetPerson> people;
  final String? selectedId;
  final ValueChanged<String> onTap;
  final bool horizontal;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    if (people.isEmpty) {
      return Center(child: Padding(padding: const EdgeInsets.all(Space.lg), child: Text('Nobody is sharing a location yet. Miners appear here once their live tracking starts.', textAlign: TextAlign.center, style: t.bodySmall?.copyWith(color: c.muted))));
    }
    Widget tile(FleetPerson p) {
      final f = p.now.fix;
      return InkWell(
        onTap: () => onTap(p.now.userId),
        borderRadius: BorderRadius.circular(Radii.card),
        child: Container(
          width: horizontal ? 220 : null,
          padding: const EdgeInsets.all(Space.md),
          decoration: BoxDecoration(color: p.now.userId == selectedId ? c.amber50 : c.surface, borderRadius: BorderRadius.circular(Radii.card), border: Border.all(color: c.border)),
          child: Row(children: [
            PulseDot(color: p.now.sosId != null ? c.danger : presenceColor(c, p.now.presence), size: 8, pulsing: p.now.presence == Presence.live),
            const SizedBox(width: Space.sm),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(p.now.name, style: t.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
                Text('${p.now.employeeId} · ${_src(f.source)}${f.tunnelId == null ? '' : ' · ${f.tunnelId}'}', style: t.labelSmall?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
                Text(p.now.sosId != null ? 'SOS active' : '${presenceLabel(p.now.presence)} · ${relativeTime(f.ts)}', style: t.labelSmall?.copyWith(color: p.now.sosId != null ? c.danger : c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
              ]),
            ),
          ]),
        ),
      );
    }

    if (horizontal) {
      return ListView.separated(scrollDirection: Axis.horizontal, padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm), itemCount: people.length, separatorBuilder: (_, _) => const SizedBox(width: Space.sm), itemBuilder: (_, i) => tile(people[i]));
    }
    return ListView.separated(padding: const EdgeInsets.all(Space.lg), itemCount: people.length, separatorBuilder: (_, _) => const SizedBox(height: Space.sm), itemBuilder: (_, i) => tile(people[i]));
  }
}

class _PersonCard extends StatelessWidget {
  const _PersonCard({required this.state, required this.person});
  final FleetState state;
  final FleetPerson person;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final p = state.selectedProfile;
    final f = person.now.fix;
    return GlassCard(
      blur: true,
      padding: const EdgeInsets.all(Space.md),
      child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          ProfileAvatar(name: person.now.name, photoUrl: p?.photo?.url, size: 44, presence: person.now.presence, ring: p == null ? null : todayRing(c, p.today)),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(person.now.name, style: t.titleMedium, maxLines: 1, overflow: TextOverflow.ellipsis),
              Text('${person.now.employeeId}${p?.zone == null ? '' : ' · ${p!.zone!.code}'}${p?.designation == null ? '' : ' · ${p!.designation}'}', style: t.bodySmall?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
            ]),
          ),
          IconButton(tooltip: 'Close', icon: const Icon(Icons.close), onPressed: () => context.read<FleetBloc>().add(const FleetPersonSelected(null))),
        ]),
        const SizedBox(height: Space.sm),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          StatusChip(label: '${presenceLabel(person.now.presence)} · ${relativeTime(f.ts)}', tone: person.now.presence == Presence.live ? ChipTone.success : ChipTone.neutral),
          StatusChip(label: '${_src(f.source)} ±${f.accuracyM.round()} m', icon: Icons.my_location),
          if (f.tunnelId != null) StatusChip(label: f.tunnelId!, icon: Icons.linear_scale),
          if (f.speedMps != null) StatusChip(label: '${f.speedMps!.toStringAsFixed(1)} m/s', icon: Icons.directions_walk),
          if (p?.today != null) StatusChip(label: todayLabel(p!.today), tone: todayTone(p.today)),
          if (p?.riskBand != null) StatusChip(label: 'Risk ${bandLabel(p!.riskBand!)}', tone: bandTone(p.riskBand!)),
          if (person.now.sosId != null) const StatusChip(label: 'SOS active', tone: ChipTone.crisis),
        ]),
        const SizedBox(height: Space.md),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          MgButton(label: 'AI call', icon: Icons.support_agent, onPressed: () => showAiCallSheet(context, targetType: 'user', targetId: person.now.userId, targetLabel: person.now.name, reason: person.now.sosId != null ? 'SOS' : null)),
          MgButton(label: 'Open profile', icon: Icons.badge, kind: MgButtonKind.secondary, onPressed: () => context.push(Routes.profile(person.now.userId))),
        ]),
      ]),
    );
  }
}
