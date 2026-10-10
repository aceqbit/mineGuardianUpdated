import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/success_burst.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/socket/socket_service.dart';
import '../../../core/sync/outbox_queue.dart';
import '../../../core/sync/sync_engine.dart';
import '../bloc/checkin_flow_bloc.dart';
import '../bloc/checkin_flow_event.dart';
import '../bloc/checkin_flow_state.dart';
import '../data/checkin_repository.dart';
import '../data/models/quality_report.dart';
import '../widgets/status_ticker.dart';

/// Full-screen progress for one check-in submission. Pops with `true` when the worker chose to retake.
class CheckinProgressView extends StatelessWidget {
  const CheckinProgressView({super.key, required this.report, required this.attempt});
  final QualityReport report;
  final int attempt;

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => CheckinFlowBloc(repo: CheckinRepository(api: ctx.read<ApiClient>()), socket: ctx.read<SocketService>(), queue: ctx.read<OutboxQueue>(), engine: ctx.read<SyncEngine>())..add(CheckinFlowStarted(report: report, attempt: attempt)),
      child: _View(startedAt: DateTime.now()),
    );
  }
}

class _View extends StatelessWidget {
  const _View({required this.startedAt});
  final DateTime startedAt;

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return BlocBuilder<CheckinFlowBloc, CheckinFlowState>(builder: (context, s) {
      final busy = s.phase == FlowPhase.running;
      return PopScope(
        canPop: !busy,
        child: Scaffold(
          backgroundColor: c.bg,
          appBar: AppBar(title: const Text('Submitting check-in'), automaticallyImplyLeading: !busy),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: Space.x2),
            child: ContentWidth(
              maxWidth: 760,
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                if (s.phase == FlowPhase.done) Center(child: SuccessBurst(size: 96)),
                StatusTicker(state: s, startedAt: startedAt),
                const SizedBox(height: Space.x2),
                ..._actions(context, s),
              ]),
            ),
          ),
        ),
      );
    });
  }

  List<Widget> _actions(BuildContext context, CheckinFlowState s) {
    if (s.phase == FlowPhase.done) {
      return [MgButton(label: 'Back to home', expand: true, icon: Icons.home, onPressed: () => context.go(Routes.worker))];
    }
    if (s.phase == FlowPhase.queuedOffline) {
      return [MgButton(label: 'Back to home', expand: true, onPressed: () => context.go(Routes.worker))];
    }
    if (s.phase == FlowPhase.failed && s.failure != null) {
      switch (s.failure!.action) {
        case FailAction.retakePhoto:
          return [MgButton(label: 'Retake photo', expand: true, icon: Icons.refresh, onPressed: () => Navigator.of(context).pop(true))];
        case FailAction.takeNewPhoto:
          return [MgButton(label: 'Take a new photo', expand: true, icon: Icons.photo_camera, onPressed: () => Navigator.of(context).pop(true))];
        case FailAction.retry:
          return [
            MgButton(label: 'Retry', expand: true, icon: Icons.refresh, onPressed: () => context.read<CheckinFlowBloc>().add(const CheckinFlowRetry())),
            const SizedBox(height: Space.md),
            MgButton(label: 'Back', expand: true, kind: MgButtonKind.secondary, onPressed: () => Navigator.of(context).pop(false)),
          ];
      }
    }
    return const [];
  }
}
