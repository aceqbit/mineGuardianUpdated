import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/animated_counter.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/skeleton.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/socket/socket_service.dart';
import '../bloc/leaderboard_bloc.dart';
import '../data/leaderboard_repository.dart';

class LeaderboardScreen extends StatelessWidget {
  const LeaderboardScreen({super.key, this.repository});
  final LeaderboardRepository? repository;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionBloc>().state;
    final user = session is SessionAuthenticated ? session.user : null;
    final role = user?.role ?? Role.miner;
    return BlocProvider(
      create: (ctx) => LeaderboardBloc(
        repo: repository ?? LeaderboardRepository(api: ctx.read<ApiClient>()),
        socket: ctx.read<SocketService>(),
        isMiner: role == Role.miner,
        isStaff: role != Role.miner,
      )..add(const LeaderboardStarted()),
      child: _View(myId: user?.id, staff: role != Role.miner, home: Routes.homeFor(role.wire)),
    );
  }
}

class _View extends StatefulWidget {
  const _View({required this.myId, required this.staff, required this.home});
  final String? myId;
  final bool staff;
  final String home;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  bool _supervisors = false;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go(widget.home)),
        title: const Text('Leaderboard'),
      ),
      body: BlocBuilder<LeaderboardBloc, LeaderboardState>(
        builder: (context, s) {
          if (s.loading) return const Padding(padding: EdgeInsets.all(Space.lg), child: SkeletonList(count: 6));
          if (s.error != null && s.workers.isEmpty) {
            return EmptyState(icon: Icons.cloud_off, title: 'Could not load', message: s.error, actionLabel: 'Retry', onAction: () => context.read<LeaderboardBloc>().add(const LeaderboardStarted()));
          }
          final rows = _supervisors ? s.supervisors : s.workers;
          return RefreshIndicator(
            onRefresh: () async => context.read<LeaderboardBloc>().add(const LeaderboardStarted()),
            child: ListView(
              padding: const EdgeInsets.all(Space.lg),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: Widths.form + 120),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      if (s.me != null) ...[_MyCard(me: s.me!), const SizedBox(height: Space.lg)],
                      if (widget.staff) ...[
                        SegmentedButton<bool>(
                          showSelectedIcon: false,
                          segments: const [ButtonSegment(value: false, label: Text('Workers')), ButtonSegment(value: true, label: Text('Supervisors'))],
                          selected: {_supervisors},
                          onSelectionChanged: (v) => setState(() => _supervisors = v.first),
                        ),
                        const SizedBox(height: Space.md),
                      ],
                      if (rows.length >= 5) ...[_Podium(rows: rows.take(3).toList(), myId: widget.myId), const SizedBox(height: Space.lg)],
                      if (rows.isEmpty)
                        const EmptyState(icon: Icons.leaderboard, title: 'No scores yet', message: 'Scores appear after reviewed check-ins.')
                      else
                        for (final r in (rows.length >= 5 ? rows.skip(3) : rows)) _RowTile(row: r, mine: r.userId == widget.myId, supervisor: _supervisors),
                    ]),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _MyCard extends StatelessWidget {
  const _MyCard({required this.me});
  final MyStanding me;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return MgCard(
      tone: c.amber50,
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Row(children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('Your rank', style: t.labelMedium?.copyWith(color: c.muted)),
              Text(me.rank == null ? '—' : '#${me.rank} of ${me.total}', style: t.headlineSmall),
            ]),
          ),
          Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
            Text('Score', style: t.labelMedium?.copyWith(color: c.muted)),
            AnimatedCounter(value: me.score, style: t.headlineSmall),
          ]),
        ]),
        const SizedBox(height: Space.md),
        Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
          StatusChip(label: '${me.streak}-day streak', icon: Icons.local_fire_department, tone: ChipTone.warning),
          StatusChip(label: '${me.xp} XP', icon: Icons.bolt, tone: ChipTone.info),
          for (final b in me.badges) StatusChip(label: badgeLabels[b] ?? b, icon: Icons.military_tech, tone: ChipTone.success),
        ]),
        if (me.gapToNext > 0) Padding(padding: const EdgeInsets.only(top: Space.sm), child: Text('${me.gapToNext} points to the next rank', style: t.bodySmall?.copyWith(color: c.muted))),
      ]),
    );
  }
}

class _RowTile extends StatelessWidget {
  const _RowTile({required this.row, required this.mine, required this.supervisor});
  final LeaderRow row;
  final bool mine, supervisor;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final medal = switch (row.rank) { 1 => c.medalGold, 2 => c.medalSilver, 3 => c.medalBronze, _ => null };
    return Container(
      key: ValueKey('lb-${row.userId}'),
      margin: const EdgeInsets.only(bottom: Space.sm),
      padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.md),
      decoration: BoxDecoration(color: mine ? c.amber50 : c.surface, border: Border.all(color: mine ? c.amber500 : c.border), borderRadius: BorderRadius.circular(Radii.card)),
      child: Row(children: [
        SizedBox(width: 36, child: medal != null ? Icon(Icons.emoji_events, color: medal) : Text('${row.rank}', style: Theme.of(context).textTheme.titleMedium, textAlign: TextAlign.center)),
        const SizedBox(width: Space.sm),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(mine ? '${row.name} (you)' : row.name, style: Theme.of(context).textTheme.titleSmall, maxLines: 1, overflow: TextOverflow.ellipsis),
            Text(supervisor ? '${row.xp} reviews decided' : '${row.streak}-day streak · ${row.xp} XP', style: Theme.of(context).textTheme.bodySmall?.copyWith(color: c.muted), maxLines: 1, overflow: TextOverflow.ellipsis),
          ]),
        ),
        Text('${row.score}', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
      ]),
    );
  }
}

/// Top three as podium bars that grow in. Order on screen: 2nd, 1st, 3rd.
class _Podium extends StatelessWidget {
  const _Podium({required this.rows, this.myId});
  final List<LeaderRow> rows;
  final String? myId;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final order = [rows[1], rows[0], rows[2]];
    final heights = {1: 112.0, 2: 84.0, 3: 64.0};
    final medals = {1: c.medalGold, 2: c.medalSilver, 3: c.medalBronze};
    return Semantics(
      label: 'Top three: ${rows.map((r) => '${r.rank} ${r.name} ${r.score}').join(', ')}',
      child: Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
        for (final r in order)
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.xs),
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Icon(Icons.emoji_events, color: medals[r.rank] ?? c.muted, size: r.rank == 1 ? 34 : 26),
                const SizedBox(height: Space.xs),
                Text(r.name, maxLines: 1, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: t.labelLarge),
                Text('${r.score}', style: t.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
                const SizedBox(height: Space.xs),
                TweenAnimationBuilder<double>(
                  tween: Tween(begin: 0, end: heights[r.rank] ?? 56),
                  duration: Motion.of(context, Motion.slower),
                  curve: Motion.easeOut,
                  builder: (context, h, _) => Container(
                    height: h,
                    alignment: Alignment.topCenter,
                    padding: const EdgeInsets.only(top: Space.sm),
                    decoration: BoxDecoration(color: r.userId == myId ? c.amber50 : c.surfaceTint, border: Border.all(color: medals[r.rank] ?? c.border, width: 2), borderRadius: const BorderRadius.vertical(top: Radius.circular(Radii.sm))),
                    child: Text('#${r.rank}', style: t.titleMedium?.copyWith(color: medals[r.rank])),
                  ),
                ),
              ]),
            ),
          ),
      ]),
    );
  }
}
