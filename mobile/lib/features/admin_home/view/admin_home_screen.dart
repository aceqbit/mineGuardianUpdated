import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/app_images.dart';
import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/media_tile.dart';
import '../../../app/ui/section_header.dart';
import '../../../app/ui/skeleton.dart';
import '../../../app/ui/toast.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../bloc/admin_home_bloc.dart';
import '../bloc/admin_home_event.dart';
import '../bloc/admin_home_state.dart';
import '../data/admin_repository.dart';
import '../widgets/admin_nav.dart';
import '../widgets/assign_supervisors_sheet.dart';
import '../widgets/crisis_status_card.dart';
import '../widgets/kpi_grid.dart';
import '../widgets/zone_card.dart';

class AdminHomeScreen extends StatelessWidget {
  const AdminHomeScreen({super.key});

  @override
  Widget build(BuildContext context) => BlocProvider(
        create: (ctx) => AdminHomeBloc(repo: AdminRepository(api: ctx.read<ApiClient>()), socket: ctx.read<SocketService>())..add(const AdminHomeStarted()),
        child: const _View(),
      );
}

class _View extends StatelessWidget {
  const _View();

  @override
  Widget build(BuildContext context) {
    return BlocConsumer<AdminHomeBloc, AdminHomeState>(
      listenWhen: (a, b) => b.notice != null && a.notice != b.notice,
      listener: (context, s) {
        Toast.show(context, s.notice!, kind: s.noticeIsError ? ToastKind.error : (s.notice!.startsWith('SLA') ? ToastKind.warning : ToastKind.success));
        context.read<AdminHomeBloc>().add(const AdminNoticeShown());
      },
      builder: (context, s) {
        final o = s.overview;
        final t = Theme.of(context).textTheme;
        Widget body;
        if (s.status == AdminStatus.failure) {
          body = EmptyState(icon: Icons.cloud_off, title: 'Could not load the overview', message: 'Check your connection', actionLabel: 'Retry', onAction: () => context.read<AdminHomeBloc>().add(const AdminHomeStarted()));
        } else {
          body = RefreshIndicator(
            onRefresh: () async => context.read<AdminHomeBloc>().add(const AdminHomeRefreshRequested()),
            child: SingleChildScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.symmetric(vertical: Space.lg),
              child: ContentWidth(
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  KpiGrid(overview: o),
                  const SizedBox(height: Space.lg),
                  if (o == null) const Skeleton(height: 72, radius: Radii.card) else CrisisStatusCard(crisis: o.crisis, onOpenConsole: () => context.go(Routes.adminCrisis)),
                  const SizedBox(height: Space.x2),
                  const SectionHeader(title: 'Zones'),
                  if (o == null)
                    const SkeletonList(count: 2, itemHeight: 220)
                  else
                    AdaptiveGrid(
                      minTileWidth: 280,
                      maxColumns: 3,
                      fixedTileHeight: 520,
                      children: [
                        for (final z in o.zones)
                          ZoneCard(
                            zone: z,
                            exits: s.exits,
                            onExitChosen: (id) => context.read<AdminHomeBloc>().add(ZoneExitChosen(z.id, id)),
                            onManage: () async {
                              final bloc = context.read<AdminHomeBloc>();
                              final ids = await showAssignSupervisorsSheet(context, zone: z, all: s.supervisors);
                              if (ids != null) bloc.add(SupervisorsAssigned(z.id, ids));
                            },
                          ),
                      ],
                    ),
                  const SizedBox(height: Space.x2),
                  Text('Quick access', style: t.headlineSmall),
                  const SizedBox(height: Space.md),
                  AdaptiveGrid(minTileWidth: 200, aspectRatio: 1.6, children: [
                    MediaTile(imageUrl: AppImages.adminReports, icon: Icons.fact_check, title: 'Normal Mode', subtitle: s.slaBreaches > 0 ? '${s.slaBreaches} SLA breach${s.slaBreaches == 1 ? '' : 'es'}' : 'SLA, hazard audit', aspectRatio: 1.6, onTap: () {
                      AdminBadges.sla.value = 0;
                      context.go(Routes.adminNormal);
                    }),
                    MediaTile(imageUrl: AppImages.adminCrisis, icon: Icons.crisis_alert, title: 'Crisis Console', subtitle: 'Master control', aspectRatio: 1.6, onTap: () => context.go(Routes.adminCrisis)),
                    MediaTile(imageUrl: AppImages.broadcast, icon: Icons.campaign, title: 'Broadcast', subtitle: 'Message your people', aspectRatio: 1.6, onTap: () => context.go(Routes.adminBroadcast)),
                    MediaTile(imageUrl: AppImages.contacts, icon: Icons.contact_phone, title: 'Emergency Contacts', subtitle: 'Police, fire, rescue', aspectRatio: 1.6, onTap: () => context.go(Routes.adminContacts)),
                    MediaTile(imageUrl: AppImages.leaderboard, icon: Icons.leaderboard, title: 'Live Leaderboard', subtitle: 'Everyone, live', aspectRatio: 1.6, onTap: () => context.go(Routes.leaderboard)),
                    MediaTile(imageUrl: AppImages.adminReports, icon: Icons.assessment, title: 'Reports', subtitle: 'PDF, shareable', aspectRatio: 1.6, onTap: () => context.go(Routes.adminReports)),
                  ]),
                ]),
              ),
            ),
          );
        }
        return AdminScaffold(section: AdminSection.overview, title: 'Admin overview', body: body);
      },
    );
  }
}
