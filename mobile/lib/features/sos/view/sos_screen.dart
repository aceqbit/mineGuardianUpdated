import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:url_launcher/url_launcher.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/pulse_dot.dart';
import '../../../app/ui/read_aloud_button.dart';
import '../../voice_call/widgets/ai_call_button.dart';
import '../data/emergency_protocol.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/auth/session_bloc.dart';
import '../../../core/db/cache_repository.dart';
import '../../../core/db/layout_repository.dart';
import '../../../core/location/location_service.dart';
import '../../../core/models/session_user.dart';
import '../../../core/socket/socket_service.dart';
import '../../../core/sync/outbox_queue.dart';
import '../../../core/sync/sync_engine.dart';
import '../../../core/time/ist.dart';
import '../bloc/sos_bloc.dart';
import '../bloc/sos_event.dart';
import '../bloc/sos_state.dart';
import '../data/sos_repository.dart';
import '../widgets/sos_map_panel.dart';
import '../widgets/first_aid_sheet.dart';
import '../widgets/hold_to_confirm.dart';

class SosScreen extends StatelessWidget {
  const SosScreen({super.key, this.evacOnly = false, this.locationService});

  /// `?mode=evac`: shows the evacuation view and sends nothing.
  final bool evacOnly;
  final LocationService? locationService;

  @override
  Widget build(BuildContext context) {
    final session = context.read<SessionBloc>().state;
    if (session is! SessionAuthenticated) return const SizedBox.shrink();
    final user = session.user;
    return BlocProvider(
      create: (ctx) => SosBloc(
        repo: SosRepository(api: ctx.read<ApiClient>()),
        location: locationService ?? LocationService(),
        socket: ctx.read<SocketService>(),
        engine: ctx.read<SyncEngine>(),
        queue: ctx.read<OutboxQueue>(),
        layout: LayoutRepository(api: ctx.read<ApiClient>(), cache: ctx.read<CacheRepository>()),
        userId: user.id,
        zoneCode: user.zoneCode ?? '',
        designatedExitId: user.evacExitId,
      )..add(SosOpened(evacOnly: evacOnly)),
      child: _SosView(user: user, evacOnly: evacOnly),
    );
  }
}

class _SosView extends StatefulWidget {
  const _SosView({required this.user, required this.evacOnly});
  final SessionUser user;
  final bool evacOnly;

  @override
  State<_SosView> createState() => _SosViewState();
}

class _SosViewState extends State<_SosView> {
  final _start = DateTime.now();
  Timer? _tick;
  Duration _elapsed = Duration.zero;

  @override
  void initState() {
    super.initState();
    _tick = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() => _elapsed = DateTime.now().difference(_start));
    });
  }

  @override
  void dispose() {
    _tick?.cancel();
    super.dispose();
  }

  String get _elapsedText => '${_elapsed.inMinutes.toString().padLeft(2, '0')}:${(_elapsed.inSeconds % 60).toString().padLeft(2, '0')}';

  String _statusLine(SosState s) {
    if (widget.evacOnly) return 'Follow the route to the nearest exit';
    switch (s.status) {
      case SosSendStatus.idle:
      case SosSendStatus.sending:
        return 'Sending…';
      case SosSendStatus.sent:
        return 'Sent to control room ✓ ${s.sentAt == null ? '' : formatIst(s.sentAt!, pattern: 'HH:mm:ss')}';
      case SosSendStatus.savedOffline:
        return 'Saved offline — retrying (${s.retries})';
      case SosSendStatus.failed:
        return 'Failed — use Call or SMS below';
    }
  }

  Future<void> _call() async {
    final sups = widget.user.zoneSupervisors;
    if (sups.isEmpty) {
      _snack('No supervisor number saved on this phone');
      return;
    }
    ZoneSupervisor pick = sups.first;
    if (sups.length > 1) {
      final chosen = await showModalBottomSheet<ZoneSupervisor>(
        context: context,
        builder: (ctx) => SafeArea(child: Column(mainAxisSize: MainAxisSize.min, children: [for (final s in sups) ListTile(leading: const Icon(Icons.call), title: Text(s.name), subtitle: Text(s.e164), onTap: () => Navigator.pop(ctx, s))])),
      );
      if (chosen == null) return;
      pick = chosen;
    }
    await launchUrl(Uri(scheme: 'tel', path: pick.e164));
  }

  Future<void> _sms(SosState s) async {
    final sups = widget.user.zoneSupervisors;
    if (sups.isEmpty) {
      _snack('No supervisor number saved on this phone');
      return;
    }
    final fix = s.fix;
    final loc = fix == null ? 'location unknown' : 'loc ${fix.lat.toStringAsFixed(5)},${fix.lng.toStringAsFixed(5)}, maps https://maps.google.com/?q=${fix.lat.toStringAsFixed(5)},${fix.lng.toStringAsFixed(5)}';
    final body = 'SOS: ${widget.user.fullName}, ${widget.user.zoneCode ?? ''}, ${formatIst(DateTime.now())} IST, $loc';
    await launchUrl(Uri(scheme: 'sms', path: sups.first.e164, query: 'body=${Uri.encodeComponent(body)}'));
  }

  void _snack(String m) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(m)));

  Future<void> _cancel() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text("I'm safe — cancel SOS?"),
        content: const Text('Your supervisor and the control room will be told you are safe.'),
        actions: [TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Keep SOS')), TextButton(onPressed: () => Navigator.pop(ctx, true), child: const Text("I'm safe"))],
      ),
    );
    if (ok == true && mounted) context.read<SosBloc>().add(const SosCancelConfirmed());
  }

  Widget _header(SosState s) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return Container(
      padding: const EdgeInsets.all(Space.lg),
      color: c.crisis,
      child: SafeArea(
        bottom: false,
        child: Row(children: [
          const PulseDot(color: Colors.white, size: 14),
          const SizedBox(width: Space.md),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.evacOnly ? 'EVACUATION ACTIVE' : 'SOS ACTIVE', style: t.headlineSmall?.copyWith(color: Colors.white, fontWeight: FontWeight.w800)),
              const SizedBox(height: 2),
              Semantics(liveRegion: true, child: Text(_statusLine(s), style: t.bodyMedium?.copyWith(color: Colors.white70))),
            ]),
          ),
          Text(_elapsedText, style: t.headlineSmall?.copyWith(color: Colors.white, fontFeatures: const [FontFeature.tabularFigures()])),
        ]),
      ),
    );
  }

  List<Widget> _actions(SosState s) {
    final c = MgColors.of(context);
    return [
      MgButton(label: 'Call supervisor', icon: Icons.call, expand: true, onPressed: _call),
      const SizedBox(height: Space.md),
      // Add-on X5: the AI voice agent calls the supervisor at once and tells them who, where and why.
      for (final sup in widget.user.zoneSupervisors.where((x) => x.id != null)) ...[
        AiCallButton(targetType: 'user', targetId: sup.id!, targetLabel: sup.name, reason: s.evacOnly ? 'evacuation in progress' : 'SOS', expand: true),
        const SizedBox(height: Space.md),
      ],
      MgButton(label: 'Share location by SMS', icon: Icons.sms, expand: true, kind: MgButtonKind.secondary, onPressed: () => _sms(s)),
      const SizedBox(height: Space.md),
      Align(
        alignment: Alignment.centerLeft,
        child: ReadAloudButton(owner: 'evac-protocol', label: 'Read evacuation protocol aloud', segments: [evacuationProtocolTitle, ...evacuationProtocol, if (s.offlineRoute != null) s.offlineRoute!.summary]),
      ),
      const SizedBox(height: Space.md),
      MgButton(label: 'First aid', icon: Icons.medical_services, expand: true, kind: MgButtonKind.secondary, onPressed: () => showFirstAidSheet(context)),
      if (s.status == SosSendStatus.failed) ...[
        const SizedBox(height: Space.md),
        MgButton(label: 'Try sending again', icon: Icons.refresh, expand: true, onPressed: () => context.read<SosBloc>().add(const SosRetrySend())),
      ],
      if (!widget.evacOnly) ...[
        const SizedBox(height: Space.x2),
        HoldToConfirm(label: "I'm safe — cancel SOS", icon: Icons.verified_user, color: c.successBg, foreground: c.success, onConfirmed: _cancel),
      ] else ...[
        const SizedBox(height: Space.x2),
        MgButton(label: 'Back', kind: MgButtonKind.ghost, expand: true, onPressed: () => context.canPop() ? context.pop() : context.go(Routes.worker)),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return BlocConsumer<SosBloc, SosState>(
      listenWhen: (a, b) => !a.cancelled && b.cancelled,
      listener: (context, s) => context.go(Routes.worker),
      builder: (context, s) {
        final map = SizedBox(height: context.isExpanded ? double.infinity : 380, child: SosMapPanel(state: s));
        final body = context.isExpanded
            ? Padding(
                padding: const EdgeInsets.all(Space.lg),
                child: Row(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Expanded(flex: 6, child: map),
                  const SizedBox(width: Space.lg),
                  Expanded(flex: 4, child: SingleChildScrollView(child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: _actions(s)))),
                ]),
              )
            : SingleChildScrollView(
                padding: const EdgeInsets.all(Space.lg),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [map, const SizedBox(height: Space.lg), ..._actions(s)]),
              );
        return PopScope(
          canPop: widget.evacOnly,
          child: Scaffold(backgroundColor: c.bg, body: Column(children: [_header(s), Expanded(child: body)])),
        );
      },
    );
  }
}
