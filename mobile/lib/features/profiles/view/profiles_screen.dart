import 'package:animations/animations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/mg_text_field.dart';
import '../../../app/ui/page_hero.dart';
import '../../../app/ui/pulse_on_change.dart';
import '../../../app/ui/role_accent.dart';
import '../../../app/ui/section_header.dart';
import '../../../app/ui/skeleton.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/socket/socket_service.dart';
import '../bloc/profiles_bloc.dart';
import '../data/profile_models.dart';
import '../data/profiles_repository.dart';
import '../widgets/profile_card_tile.dart';
import '../widgets/profile_visuals.dart';
import 'profile_detail_screen.dart';

/// Profile manager (CLAUDE.md section 23.2): one screen, scoped by the viewer's role on the server.
/// Miner: own profile + crew. Supervisor: own zone's miners. Admin: everyone, with role tabs.
class ProfilesScreen extends StatelessWidget {
  const ProfilesScreen({super.key, this.repository});
  final ProfilesRepository? repository;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionBloc>().state;
    final user = session is SessionAuthenticated ? session.user : null;
    final role = user?.role ?? Role.miner;
    final repo = repository ?? ProfilesRepository(api: context.read<ApiClient>());
    return RepositoryProvider.value(
      value: repo,
      child: BlocProvider(
        create: (ctx) => ProfilesBloc(repo: repo, socket: ctx.read<SocketService>(), viewerId: user?.id ?? '', viewerRole: role)..add(const ProfilesStarted()),
        child: _View(role: role, myId: user?.id ?? '', zoneCode: user?.zoneCode),
      ),
    );
  }
}

class _View extends StatefulWidget {
  const _View({required this.role, required this.myId, this.zoneCode});
  final Role role;
  final String myId;
  final String? zoneCode;
  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  late final TextEditingController _search;

  @override
  void initState() {
    super.initState();
    _search = TextEditingController();
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  String get _title => switch (widget.role) {
        Role.miner => 'My crew',
        Role.supervisor => widget.zoneCode == null ? 'My team' : 'Team · ${widget.zoneCode}',
        Role.admin => 'People',
      };

  @override
  Widget build(BuildContext context) {
    final staff = widget.role != Role.miner;
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go(Routes.homeFor(widget.role.wire))),
        title: const Text('Profiles'),
      ),
      body: BlocBuilder<ProfilesBloc, ProfilesState>(
        builder: (context, s) {
          final bloc = context.read<ProfilesBloc>();
          final me = s.items.where((c) => c.id == widget.myId).firstOrNull;
          final others = s.visible.where((c) => c.id != widget.myId).toList();
          final live = s.items.where((c) => c.presence == Presence.live).length;
          return RefreshIndicator(
            onRefresh: () async => bloc.add(const ProfilesStarted()),
            child: ListView(
              padding: const EdgeInsets.only(top: Space.lg, bottom: Space.x4),
              children: [
                ContentWidth(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    PageHero(
                      role: widget.role,
                      icon: Icons.badge,
                      title: _title,
                      subtitle: s.status == ProfilesStatus.loading ? 'Loading people…' : '${s.total} ${s.total == 1 ? 'person' : 'people'}${staff ? ' · $live live now' : ''} · updates live',
                      bottom: MgTextField(controller: _search, hint: 'Search by name or employee ID', prefix: const Icon(Icons.search), onChanged: (v) => bloc.add(ProfilesQueryChanged(v))),
                    ),
                    const SizedBox(height: Space.lg),
                    if (widget.role == Role.admin) ...[
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: SegmentedButton<Role?>(
                          showSelectedIcon: false,
                          segments: const [
                            ButtonSegment(value: null, label: Text('All')),
                            ButtonSegment(value: Role.miner, label: Text('Miners')),
                            ButtonSegment(value: Role.supervisor, label: Text('Supervisors')),
                            ButtonSegment(value: Role.admin, label: Text('Admins')),
                          ],
                          selected: {s.roleTab},
                          onSelectionChanged: (v) => bloc.add(ProfilesRoleTabChanged(v.first)),
                        ),
                      ),
                      const SizedBox(height: Space.md),
                    ],
                    if (staff && s.items.any((c) => c.riskBand != null)) ...[
                      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
                        for (final b in RiskBand.values)
                          FilterChip(label: Text('${bandLabel(b)} · ${s.countBand(b)}'), selected: s.band == b, onSelected: (_) => bloc.add(ProfilesBandChanged(b))),
                      ]),
                      const SizedBox(height: Space.lg),
                    ],
                    if (s.status == ProfilesStatus.loading)
                      const SkeletonList(count: 4)
                    else if (s.status == ProfilesStatus.failure)
                      EmptyState(icon: Icons.cloud_off, title: 'Could not load profiles', message: s.error, actionLabel: 'Retry', onAction: () => bloc.add(const ProfilesStarted()))
                    else ...[
                      if (me != null && widget.role == Role.miner) ...[
                        const SectionHeader(title: 'You'),
                        _OpenCard(card: me, isMe: true, pulse: s.pulse[me.id], role: widget.role),
                        const SizedBox(height: Space.x2),
                        SectionHeader(title: 'Your crew', subtitle: '${others.length} in ${me.zone?.code ?? 'your zone'}'),
                      ],
                      if (others.isEmpty && (me == null || widget.role != Role.miner))
                        EmptyState(icon: Icons.groups, title: s.query.isEmpty ? 'Nobody here yet' : 'No match', message: s.query.isEmpty ? 'People appear here as soon as they are registered.' : 'Try another name or employee ID.')
                      else
                        AdaptiveGrid(
                          minTileWidth: 300,
                          maxColumns: 3,
                          fixedTileHeight: profileCardHeight,
                          children: [
                            for (final card in (widget.role == Role.miner ? others : s.visible))
                              _OpenCard(card: card, isMe: card.id == widget.myId, pulse: s.pulse[card.id], role: widget.role),
                          ],
                        ),
                    ],
                  ]),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

/// Card -> detail container transform (animations package). Instant under reduced motion.
class _OpenCard extends StatelessWidget {
  const _OpenCard({required this.card, required this.isMe, required this.pulse, required this.role});
  final ProfileCard card;
  final bool isMe;
  final int? pulse;
  final Role role;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final repo = context.read<ProfilesRepository>();
    final accent = isMe ? RoleAccent.of(context, role).fill : null;
    return PulseOnChange(
      pulseKey: pulse,
      child: SizedBox(
        height: profileCardHeight,
        child: OpenContainer(
          transitionDuration: Motion.reduce(context) ? const Duration(milliseconds: 1) : Motion.slower,
          closedElevation: 0,
          openElevation: 0,
          closedColor: Colors.transparent,
          middleColor: c.bg,
          openColor: c.bg,
          closedShape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.card)),
          tappable: false,
          closedBuilder: (ctx, open) => ProfileCardTile(card: card, isMe: isMe, accent: accent, onTap: open),
          openBuilder: (ctx, _) => ProfileDetailScreen(userId: card.id, repository: repo, initial: card),
        ),
      ),
    );
  }
}
