import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_images.dart';
import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/app_scaffold.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/media_tile.dart';
import '../../../app/ui/section_header.dart';
import '../../../app/ui/sync_indicator.dart';
import '../../../core/sync/sync_engine.dart';
import '../../live_map/widgets/live_tracking_pill.dart';
import '../../safety_feed/widgets/safety_bar.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/db/cache_repository.dart';
import '../../../core/db/layout_repository.dart';
import '../../../core/models/session_user.dart';
import '../../../core/socket/socket_service.dart';
import '../bloc/worker_home_bloc.dart';
import '../bloc/worker_home_event.dart';
import '../bloc/worker_home_state.dart';
import '../data/worker_repository.dart';
import '../widgets/recent_checkins.dart';
import '../widgets/worker_hero.dart';
import '../widgets/sos_button.dart';
import '../widgets/stats_strip.dart';

class WorkerHomeScreen extends StatelessWidget {
  const WorkerHomeScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final session = context.watch<SessionBloc>().state;
    if (session is! SessionAuthenticated) return const SizedBox.shrink();
    return BlocProvider(
      create: (ctx) => WorkerHomeBloc(repo: WorkerRepository(api: ctx.read<ApiClient>()), socket: ctx.read<SocketService>(), userId: session.user.id)..add(const WorkerHomeStarted()),
      child: _WorkerHomeView(user: session.user),
    );
  }
}

class _WorkerHomeView extends StatefulWidget {
  const _WorkerHomeView({required this.user});
  final dynamic user;

  @override
  State<_WorkerHomeView> createState() => _WorkerHomeViewState();
}

class _WorkerHomeViewState extends State<_WorkerHomeView> with WidgetsBindingObserver {
  /// Keeps the evacuation map, supervisors and profile on the phone so the SOS screen works with no connection.
  Future<void> _warmOfflineCache() async {
    try {
      final repo = LayoutRepository(api: context.read<ApiClient>(), cache: context.read<CacheRepository>());
      final user = widget.user as SessionUser;
      await repo.cacheSupervisors([for (final s in user.zoneSupervisors) s.toJson()]);
      await repo.cacheProfile({'id': user.id, 'fullName': user.fullName, 'zoneCode': user.zoneCode, 'zoneName': user.zoneName, 'shift': user.shift?.wire});
      await repo.refresh();
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _warmOfflineCache();
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && mounted) {
      context.read<WorkerHomeBloc>().add(const WorkerHomeRefreshed());
      _warmOfflineCache();
    }
  }

  void _nav(int i) {
    switch (i) {
      case 1:
        context.go(Routes.workerHazard);
      case 2:
        context.go(Routes.leaderboard);
      case 3:
        context.go(Routes.rewards);
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = widget.user;
    final socket = context.read<SocketService>();
    final compact = context.isCompact;
    final sos = SosButton(size: compact ? 72 : 52, onTriggered: () => context.go(Routes.workerSos, extra: true));
    return AppScaffold(
      title: 'Worker home',
      selectedIndex: 0,
      onSelect: _nav,
      destinations: const [
        NavDest(label: 'Home', icon: Icons.home),
        NavDest(label: 'Report Hazard', icon: Icons.warning_amber),
        NavDest(label: 'Leaderboard', icon: Icons.leaderboard),
        NavDest(label: 'Rewards', icon: Icons.emoji_events),
      ],
      actions: [const LiveTrackingPill(), SyncIndicator(engine: context.read<SyncEngine>()), if (!compact) Padding(padding: const EdgeInsets.only(right: Space.md, left: Space.md), child: sos)],
      floatingActionButton: compact ? sos : null,
      // Add-on X6: the daily safety bar sits under the page, above the navigation.
      body: Column(children: [Expanded(child: BlocBuilder<WorkerHomeBloc, WorkerHomeState>(builder: (context, s) {
        if (s.status == WorkerHomeStatus.failure) {
          return EmptyState(icon: Icons.cloud_off, title: 'Could not load', message: 'Pull down to try again', actionLabel: 'Retry', onAction: () => context.read<WorkerHomeBloc>().add(const WorkerHomeStarted()));
        }
        return RefreshIndicator(
          onRefresh: () async => context.read<WorkerHomeBloc>().add(const WorkerHomeRefreshed()),
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.only(top: Space.lg, bottom: 96),
            children: [
              ContentWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  WorkerHero(user: user, connected: socket.connection$, stats: s.stats),
                  const SizedBox(height: Space.x2),
                  StatsStrip(stats: s.stats, flash: s.statsFlash),
                  const SizedBox(height: Space.x2),
                  const SectionHeader(title: 'Actions'),
                  AdaptiveGrid(children: [
                    MediaTile(imageUrl: AppImages.capture, icon: Icons.photo_camera, title: 'Capture Shift Photo', subtitle: s.captureSubtitle, onTap: () => context.go(Routes.workerCapture)),
                    MediaTile(imageUrl: AppImages.hazard, icon: Icons.warning_amber, title: 'Report Hazard', subtitle: 'Photo, category, location', onTap: () => context.go(Routes.workerHazard)),
                    MediaTile(imageUrl: AppImages.leaderboard, icon: Icons.leaderboard, title: 'Leaderboard', subtitle: 'Live safety ranking', onTap: () => context.go(Routes.leaderboard)),
                    MediaTile(imageUrl: AppImages.rewards, icon: Icons.emoji_events, title: 'Rewards', subtitle: 'Honours and badges', onTap: () => context.go(Routes.rewards)),
                    MediaTile(imageUrl: AppImages.adminZones, icon: Icons.map, title: 'Live map', subtitle: 'Destinations and 4 route types', onTap: () => context.go(Routes.workerMap)),
                    MediaTile(imageUrl: AppImages.supervisorFeed, icon: Icons.badge, title: 'My crew', subtitle: 'Your profile and your crew', onTap: () => context.go(Routes.workerProfiles)),
                    MediaTile(imageUrl: AppImages.adminCrisis, icon: Icons.alt_route, title: 'Exit navigation', subtitle: 'Live map to the nearest exit', onTap: () => context.go(Routes.workerSosEvac)),
                  ]),
                  const SizedBox(height: Space.x2),
                  const SectionHeader(title: 'Recent check-ins'),
                  RecentCheckins(items: s.checkins, loading: s.status == WorkerHomeStatus.loading, flashIds: s.flashIds),
                ]),
              ),
            ],
          ),
        );
      })), const SafetyBar()]),
    );
  }
}
