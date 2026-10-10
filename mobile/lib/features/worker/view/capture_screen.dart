import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart';

import '../../../app/app_images.dart';
import '../../../app/responsive.dart';
import '../../../app/theme/tokens.dart';
import '../../../app/ui/media_tile.dart';
import '../../../app/ui/section_header.dart';
import '../../../contracts/routes.dart';
import '../bloc/capture_bloc.dart';
import '../bloc/capture_event.dart';
import '../bloc/capture_state.dart';
import '../data/models/quality_report.dart';
import '../data/quality_config.dart';
import 'camera_view.dart';
import 'checkin_progress_view.dart';
import 'photo_review_view.dart';

/// Called when the worker submits a passed photo. The check-in flow (P1.6) provides the real implementation.
typedef SubmitCheckin = void Function(BuildContext context, QualityReport report, int attempt);

class CaptureScreen extends StatelessWidget {
  const CaptureScreen({super.key, this.onSubmit});
  final SubmitCheckin? onSubmit;

  @override
  Widget build(BuildContext context) => BlocProvider(create: (_) => CaptureBloc(), child: _CaptureView(onSubmit: onSubmit));
}

class _CaptureView extends StatefulWidget {
  const _CaptureView({this.onSubmit});
  final SubmitCheckin? onSubmit;

  @override
  State<_CaptureView> createState() => _CaptureViewState();
}

class _CaptureViewState extends State<_CaptureView> {
  final _picker = ImagePicker();
  bool _noCamera = false;

  Future<void> _pickGallery() async {
    try {
      final f = await _picker.pickImage(source: ImageSource.gallery);
      if (f == null || !mounted) return;
      final bytes = await f.readAsBytes();
      if (mounted) context.read<CaptureBloc>().add(PhotoSelected(bytes: bytes, source: 'gallery'));
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the gallery')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    return BlocBuilder<CaptureBloc, CaptureState>(builder: (context, s) {
      if (s.phase == CapturePhase.camera) {
        return Scaffold(
          backgroundColor: Colors.black,
          body: CameraView(
            onClose: () => context.read<CaptureBloc>().add(const CameraClosed()),
            onCaptured: (bytes, at) => context.read<CaptureBloc>().add(PhotoSelected(bytes: bytes, source: 'camera', shutterAt: at)),
            onNoCamera: () => setState(() => _noCamera = true),
          ),
        );
      }
      final inReview = s.phase == CapturePhase.review || s.phase == CapturePhase.gating;
      return Scaffold(
        backgroundColor: c.bg,
        appBar: AppBar(
          title: Text(inReview ? 'Review photo' : 'Capture Shift Photo'),
          leading: IconButton(icon: const Icon(Icons.arrow_back), tooltip: 'Back', onPressed: () => context.canPop() ? context.pop() : context.go(Routes.worker)),
          actions: [if (s.attempt > 1) Padding(padding: const EdgeInsets.only(right: Space.lg), child: Center(child: Text('Attempt ${s.attempt}', style: Theme.of(context).textTheme.labelMedium)))],
        ),
        body: inReview
            ? PhotoReviewView(
                report: s.report,
                mode: GateMode.checkin,
                gating: s.phase == CapturePhase.gating,
                cameraAvailable: !_noCamera,
                onRetake: () => context.read<CaptureBloc>().add(const RetakeRequested(toCamera: true)),
                onChooseAnother: () {
                  context.read<CaptureBloc>().add(const RetakeRequested());
                  _pickGallery();
                },
                onSwitchToCamera: () => context.read<CaptureBloc>().add(const RetakeRequested(toCamera: true)),
                onSubmit: () async {
                  final r = s.report;
                  if (r == null) return;
                  final bloc = context.read<CaptureBloc>();
                  final retake = await Navigator.of(context).push<bool>(MaterialPageRoute(builder: (_) => CheckinProgressView(report: r, attempt: s.attempt)));
                  if (retake == true) bloc.add(const RetakeRequested(toCamera: true));
                },
              )
            : _menu(context),
      );
    });
  }

  Widget _menu(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: Space.lg),
      child: ContentWidth(
        maxWidth: 900,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          const SectionHeader(title: 'How would you like to add your photo?', subtitle: 'Stand 2–3 m away so your whole body, head to boots, is visible.'),
          AdaptiveGrid(minTileWidth: 240, maxColumns: 2, aspectRatio: 1.5, children: [
            if (!_noCamera)
              MediaTile(imageUrl: AppImages.capture, icon: Icons.photo_camera, title: 'Capture with camera', subtitle: 'Recommended', aspectRatio: 1.5, onTap: () => context.read<CaptureBloc>().add(const CameraOpened())),
            MediaTile(imageUrl: AppImages.supervisorFeed, icon: Icons.photo_library, title: 'Insert from gallery', subtitle: 'Photo must be fresh', aspectRatio: 1.5, onTap: _pickGallery),
          ]),
        ]),
      ),
    );
  }
}
