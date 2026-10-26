import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../../../app/ui/page_hero.dart';
import '../../../app/ui/skeleton.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/db/cache_repository.dart';
import '../../../core/socket/socket_service.dart';
import '../bloc/safety_feed_bloc.dart';
import '../data/safety_feed_repository.dart';
import '../widgets/safety_visuals.dart';

String availabilityText(FeedAvailability? a, SafetyFeed? f) => switch (a) {
      FeedAvailability.notConfigured => "Today's safety feed is not set up on the server yet (GEMINI_API_KEY).",
      FeedAvailability.notReady => "Today's safety feed is being prepared from live sources.",
      FeedAvailability.cached => 'Offline: showing the feed from ${f?.date ?? 'the last download'}.',
      FeedAvailability.offline => 'No connection and no saved feed yet.',
      _ => f == null ? '' : 'Updated ${f.date} · ${f.items.length} items from live sources',
    };

/// `/worker/safety` (CLAUDE.md section 23.6): today's rule, how to prevent, how to react, lessons, and explainers.
class SafetyScreen extends StatelessWidget {
  const SafetyScreen({super.key, this.repository});
  final SafetyFeedRepository? repository;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => SafetyFeedBloc(repo: repository ?? SafetyFeedRepository(api: ctx.read<ApiClient>(), cache: ctx.read<CacheRepository>()), socket: ctx.read<SocketService>())..add(const SafetyFeedStarted()),
      child: DefaultTabController(
        length: 4,
        child: Scaffold(
          appBar: AppBar(
            leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go(Routes.worker)),
            title: const Text('Safety today'),
            bottom: const TabBar(isScrollable: true, tabAlignment: TabAlignment.start, tabs: [Tab(text: 'Today'), Tab(text: 'React'), Tab(text: 'Prevent'), Tab(text: 'Videos')]),
          ),
          body: BlocBuilder<SafetyFeedBloc, SafetyFeedState>(
            builder: (context, s) {
              final f = s.feed;
              if (s.loading && f == null) return const Padding(padding: EdgeInsets.all(Space.lg), child: SkeletonList(count: 3));
              if (f == null) {
                return EmptyState(icon: Icons.health_and_safety, title: 'No safety feed yet', message: availabilityText(s.availability, f), actionLabel: 'Retry', onAction: () => context.read<SafetyFeedBloc>().add(const SafetyFeedStarted()));
              }
              Widget list(List<Widget> children) => RefreshIndicator(
                    onRefresh: () async => context.read<SafetyFeedBloc>().add(const SafetyFeedStarted()),
                    child: ListView(padding: const EdgeInsets.symmetric(vertical: Space.lg), children: [
                      ContentWidth(maxWidth: Widths.form + 280, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [for (var i = 0; i < children.length; i++) ...[if (i > 0) const SizedBox(height: Space.lg), StaggerIn(index: i, child: children[i])]])),
                    ]),
                  );
              final hero = PageHero(role: Role.miner, icon: Icons.health_and_safety, title: 'Safety today', subtitle: availabilityText(s.availability, f));
              final react = f.of(SafetyItemKind.react);
              final byCat = <String, List<SafetyItem>>{};
              for (final r in react) {
                byCat.putIfAbsent(r.hazardCategory ?? 'OTHER', () => []).add(r);
              }
              String catName(String k) => k.replaceAll('_', ' ').toLowerCase().replaceFirstMapped(RegExp('^.'), (m) => m[0]!.toUpperCase());
              return TabBarView(children: [
                list([hero, for (final k in [SafetyItemKind.rule, SafetyItemKind.lesson]) ...f.of(k).map((i) => SafetyItemCard(item: i)), if (f.items.isEmpty) const EmptyState(icon: Icons.verified, title: 'Nothing passed the source check today', message: 'Only items backed by allowed sources are shown.')]),
                list([
                  if (react.isEmpty) const EmptyState(icon: Icons.emergency, title: 'No reaction guides today'),
                  for (final e in byCat.entries) ...[
                    Row(children: [Icon(hazardIcon(e.key), color: MgColors.of(context).danger), const SizedBox(width: Space.sm), Text(catName(e.key), style: Theme.of(context).textTheme.titleMedium)]),
                    for (final i in e.value) SafetyItemCard(item: i),
                  ],
                ]),
                list([if (f.of(SafetyItemKind.prevent).isEmpty) const EmptyState(icon: Icons.shield, title: 'No prevention items today'), ...f.of(SafetyItemKind.prevent).map((i) => SafetyItemCard(item: i))]),
                list([
                  if (f.videos.isEmpty) const EmptyState(icon: Icons.movie, title: 'No explainers today', message: 'Explainers are made from the React and Prevent items.'),
                  for (final v in f.videos)
                    v.isVeo ? VeoClip(video: v) : StoryboardPlayer(video: v, hazardCategory: f.items.where((i) => i.id == v.itemId).firstOrNull?.hazardCategory),
                ]),
              ]);
            },
          ),
        ),
      ),
    );
  }
}
