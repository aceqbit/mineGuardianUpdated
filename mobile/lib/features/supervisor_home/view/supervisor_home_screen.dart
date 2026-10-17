import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/app_scaffold.dart';
import '../../../app/ui/connection_banner.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/mg_hero_header.dart';
import '../../../app/ui/pulse_dot.dart';
import '../../../app/ui/section_header.dart';
import '../../../app/ui/skeleton.dart';
import '../../../app/ui/tile_art.dart';
import '../../../app/ui/toast.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/socket/socket_service.dart';
import '../../../core/time/ist.dart';
import '../bloc/supervisor_feed_bloc.dart';
import '../bloc/supervisor_feed_event.dart';
import '../bloc/supervisor_feed_state.dart';
import '../data/feed_repository.dart';
import '../data/models/feed_item.dart';
import '../widgets/checkin_card.dart';
import '../widgets/close_note_sheet.dart';
import '../widgets/feed_filters.dart';
import '../widgets/hazard_card.dart';
import '../widgets/kpi_strip.dart';
import '../widgets/quick_actions.dart';
import '../widgets/sos_card.dart';
import '../widgets/worker_detail_sheet.dart';
import '../widgets/workers_page.dart';
import '../widgets/zone_pulse.dart';

class SupervisorHomeScreen extends StatelessWidget {
  const SupervisorHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionBloc>().state;
    if (s is! SessionAuthenticated) return const SizedBox.shrink();
    return BlocProvider(
      create: (ctx) => SupervisorFeedBloc(repo: FeedRepository(api: ctx.read<ApiClient>()), socket: ctx.read<SocketService>())..add(const FeedStarted()),
      child: _View(shiftLabel: s.user.shift == null ? '' : 'Shift ${s.user.shift!.wire} · ${s.user.shift!.window}'),
    );
  }
}

class _View extends StatefulWidget {
  const _View({required this.shiftLabel});
  final String shiftLabel;

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  /// 0 = Live Feed, 1 = Workers. Two different pages on every screen size.
  int _tab = 0;

  void _nav(int i) {
    if (i == 0 || i == 1) {
      setState(() => _tab = i);
    } else if (i == 2) {
      context.go(Routes.leaderboard);
    } else {
      context.go(Routes.rewards);
    }
  }

  Future<void> _hazardAction(HazardFeed h, HazardStatus status) async {
    final bloc = context.read<SupervisorFeedBloc>();
    String? note;
    if (status == HazardStatus.closed || status == HazardStatus.rejected) {
      note = await showCloseNoteSheet(context, action: status);
      if (note == null) return;
    }
    bloc.add(HazardActionRequested(h.id, status, note: note));
  }

  void _reviewNext(SupervisorFeedState s) {
    final next = s.checkins.where((c) => c.review?.decided != true).firstOrNull;
    if (next == null) {
      Toast.show(context, 'Nothing is waiting for your review');
      return;
    }
    context.push(Routes.review(next.id));
  }

  Widget _feedList(SupervisorFeedState s) {
    final items = s.items;
    if (s.status == FeedStatus.loading) return const SkeletonList(count: 4, itemHeight: 104);
    if (items.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(vertical: Space.x3),
        child: EmptyState(icon: Icons.inbox, title: 'Nothing yet', message: 'Check-ins, hazards and SOS alerts from your zone appear here live'),
      );
    }
    return Column(children: [
      for (var i = 0; i < items.length; i++)
        Padding(
          key: ValueKey(items[i].id),
          padding: const EdgeInsets.only(bottom: Space.md),
          child: _Entrance(
            child: switch (items[i]) {
              SosFeed s2 => SosCard(item: s2, onOpenCrisis: () => context.go(Routes.crisisView)),
              CheckinFeed c => CheckinCard(item: c, onOpen: () => context.push(Routes.review(c.id))),
              HazardFeed h => HazardCard(
                  item: h,
                  onOpen: () => context.push(Routes.hazardDetail(h.id), extra: h),
                  onAcknowledge: () => _hazardAction(h, HazardStatus.acknowledged),
                  onClose: () => _hazardAction(h, HazardStatus.closed),
                  onReject: () => _hazardAction(h, HazardStatus.rejected),
                ),
            },
          ),
        ),
    ]);
  }

  Widget _liveFeed(SupervisorFeedState s, bool expanded) {
    final feed = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader(title: 'Live feed', subtitle: 'Check-ins, hazards and SOS from your zone, newest first'),
      FeedFilters(value: s.filter, onChanged: (f) => context.read<SupervisorFeedBloc>().add(FeedFilterChanged(f))),
      const SizedBox(height: Space.lg),
      _feedList(s),
    ]);
    if (!expanded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [ZonePulse(workers: s.workers), const SizedBox(height: Space.x2), feed]);
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      Expanded(flex: 3, child: feed),
      const SizedBox(width: Space.x2),
      Expanded(flex: 2, child: ZonePulse(workers: s.workers)),
    ]);
  }

  Widget _workers(SupervisorFeedState s) {
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      SectionHeader(title: 'Workers', subtitle: '${s.checkedIn} of ${s.workers.length} checked in today · tap a worker for details'),
      WorkersPage(
        workers: s.workers,
        onOpenWorker: (w) => showWorkerDetail(context, worker: w, checkins: s.checkins, onOpenCheckin: (id) => context.push(Routes.review(id))),
      ),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final socket = context.read<SocketService>();
    final expanded = context.isExpanded;
    return BlocConsumer<SupervisorFeedBloc, SupervisorFeedState>(
      listenWhen: (a, b) => a.alertSeq != b.alertSeq || (b.error != null && a.error != b.error),
      listener: (context, s) {
        if (s.error != null) {
          Toast.show(context, s.error!, kind: ToastKind.error);
          context.read<SupervisorFeedBloc>().add(const FeedErrorShown());
        } else {
          HapticFeedback.mediumImpact();
        }
      },
      builder: (context, s) {
        final kpis = KpiStrip(items: [
          KpiData(label: 'Checked in today', value: '${s.checkedIn} / ${s.workers.length}', icon: Icons.how_to_reg),
          KpiData(label: 'Awaiting review', value: '${s.awaitingReview}', icon: Icons.pending_actions, tone: s.awaitingReview > 0 ? c.warning : null),
          KpiData(label: 'Open hazards', value: '${s.openHazards}', icon: Icons.warning_amber, tone: s.openHazards > 0 ? c.danger : null),
          KpiData(label: 'Active SOS', value: '${s.sos.length}', icon: Icons.sos, tone: s.sos.isNotEmpty ? c.crisis : null),
        ]);
        final header = MgHeroHeader(
          eyebrow: greetingFor(nowIst()).toUpperCase(),
          title: s.zoneCode.isEmpty ? 'Your zone' : '${s.zoneCode} · ${s.zoneName}',
          subtitle: widget.shiftLabel.isEmpty ? null : widget.shiftLabel,
          art: TileArtKind.supervisorFeed,
          trailing: StreamBuilder<bool>(
            stream: socket.connection$,
            initialData: socket.isConnected,
            builder: (context, snap) {
              final up = snap.data == true;
              return Row(mainAxisSize: MainAxisSize.min, children: [
                PulseDot(color: up ? c.success : c.slate400, pulsing: up),
                const SizedBox(width: Space.xs),
                Text(up ? 'LIVE' : 'OFFLINE', style: t.labelMedium?.copyWith(color: Colors.white)),
              ]);
            },
          ),
        );
        final actions = QuickActions(actions: [
          QuickAction(icon: Icons.rate_review, label: 'Review next', badge: s.awaitingReview, onTap: () => _reviewNext(s)),
          QuickAction(icon: Icons.crisis_alert, label: 'Crisis view', tone: s.sos.isNotEmpty ? c.crisis : c.danger, onTap: () => context.go(Routes.crisisView)),
          QuickAction(icon: Icons.badge, label: 'Profiles', onTap: () => context.go(Routes.supervisorProfiles)),
          QuickAction(icon: Icons.leaderboard, label: 'Leaderboard', onTap: () => context.go(Routes.leaderboard)),
          QuickAction(icon: Icons.emoji_events, label: 'Rewards', onTap: () => context.go(Routes.rewards)),
          QuickAction(icon: Icons.refresh, label: 'Refresh', onTap: () => context.read<SupervisorFeedBloc>().add(const FeedRefreshed())),
        ]);

        final Widget body;
        if (s.status == FeedStatus.failure) {
          body = EmptyState(icon: Icons.cloud_off, title: 'Could not load your feed', message: 'Check your connection', actionLabel: 'Retry', onAction: () => context.read<SupervisorFeedBloc>().add(const FeedStarted()));
        } else {
          body = RefreshIndicator(
            onRefresh: () async => context.read<SupervisorFeedBloc>().add(const FeedRefreshed()),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              child: ContentWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  header,
                  const SizedBox(height: Space.lg),
                  actions,
                  const SizedBox(height: Space.lg),
                  kpis,
                  const SizedBox(height: Space.x2),
                  KeyedSubtree(key: ValueKey(_tab), child: _tab == 0 ? _liveFeed(s, expanded) : _workers(s)),
                ]),
              ),
            ),
          );
        }

        return AppScaffold(
          title: 'Supervisor',
          selectedIndex: _tab,
          onSelect: _nav,
          destinations: const [
            NavDest(label: 'Live Feed', icon: Icons.dynamic_feed),
            NavDest(label: 'Workers', icon: Icons.groups),
            NavDest(label: 'Leaderboard', icon: Icons.leaderboard),
            NavDest(label: 'Rewards', icon: Icons.emoji_events),
          ],
          banner: ConnectionBanner(connected: socket.connection$),
          actions: [IconButton(tooltip: 'Log out', icon: const Icon(Icons.logout), onPressed: () => context.read<SessionBloc>().add(const LoggedOut()))],
          body: body,
        );
      },
    );
  }
}

/// New items slide in from the top.
class _Entrance extends StatefulWidget {
  const _Entrance({required this.child});
  final Widget child;

  @override
  State<_Entrance> createState() => _EntranceState();
}

class _EntranceState extends State<_Entrance> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: Motion.slow);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (Motion.reduce(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SizeTransition(
        sizeFactor: CurvedAnimation(parent: _c, curve: Motion.easeOut),
        alignment: Alignment.topCenter,
        child: FadeTransition(opacity: _c, child: widget.child),
      );
}
