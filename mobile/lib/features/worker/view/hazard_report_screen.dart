import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../../../app/ui/mg_card.dart';
import '../../../app/ui/section_header.dart';
import '../../../app/ui/sync_indicator.dart';
import '../../../contracts/routes.dart';
import '../../../core/api/api_client.dart';
import '../../../core/db/cache_repository.dart';
import '../../../core/db/layout_repository.dart';
import '../../../core/location/location_service.dart';
import '../../../core/socket/socket_service.dart';
import '../../../core/sync/outbox_queue.dart';
import '../../../core/sync/sync_engine.dart';
import '../bloc/checkin_flow_state.dart';
import '../bloc/hazard_report_bloc.dart';
import '../bloc/hazard_report_event.dart';
import '../bloc/hazard_report_state.dart';
import '../data/hazard_repository.dart';
import '../widgets/category_grid.dart';
import '../widgets/location_card.dart';
import '../widgets/metric_chip.dart';
import '../widgets/status_ticker.dart';
import 'camera_view.dart';

class HazardReportScreen extends StatelessWidget {
  const HazardReportScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (ctx) => HazardReportBloc(
        repo: HazardRepository(api: ctx.read<ApiClient>()),
        location: LocationService(),
        socket: ctx.read<SocketService>(),
        layout: LayoutRepository(api: ctx.read<ApiClient>(), cache: ctx.read<CacheRepository>()),
        queue: ctx.read<OutboxQueue>(),
        engine: ctx.read<SyncEngine>(),
      )..add(const HazardStarted()),
      child: const _View(),
    );
  }
}

class _View extends StatefulWidget {
  const _View();

  @override
  State<_View> createState() => _ViewState();
}

class _ViewState extends State<_View> {
  final _picker = ImagePicker();
  final _startedAt = DateTime.now();

  Future<void> _gallery() async {
    final bloc = context.read<HazardReportBloc>();
    try {
      final f = await _picker.pickImage(source: ImageSource.gallery);
      if (f == null) return;
      bloc.add(HazardPhotoSelected(bytes: await f.readAsBytes(), source: 'gallery'));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the gallery')));
    }
  }

  Future<void> _camera() async {
    final bloc = context.read<HazardReportBloc>();
    await Navigator.of(context).push<void>(MaterialPageRoute(
      fullscreenDialog: true,
      builder: (ctx) => Scaffold(
        backgroundColor: Colors.black,
        body: CameraView(
          showSilhouette: false,
          onClose: () => Navigator.of(ctx).pop(),
          onCaptured: (bytes, at) {
            Navigator.of(ctx).pop();
            bloc.add(HazardPhotoSelected(bytes: bytes, source: 'camera', shutterAt: at));
          },
        ),
      ),
    ));
  }

  Widget _photoSection(HazardReportState s) {
    final c = MgColors.of(context);
    final t = Theme.of(context).textTheme;
    final r = s.report;
    if (s.gating) {
      return MgCard(child: Wrap(spacing: Space.sm, runSpacing: Space.sm, children: const [MetricChip(label: 'Sharpness', state: MetricState.checking), MetricChip(label: 'Lighting', state: MetricState.checking), MetricChip(label: 'Timestamp', state: MetricState.checking)]));
    }
    if (r == null) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        MgButton(label: 'Capture with camera', icon: Icons.photo_camera, expand: true, onPressed: _camera),
        const SizedBox(height: Space.md),
        MgButton(label: 'Insert from gallery', kind: MgButtonKind.secondary, icon: Icons.photo_library, expand: true, onPressed: _gallery),
      ]);
    }
    final first = r.firstFailure;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ClipRRect(borderRadius: BorderRadius.circular(Radii.card), child: AspectRatio(aspectRatio: 4 / 3, child: Image.memory(r.uploadBytes, fit: BoxFit.cover, gaplessPlayback: true))),
      const SizedBox(height: Space.md),
      Wrap(spacing: Space.sm, runSpacing: Space.sm, children: [
        MetricChip(label: 'Sharpness', state: r.hasFailure('BLURRY') ? MetricState.fail : MetricState.pass, detail: r.metrics.blurScore.toStringAsFixed(0)),
        MetricChip(label: 'Lighting', state: r.failures.any((f) => const {'DARK', 'BRIGHT', 'EXPOSURE'}.contains(f.code)) ? MetricState.fail : MetricState.pass, delay: const Duration(milliseconds: 80)),
        MetricChip(label: 'Timestamp', state: r.hasFailure('STALE') ? MetricState.fail : MetricState.pass, detail: r.warnings.contains('NO_EXIF') ? 'no EXIF' : null, delay: const Duration(milliseconds: 160)),
      ]),
      if (first != null) ...[
        const SizedBox(height: Space.md),
        Container(padding: const EdgeInsets.all(Space.md), decoration: BoxDecoration(color: c.dangerBg, borderRadius: BorderRadius.circular(Radii.sm)), child: Text(first.message, style: t.bodyMedium?.copyWith(color: c.danger))),
      ],
      const SizedBox(height: Space.md),
      MgButton(label: r.source == 'camera' ? 'Retake photo' : 'Choose another photo', kind: MgButtonKind.secondary, icon: Icons.refresh, expand: true, onPressed: () {
        context.read<HazardReportBloc>().add(const HazardPhotoCleared());
        if (r.source == 'camera') {
          _camera();
        } else {
          _gallery();
        }
      }),
    ]);
  }

  Widget _form(HazardReportState s) {
    final bloc = context.read<HazardReportBloc>();
    final photo = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [const SectionHeader(title: 'Photo', number: 1, subtitle: 'Show the hazard clearly'), _photoSection(s)]);
    final category = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader(title: 'Category', number: 2, subtitle: 'What kind of hazard is it?'),
      CategoryGrid(selected: s.category, onSelected: (c) => bloc.add(HazardCategorySelected(c))),
    ]);
    final location = Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      const SectionHeader(title: 'Location', number: 3),
      LocationCard(state: s, onRefresh: () => bloc.add(const HazardLocationRefreshed())),
    ]);
    final submit = MgButton(label: 'Report hazard', icon: Icons.send, expand: true, onPressed: s.canSubmit ? () => bloc.add(const HazardSubmitted()) : null);
    final progress = Row(children: List.generate(3, (i) {
      final done = i == 0 ? s.photoOk : (i == 1 ? s.category != null : s.locationStatus != LocationStatus.loading);
      return Expanded(child: Container(height: 4, margin: EdgeInsets.only(right: i < 2 ? Space.xs : 0), decoration: BoxDecoration(color: done ? MgColors.of(context).success : MgColors.of(context).border, borderRadius: BorderRadius.circular(2))));
    }));

    if (context.isExpanded) {
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        progress,
        const SizedBox(height: Space.x2),
        Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(flex: 5, child: photo),
          const SizedBox(width: Space.x2),
          Expanded(flex: 7, child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [category, const SizedBox(height: Space.x2), location])),
        ]),
        const SizedBox(height: Space.x2),
        submit,
      ]);
    }
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [progress, const SizedBox(height: Space.x2), photo, const SizedBox(height: Space.x2), category, const SizedBox(height: Space.x2), location, const SizedBox(height: Space.x2), submit]);
  }

  Widget _flowView(HazardReportState s) {
    final f = s.flow!;
    final bloc = context.read<HazardReportBloc>();
    final reachedServer = f.stage.index >= TickerStage.synced.index && f.phase != FlowPhase.failed;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      StatusTicker(state: f, startedAt: _startedAt),
      const SizedBox(height: Space.x2),
      if (f.phase == FlowPhase.failed)
        MgButton(label: 'Retry', icon: Icons.refresh, expand: true, onPressed: () => bloc.add(const HazardRetry())),
      if (reachedServer || f.phase == FlowPhase.queuedOffline) MgButton(label: 'Back to home', icon: Icons.home, expand: true, kind: f.phase == FlowPhase.done ? MgButtonKind.primary : MgButtonKind.secondary, onPressed: () => context.go(Routes.worker)),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return BlocBuilder<HazardReportBloc, HazardReportState>(builder: (context, s) {
      final busy = s.flow != null && s.flow!.phase == FlowPhase.running && s.flow!.stage.index < TickerStage.synced.index;
      return PopScope(
        canPop: !busy,
        child: Scaffold(
          backgroundColor: c.bg,
          appBar: AppBar(
            title: const Text('Report Safety Hazard'),
            leading: busy ? null : IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go(Routes.worker)),
            actions: [SyncIndicator(engine: context.read<SyncEngine>())],
          ),
          body: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: Space.lg),
            child: ContentWidth(maxWidth: 1000, child: s.flow != null ? _flowView(s) : _form(s)),
          ),
        ),
      );
    });
  }
}
