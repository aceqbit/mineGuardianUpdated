import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../contracts/enums.dart';
import '../contracts/routes.dart';
import '../contracts/socket_events.dart';
import '../core/api/api_client.dart';
import '../core/auth/session_bloc.dart';
import '../core/socket/socket_service.dart';
import '../features/broadcast/bloc/broadcast_inbox_bloc.dart';
import '../features/broadcast/data/broadcast_repository.dart';
import '../features/crisis/bloc/crisis_bloc.dart';
import '../features/crisis/data/crisis_repository.dart';
import 'siren.dart';
import 'ui/read_aloud_button.dart';
import 'theme/motion.dart';
import 'theme/tokens.dart';

/// Wraps every page via a ShellRoute: crisis flash, siren, banners and navigation per role (CLAUDE.md §13).
/// admin: 3 red pulses + siren + open the crisis console. supervisor: banner + 3 s siren. miner: EVACUATE banner + vibration + evacuation view.
class GlobalOverlays extends StatefulWidget {
  const GlobalOverlays({super.key, required this.child, this.crisisBloc, this.inboxBloc, this.siren});
  final Widget child;

  /// Tests inject these; the app builds its own.
  final CrisisBloc? crisisBloc;
  final BroadcastInboxBloc? inboxBloc;
  final SirenController? siren;

  @override
  State<GlobalOverlays> createState() => _GlobalOverlaysState();
}

class _GlobalOverlaysState extends State<GlobalOverlays> with SingleTickerProviderStateMixin {
  CrisisBloc? _bloc;
  BroadcastInboxBloc? _inbox;
  bool _ownsInbox = false;
  Timer? _toastTimer;
  SirenController? _siren;
  bool _ownsBloc = false, _ownsSiren = false;
  late final AnimationController _flash = AnimationController(vsync: this, duration: const Duration(milliseconds: 300));
  Timer? _clearTimer;

  Role? get _role {
    final s = context.read<SessionBloc>().state;
    return s is SessionAuthenticated ? s.user.role : null;
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_bloc == null) {
      _ownsBloc = widget.crisisBloc == null;
      _bloc = widget.crisisBloc ??
          CrisisBloc(repo: CrisisRepository(api: context.read<ApiClient>()), socket: context.read<SocketService>(), isStaff: () => _role == Role.admin || _role == Role.supervisor);
    }
    if (_inbox == null) {
      _ownsInbox = widget.inboxBloc == null;
      _inbox = widget.inboxBloc ?? BroadcastInboxBloc(repo: BroadcastRepository(api: context.read<ApiClient>()), socket: context.read<SocketService>());
    }
    if (_siren == null) {
      _ownsSiren = widget.siren == null;
      _siren = widget.siren ?? SirenController();
    }
  }

  @override
  void dispose() {
    _clearTimer?.cancel();
    _toastTimer?.cancel();
    _flash.dispose();
    if (_ownsInbox) _inbox?.close();
    if (_ownsBloc) _bloc?.close();
    if (_ownsSiren) _siren?.dispose();
    super.dispose();
  }

  String get _path => GoRouter.of(context).routeInformationProvider.value.uri.path;

  void _go(String route) {
    if (_path != route.split('?').first) GoRouter.of(context).go(route);
  }

  Future<void> _onActivated() async {
    final role = _role;
    if (role == null) return;
    switch (role) {
      case Role.admin:
        if (!Motion.reduce(context)) {
          for (var i = 0; i < 3 && mounted; i++) {
            await _flash.forward(from: 0);
            await _flash.reverse();
          }
        }
        unawaited(_siren!.start(forAtMost: const Duration(seconds: 10)));
        _go(Routes.adminCrisis);
      case Role.supervisor:
        unawaited(_siren!.start(forAtMost: const Duration(seconds: 3)));
      case Role.miner:
        unawaited(HapticFeedback.vibrate());
        _go('${Routes.workerSos}?mode=evac');
    }
  }

  void _onResolved() {
    unawaited(_siren!.stop());
    _clearTimer?.cancel();
    if (_role != Role.admin) {
      _clearTimer = Timer(const Duration(seconds: 8), () {
        if (mounted) _bloc!.add(const CrisisCleared());
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bloc = _bloc!;
    final session = context.watch<SessionBloc>().state;
    return MultiBlocProvider(
      providers: [BlocProvider<CrisisBloc>.value(value: bloc), BlocProvider<BroadcastInboxBloc>.value(value: _inbox!)],
      child: BlocListener<SessionBloc, SessionState>(
        listener: (context, s) {
          if (s is SessionAuthenticated) {
            bloc.add(const CrisisStarted());
            _inbox!.add(const InboxStarted());
          } else {
            bloc.add(const CrisisCleared());
            unawaited(_siren!.stop());
          }
        },
        child: MultiBlocListener(
          listeners: [
            BlocListener<CrisisBloc, CrisisState>(listenWhen: (a, b) => a.activationSeq != b.activationSeq, listener: (context, s) => _onActivated()),
            BlocListener<BroadcastInboxBloc, BroadcastInboxState>(
              listenWhen: (a, b) => b.toast != null && a.toast?.id != b.toast?.id,
              listener: (context, s) {
                _toastTimer?.cancel();
                _toastTimer = Timer(const Duration(seconds: 4), () {
                  if (mounted) _inbox!.add(const InboxToastDismissed());
                });
              },
            ),
            BlocListener<CrisisBloc, CrisisState>(listenWhen: (a, b) => a.phase != CrisisPhase.resolved && b.phase == CrisisPhase.resolved, listener: (context, s) => _onResolved()),
          ],
          child: Stack(children: [
            Positioned.fill(child: widget.child),
            if (session is SessionAuthenticated) ...[
              Positioned(top: 0, left: 0, right: 0, child: SafeArea(bottom: false, child: Column(mainAxisSize: MainAxisSize.min, children: [_CrisisBanner(role: session.user.role, onGo: _go), const BroadcastBanners()]))),
              Positioned.fill(child: IgnorePointer(child: AnimatedBuilder(animation: _flash, builder: (_, _) => ColoredBox(color: MgColors.of(context).crisis.withValues(alpha: 0.45 * _flash.value))))),
              Positioned(right: Space.md, bottom: Space.x4 + Space.lg, child: _SirenChip(siren: _siren!)),
            ],
          ]),
        ),
      ),
    );
  }
}

class _CrisisBanner extends StatelessWidget {
  const _CrisisBanner({required this.role, required this.onGo});
  final Role role;
  final void Function(String) onGo;

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<CrisisBloc, CrisisState>(
      builder: (context, s) {
        if (s.phase == CrisisPhase.idle) return const SizedBox.shrink();
        final c = MgColors.of(context);
        final resolved = s.phase == CrisisPhase.resolved;
        final (text, route) = switch (role) {
          Role.miner => (resolved ? (s.falseAlarm ? 'False alarm. You can continue your shift.' : 'Emergency resolved. Follow your supervisor.') : 'EVACUATE — follow the route on your screen', '${Routes.workerSos}?mode=evac'),
          Role.supervisor => (resolved ? 'Crisis resolved' : 'CRISIS ACTIVE — open the crisis view', Routes.crisisView),
          Role.admin => (resolved ? 'Crisis resolved — open the report' : 'CRISIS ACTIVE — open the console', Routes.adminCrisis),
        };
        return Semantics(
          liveRegion: true,
          button: true,
          label: text,
          child: Material(
            color: resolved ? c.successFill : c.crisis,
            child: InkWell(
              onTap: () => onGo(route),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.md),
                child: Row(children: [
                  Icon(resolved ? Icons.check_circle : Icons.warning_amber_rounded, color: Colors.white),
                  const SizedBox(width: Space.sm),
                  Expanded(child: Text(text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                  const Icon(Icons.chevron_right, color: Colors.white),
                ]),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _SirenChip extends StatelessWidget {
  const _SirenChip({required this.siren});
  final SirenController siren;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: siren,
      builder: (context, _) {
        if (!siren.blocked && !siren.playing && !siren.muted) return const SizedBox.shrink();
        final label = siren.blocked ? 'Tap to enable siren' : (siren.muted ? 'Siren muted' : 'Mute siren');
        final icon = siren.blocked ? Icons.volume_up : (siren.muted ? Icons.volume_off : Icons.volume_off_outlined);
        return Material(
          color: MgColors.of(context).ink800,
          borderRadius: BorderRadius.circular(Radii.pill),
          child: InkWell(
            borderRadius: BorderRadius.circular(Radii.pill),
            onTap: () => siren.blocked ? siren.enable() : siren.toggleMute(),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: Space.md, vertical: Space.sm),
              child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(icon, color: Colors.white, size: 18), const SizedBox(width: Space.sm), Text(label, style: const TextStyle(color: Colors.white))]),
            ),
          ),
        );
      },
    );
  }
}

/// Sticky banners for URGENT and EMERGENCY broadcasts (until "Got it"); INFO shows as a short toast.
class BroadcastBanners extends StatelessWidget {
  const BroadcastBanners({super.key});

  /// A short reply goes to the admin (and the sender) over the socket.
  Future<void> _reply(BuildContext context, String broadcastId) async {
    final socket = context.read<SocketService>();
    final ctl = TextEditingController();
    final text = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Reply'),
        content: TextField(controller: ctl, autofocus: true, maxLength: 280, maxLines: 3, decoration: const InputDecoration(hintText: 'Your reply')),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Cancel')), FilledButton(onPressed: () => Navigator.pop(ctx, ctl.text.trim()), child: const Text('Send'))],
      ),
    );
    ctl.dispose();
    if (text == null || text.isEmpty) return;
    await socket.emit(SocketEvents.broadcastReplySend, {'broadcastId': broadcastId, 'text': text});
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<BroadcastInboxBloc, BroadcastInboxState>(
      builder: (context, s) {
        final c = MgColors.of(context);
        return Column(mainAxisSize: MainAxisSize.min, children: [
          for (final m in s.sticky)
            Semantics(
              liveRegion: true,
              label: '${m.priority.label} message from ${m.senderName}: ${m.text}',
              child: Material(
                key: ValueKey('bc-${m.id}'),
                color: m.priority == BroadcastPriority.emergency ? c.crisis : c.warningFill,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
                  child: Row(children: [
                    const Icon(Icons.campaign, color: Colors.white),
                    const SizedBox(width: Space.sm),
                    Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text('${m.priority.label.toUpperCase()} · ${m.senderName}', style: const TextStyle(color: Colors.white70, fontSize: 11, fontWeight: FontWeight.w700)), Text(m.text, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w700))])),
                    ReadAloudButton(owner: 'bc-${m.id}', segments: [m.text], onDark: true),
                    TextButton(onPressed: () => _reply(context, m.id), child: const Text('Reply', style: TextStyle(color: Colors.white))),
                    TextButton(onPressed: () => context.read<BroadcastInboxBloc>().add(InboxGotIt(m.id)), child: const Text('Got it', style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800))),
                  ]),
                ),
              ),
            ),
          if (s.toast != null)
            Material(
              key: const ValueKey('bc-toast'),
              color: c.ink800,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: Space.lg, vertical: Space.sm),
                child: Row(children: [const Icon(Icons.info_outline, color: Colors.white, size: 18), const SizedBox(width: Space.sm), Expanded(child: Text('${s.toast!.senderName}: ${s.toast!.text}', style: const TextStyle(color: Colors.white)))]),
              ),
            ),
        ]);
      },
    );
  }
}
