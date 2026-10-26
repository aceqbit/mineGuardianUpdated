import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/pulse_dot.dart';
import '../../../app/ui/status_chip.dart';
import '../../../contracts/enums.dart';
import '../../../core/api/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../bloc/voice_call_bloc.dart';
import '../data/voice_repository.dart';

/// Tap = an AI voice-agent call to [targetLabel] at once (CLAUDE.md section 23.5): no confirm dialog, a live status chip
/// and Hang up appear immediately. Every dialling guard runs on the server. Renders nothing when the API is not wired.
class AiCallButton extends StatelessWidget {
  const AiCallButton({super.key, required this.targetType, required this.targetId, required this.targetLabel, this.reason, this.expand = false, this.autoStart = false, this.repository});
  final String targetType;
  final String targetId;
  final String targetLabel;
  final String? reason;
  final bool expand;

  /// Place the call as soon as this appears (the tap that opened it was the call).
  final bool autoStart;
  final VoiceRepository? repository;

  @override
  Widget build(BuildContext context) {
    ApiClient? api;
    SocketService? socket;
    try {
      api = context.read<ApiClient>();
      socket = context.read<SocketService>();
    } catch (_) {
      return const SizedBox.shrink();
    }
    return BlocProvider(
      create: (_) {
        final b = VoiceCallBloc(repo: repository ?? VoiceRepository(api: api!), socket: socket!, targetType: targetType, targetId: targetId);
        if (autoStart) b.add(VoiceCallRequested(reason: reason));
        return b;
      },
      child: _CallView(label: targetLabel, reason: reason, expand: expand),
    );
  }
}

class _CallView extends StatelessWidget {
  const _CallView({required this.label, required this.reason, required this.expand});
  final String label;
  final String? reason;
  final bool expand;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    return BlocBuilder<VoiceCallBloc, VoiceCallState>(
      builder: (context, s) {
        final bloc = context.read<VoiceCallBloc>();
        final button = MgButton(
          label: s.phase == CallPhase.done || s.phase == CallPhase.error ? 'Call $label again' : 'AI call $label',
          icon: Icons.support_agent,
          kind: MgButtonKind.secondary,
          expand: expand,
          semanticLabel: 'Call $label now with the AI voice agent',
          onPressed: () => bloc.add(VoiceCallRequested(reason: reason)),
        );
        if (s.phase == CallPhase.idle) return button;
        final live = s.phase == CallPhase.placing || s.phase == CallPhase.active;
        final status = s.status;
        final (text, tone) = switch (s.phase) {
          CallPhase.error => (s.message ?? 'Call failed', ChipTone.danger),
          _ when status == VoiceCallStatus.dryRun => (status!.label, ChipTone.info),
          _ when status == VoiceCallStatus.failed => ('Call failed or not answered', ChipTone.danger),
          _ when status == VoiceCallStatus.completed => ('Call ended', ChipTone.neutral),
          _ => (status?.label ?? 'Calling…', ChipTone.success),
        };
        return Semantics(
          liveRegion: true,
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Container(
              padding: const EdgeInsets.all(Space.md),
              decoration: BoxDecoration(color: c.surfaceTint, borderRadius: BorderRadius.circular(Radii.card), border: Border.all(color: c.border)),
              child: Row(children: [
                if (live) PulseDot(color: c.success, size: 8) else Icon(Icons.support_agent, size: 18, color: c.muted),
                const SizedBox(width: Space.sm),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                    Text('AI call · $label', style: t.labelLarge, maxLines: 1, overflow: TextOverflow.ellipsis),
                    const SizedBox(height: Space.xs),
                    StatusChip(label: text, tone: tone),
                    if (live && s.mode == 'say' && !s.dryRun) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text('The agent reads a short briefing twice.', style: t.labelSmall?.copyWith(color: c.muted))),
                    if (live && !s.statusUpdates && !s.dryRun) Padding(padding: const EdgeInsets.only(top: Space.xs), child: Text('Live status needs a public PUBLIC_BASE_URL.', style: t.labelSmall?.copyWith(color: c.muted))),
                  ]),
                ),
                if (live && s.callId != null) ...[
                  const SizedBox(width: Space.sm),
                  MgButton(label: 'Hang up', icon: Icons.call_end, kind: MgButtonKind.danger, onPressed: () => bloc.add(const VoiceCallHungUp())),
                ],
              ]),
            ),
            if (!live) ...[const SizedBox(height: Space.sm), button],
          ]),
        );
      },
    );
  }
}

/// One tap from a compact card: the sheet opens and the AI call is placed at the same moment.
Future<void> showAiCallSheet(BuildContext context, {required String targetType, required String targetId, required String targetLabel, String? reason}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (_) => SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(Space.x2, 0, Space.x2, Space.x2),
        child: AiCallButton(targetType: targetType, targetId: targetId, targetLabel: targetLabel, reason: reason, expand: true, autoStart: true),
      ),
    ),
  );
}
