import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/pulse_dot.dart';
import '../../../app/ui/role_accent.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/location/tracking_controller.dart';
import '../../../core/models/session_user.dart';
import '../../../core/socket/socket_service.dart';
import '../../../core/sync/sync_engine.dart';
import '../../voice_call/widgets/ai_call_button.dart';
import '../bloc/feature_dock_bloc.dart';

/// Pages where the dock stays out of the way: sign-in, the SOS / evacuation screen and the crisis consoles need focus.
bool dockVisibleFor(String path) {
  const hidden = [Routes.splash, Routes.login, Routes.signup, Routes.workerSos, Routes.adminCrisis, Routes.crisisView];
  if (path.startsWith('/dev/')) return false;
  return !hidden.any((h) => path == h || path.startsWith('$h/'));
}

class DockShortcut {
  const DockShortcut({required this.label, required this.icon, this.route, this.onTap});
  final String label;
  final IconData icon;
  final String? route;
  final void Function(BuildContext)? onTap;
}

List<DockShortcut> dockShortcuts(SessionUser user) {
  switch (user.role) {
    case Role.miner:
      final sup = user.zoneSupervisors.where((s) => s.id != null).firstOrNull;
      return [
        const DockShortcut(label: 'Profiles', icon: Icons.badge, route: Routes.workerProfiles),
        const DockShortcut(label: 'Live map', icon: Icons.map, route: Routes.workerMap),
        const DockShortcut(label: 'Safety today', icon: Icons.health_and_safety, route: Routes.workerSafety),
        if (sup != null) DockShortcut(label: 'AI call ${sup.name.split(' ').first}', icon: Icons.support_agent, onTap: (ctx) => showAiCallSheet(ctx, targetType: 'user', targetId: sup.id!, targetLabel: sup.name)),
      ];
    case Role.supervisor:
      return const [
        DockShortcut(label: 'Profiles', icon: Icons.badge, route: Routes.supervisorProfiles),
        DockShortcut(label: 'Live map', icon: Icons.map, route: Routes.supervisorLiveMap),
      ];
    case Role.admin:
      return const [
        DockShortcut(label: 'Profiles', icon: Icons.badge, route: Routes.adminProfiles),
        DockShortcut(label: 'Live map', icon: Icons.map, route: Routes.adminLiveMap),
        DockShortcut(label: 'AI calls', icon: Icons.support_agent, route: Routes.adminContacts),
      ];
  }
}

/// Puts the dock under every signed-in role page (used by the router's ShellRoute; wraps, never edits, the pages).
class FeatureDockFrame extends StatelessWidget {
  const FeatureDockFrame({super.key, required this.location, required this.child});
  final String location;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final s = context.watch<SessionBloc>().state;
    if (s is! SessionAuthenticated || !dockVisibleFor(location)) return child;
    return Column(children: [
      Expanded(child: MediaQuery.removePadding(context: context, removeBottom: true, child: child)),
      FeatureDock(user: s.user, location: location),
    ]);
  }
}

/// The high-contrast band (CLAUDE.md section 23.7): role-accent top border, the role's add-on shortcuts and live status
/// chips (connection, outbox, tracking source, crisis). Icon row below 600 px.
class FeatureDock extends StatelessWidget {
  const FeatureDock({super.key, required this.user, required this.location});
  final SessionUser user;
  final String location;

  @override
  Widget build(BuildContext context) {
    T? opt<T>() {
      try {
        return RepositoryProvider.of<T>(context);
      } catch (_) {
        return null;
      }
    }

    final socket = opt<SocketService>();
    if (socket == null) return const SizedBox.shrink();
    return BlocProvider(
      create: (_) => FeatureDockBloc(socket: socket, engine: opt<SyncEngine>(), tracking: user.role == Role.miner ? opt<TrackingController>() : null, api: opt<ApiClient>())..add(const DockStarted()),
      child: _Dock(user: user, location: location),
    );
  }
}

class _Dock extends StatelessWidget {
  const _Dock({required this.user, required this.location});
  final SessionUser user;
  final String location;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final accent = RoleAccent.of(context, user.role);
    final compact = context.sizeClass == SizeClass.compact;
    final shortcuts = dockShortcuts(user);
    return Material(
      color: dark ? c.ink800 : c.ink900,
      child: Container(
        decoration: BoxDecoration(border: Border(top: BorderSide(color: accent.fill, width: 3))),
        child: SafeArea(
          top: false,
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: compact ? Space.sm : Space.lg, vertical: Space.xs),
            child: BlocBuilder<FeatureDockBloc, DockState>(
              builder: (context, s) {
                final status = _statusChips(s, compact);
                return Row(children: [
                  Expanded(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: Row(children: [
                        for (final sc in shortcuts) _ShortcutButton(shortcut: sc, compact: compact, selected: sc.route != null && (location == sc.route || location.startsWith('${sc.route}/'))),
                      ]),
                    ),
                  ),
                  const SizedBox(width: Space.sm),
                  Semantics(
                    liveRegion: true,
                    label: _statusLabel(s),
                    excludeSemantics: true,
                    child: Row(mainAxisSize: MainAxisSize.min, children: status),
                  ),
                  if (!compact) ...[const SizedBox(width: Space.sm), Text(user.role.label.toUpperCase(), style: t.labelSmall?.copyWith(color: accent.fill == c.amber500 ? c.amber500 : c.slate300, letterSpacing: 1.2))],
                ]);
              },
            ),
          ),
        ),
      ),
    );
  }

  String _statusLabel(DockState s) => [
        s.online ? 'Online' : 'Offline',
        if (s.pending > 0) '${s.pending} queued',
        if (s.failed > 0) '${s.failed} failed',
        if (s.tracking == TrackingPhase.live) 'Location live',
        if (s.crisis == true) 'Crisis active',
      ].join(', ');

  List<Widget> _statusChips(DockState s, bool compact) {
    String src(PositionSource? p) => switch (p) { PositionSource.gps => 'GPS', PositionSource.fused => 'GPS+sensors', PositionSource.pdr => 'sensors', null => '…' };
    if (compact) {
      return [
        _Dot(on: s.online, label: s.online ? 'Online' : 'Offline'),
        if (s.pending > 0 || s.failed > 0) Padding(padding: const EdgeInsets.only(left: Space.xs), child: Badge.count(count: s.pending + s.failed, child: const Icon(Icons.cloud_upload, size: 18, color: Colors.white))),
        if (s.crisis == true) const Padding(padding: EdgeInsets.only(left: Space.sm), child: StatusChip(label: 'CRISIS', tone: ChipTone.crisis)),
      ];
    }
    return [
      StatusChip(label: s.online ? 'Online' : 'Offline', tone: s.online ? ChipTone.success : ChipTone.neutral, icon: s.online ? Icons.wifi : Icons.wifi_off),
      if (s.pending > 0 || s.failed > 0) ...[const SizedBox(width: Space.xs), StatusChip(label: s.failed > 0 ? '${s.failed} failed' : '${s.pending} queued', tone: s.failed > 0 ? ChipTone.danger : ChipTone.warning, icon: Icons.cloud_upload)],
      if (s.tracking != null && s.tracking != TrackingPhase.notMiner) ...[
        const SizedBox(width: Space.xs),
        StatusChip(label: s.tracking == TrackingPhase.live ? 'Live · ${src(s.source)}' : (s.tracking == TrackingPhase.outsideShift ? 'Off shift' : 'Location off'), tone: s.tracking == TrackingPhase.live ? ChipTone.info : ChipTone.neutral, icon: Icons.my_location),
      ],
      if (s.crisis != null) ...[const SizedBox(width: Space.xs), s.crisis! ? const StatusChip(label: 'Crisis active', tone: ChipTone.crisis) : const StatusChip(label: 'No crisis', tone: ChipTone.neutral, icon: Icons.verified_user)],
    ];
  }
}

class _Dot extends StatelessWidget {
  const _Dot({required this.on, required this.label});
  final bool on;
  final String label;
  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return Tooltip(message: label, child: PulseDot(color: on ? c.success : c.slate400, size: 8, pulsing: on));
  }
}

class _ShortcutButton extends StatelessWidget {
  const _ShortcutButton({required this.shortcut, required this.compact, required this.selected});
  final DockShortcut shortcut;
  final bool compact;
  final bool selected;

  void _go(BuildContext context) {
    final r = shortcut.route;
    if (r != null) {
      context.go(r);
    } else {
      shortcut.onTap?.call(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    // White on the ink band always passes AA; the role colour lives in the top border, selection is a lighter pill.
    final pill = selected ? Colors.white.withValues(alpha: 0.16) : null;
    if (compact) {
      return IconButton(tooltip: shortcut.label, onPressed: () => _go(context), style: IconButton.styleFrom(backgroundColor: pill), icon: Icon(shortcut.icon, color: Colors.white));
    }
    return Padding(
      padding: const EdgeInsets.only(right: Space.xs),
      child: TextButton.icon(
        onPressed: () => _go(context),
        style: TextButton.styleFrom(foregroundColor: Colors.white, backgroundColor: pill, shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(Radii.pill))),
        icon: Icon(shortcut.icon, size: 18),
        label: Text(shortcut.label, style: t.labelLarge?.copyWith(color: c.slate100, fontWeight: selected ? FontWeight.w800 : null)),
      ),
    );
  }
}
