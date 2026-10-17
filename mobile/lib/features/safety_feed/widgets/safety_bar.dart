import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/motion.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/db/cache_repository.dart';
import '../../../core/socket/socket_service.dart';
import '../bloc/safety_feed_bloc.dart';
import '../data/safety_feed_repository.dart';
import '../view/safety_screen.dart';
import 'safety_visuals.dart';

/// Bottom safety bar on the miner home (CLAUDE.md section 23.6): today's titles rotate every 5 s with their kind chip;
/// tap opens /worker/safety. Works offline from the cached feed. Renders nothing when the API is not wired (tests).
class SafetyBar extends StatelessWidget {
  const SafetyBar({super.key, this.repository});
  final SafetyFeedRepository? repository;

  @override
  Widget build(BuildContext context) {
    SafetyFeedRepository repo;
    SocketService socket;
    try {
      repo = repository ?? SafetyFeedRepository(api: context.read<ApiClient>(), cache: context.read<CacheRepository>());
      socket = context.read<SocketService>();
    } catch (_) {
      return const SizedBox.shrink();
    }
    return BlocProvider(create: (_) => SafetyFeedBloc(repo: repo, socket: socket)..add(const SafetyFeedStarted()), child: const _Bar());
  }
}

class _Bar extends StatefulWidget {
  const _Bar();
  @override
  State<_Bar> createState() => _BarState();
}

class _BarState extends State<_Bar> {
  Timer? _timer;
  int _i = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  void _ensureTimer(int n) {
    if (n <= 1 || Motion.reduce(context)) {
      _timer?.cancel();
      _timer = null;
      return;
    }
    _timer ??= Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted) setState(() => _i++);
    });
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final compact = context.sizeClass == SizeClass.compact;
    return BlocConsumer<SafetyFeedBloc, SafetyFeedState>(
      listener: (context, s) => _ensureTimer(s.feed?.items.length ?? 0),
      builder: (context, s) {
        final items = s.feed?.items ?? const <SafetyItem>[];
        final item = items.isEmpty ? null : items[_i % items.length];
        final note = availabilityText(s.availability, s.feed);
        return Material(
          color: c.ink900,
          child: InkWell(
            onTap: () => context.go(Routes.workerSafety),
            child: SafeArea(
              top: false,
              child: Padding(
                // keep clear of the SOS button that floats bottom-right on phones
                padding: EdgeInsets.fromLTRB(Space.lg, Space.sm, compact ? 96 : Space.lg, Space.sm),
                child: Semantics(
                  button: true,
                  liveRegion: true,
                  label: item == null ? 'Safety today. $note' : 'Safety today: ${item.kind.label}. ${item.title}',
                  excludeSemantics: true,
                  child: Row(children: [
                    Icon(Icons.health_and_safety, color: c.amber500, size: 20),
                    const SizedBox(width: Space.sm),
                    Expanded(
                      child: AnimatedSwitcher(
                        duration: Motion.of(context, Motion.slow),
                        transitionBuilder: (child, a) => FadeTransition(opacity: a, child: SlideTransition(position: Tween(begin: const Offset(0, 0.4), end: Offset.zero).animate(a), child: child)),
                        child: item == null
                            ? Text(s.loading ? 'Loading today\'s safety feed…' : note, key: const ValueKey('note'), maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodySmall?.copyWith(color: c.slate300))
                            : Row(key: ValueKey(item.id), children: [
                                Flexible(child: StatusChip(label: item.kind.label, tone: kindTone(item.kind))),
                                const SizedBox(width: Space.sm),
                                Expanded(child: Text(item.title, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.bodyMedium?.copyWith(color: Colors.white))),
                              ]),
                      ),
                    ),
                    Icon(Icons.chevron_right, color: c.slate300),
                  ]),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
