
import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/empty_state.dart';
import '../widgets/self_timer.dart';
import '../widgets/silhouette_overlay.dart';

/// Full-bleed camera preview. Back camera, veryHigh, JPEG. Disposes when inactive, re-initialises on resume.
class CameraView extends StatefulWidget {
  const CameraView({super.key, required this.onCaptured, required this.onClose, this.showSilhouette = true, this.onNoCamera});
  final void Function(Uint8List bytes, DateTime shutterAt) onCaptured;
  final VoidCallback onClose;
  final bool showSilhouette;
  final VoidCallback? onNoCamera;

  @override
  State<CameraView> createState() => _CameraViewState();
}

enum _CamState { init, ready, denied, none, error }

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  CameraController? _ctrl;
  List<CameraDescription> _cams = const [];
  int _index = 0;
  _CamState _state = _CamState.init;
  FlashMode _flash = FlashMode.off;
  bool _timerOn = false;
  bool _busy = false;
  double _zoom = 1, _zoomBase = 1, _minZoom = 1, _maxZoom = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  Future<void> _init({bool keepIndex = false}) async {
    setState(() => _state = _CamState.init);
    try {
      // On web the browser prompts during initialize(); permission_handler has no camera support there.
      final granted = kIsWeb || (await Permission.camera.request()).isGranted;
      if (!granted) {
        if (mounted) setState(() => _state = _CamState.denied);
        return;
      }
      _cams = await availableCameras();
      if (_cams.isEmpty) {
        if (mounted) setState(() => _state = _CamState.none);
        widget.onNoCamera?.call();
        return;
      }
      if (!keepIndex) {
        final back = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        _index = back >= 0 ? back : 0;
      }
      final c = CameraController(_cams[_index], ResolutionPreset.veryHigh, enableAudio: false, imageFormatGroup: ImageFormatGroup.jpeg);
      await c.initialize();
      await c.setFlashMode(_flash);
      try {
        _minZoom = await c.getMinZoomLevel();
        _maxZoom = await c.getMaxZoomLevel();
        _zoom = _minZoom;
      } catch (_) {}
      if (!mounted) {
        await c.dispose();
        return;
      }
      setState(() {
        _ctrl = c;
        _state = _CamState.ready;
      });
    } catch (_) {
      if (mounted) setState(() => _state = _CamState.error);
      widget.onNoCamera?.call();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (state == AppLifecycleState.inactive) {
      _ctrl = null;
      c?.dispose();
      if (mounted) setState(() => _state = _CamState.init);
    } else if (state == AppLifecycleState.resumed && _ctrl == null) {
      _init(keepIndex: true);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _ctrl?.dispose();
    super.dispose();
  }

  Future<void> _shoot() async {
    final c = _ctrl;
    if (c == null || _busy || !c.value.isInitialized) return;
    _busy = true;
    try {
      HapticFeedback.mediumImpact();
      final at = DateTime.now().toUtc();
      final file = await c.takePicture();
      final bytes = await file.readAsBytes();
      if (mounted) widget.onCaptured(bytes, at);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not take the photo. Try again.')));
    } finally {
      _busy = false;
      if (mounted) setState(() => _timerOn = false);
    }
  }

  Future<void> _cycleFlash() async {
    final next = switch (_flash) { FlashMode.off => FlashMode.auto, FlashMode.auto => FlashMode.torch, _ => FlashMode.off };
    try {
      await _ctrl?.setFlashMode(next);
      setState(() => _flash = next);
    } catch (_) {}
  }

  Future<void> _switch() async {
    if (_cams.length < 2) return;
    _index = (_index + 1) % _cams.length;
    await _ctrl?.dispose();
    _ctrl = null;
    await _init(keepIndex: true);
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    Widget body;
    switch (_state) {
      case _CamState.init:
        body = const Center(child: CircularProgressIndicator());
      case _CamState.denied:
        body = EmptyState(icon: Icons.no_photography, title: 'Camera permission needed', message: 'Allow camera access to take your shift photo.', actionLabel: 'Open settings', onAction: openAppSettings);
      case _CamState.none:
        body = const EmptyState(icon: Icons.videocam_off, title: 'No camera found', message: 'Use "Insert from gallery" instead.');
      case _CamState.error:
        body = EmptyState(icon: Icons.error_outline, title: 'Camera problem', message: 'Could not start the camera.', actionLabel: 'Try again', onAction: _init);
      case _CamState.ready:
        final ctrl = _ctrl!;
        body = Stack(fit: StackFit.expand, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) => _zoomBase = _zoom,
            onScaleUpdate: (d) async {
              final z = (_zoomBase * d.scale).clamp(_minZoom, _maxZoom);
              if (z == _zoom) return;
              _zoom = z;
              try {
                await ctrl.setZoomLevel(z);
              } catch (_) {}
            },
            child: ColoredBox(color: Colors.black, child: Center(child: CameraPreview(ctrl))),
          ),
          if (widget.showSilhouette) const SilhouetteOverlay(),
          if (widget.showSilhouette)
            Positioned(
              left: Space.lg,
              right: Space.lg,
              top: Space.lg + 40,
              child: Text('Stand 2–3 m away · head to boots inside the outline', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Colors.white, shadows: const [Shadow(blurRadius: 8, color: Colors.black87)])),
            ),
          if (_timerOn) SelfTimer(onDone: _shoot),
          Positioned(
            left: 0,
            right: 0,
            bottom: Space.x2,
            child: Row(mainAxisAlignment: MainAxisAlignment.spaceEvenly, children: [
              _RoundBtn(icon: switch (_flash) { FlashMode.off => Icons.flash_off, FlashMode.auto => Icons.flash_auto, _ => Icons.flashlight_on }, tooltip: 'Flash', onTap: _cycleFlash),
              _RoundBtn(icon: _timerOn ? Icons.timer_off : Icons.timer, tooltip: '5 second self-timer', onTap: () => setState(() => _timerOn = !_timerOn)),
              Semantics(
                button: true,
                label: 'Take photo',
                child: GestureDetector(
                  onTap: _timerOn ? null : _shoot,
                  child: Container(width: 76, height: 76, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: c.amber500, width: 5))),
                ),
              ),
              _RoundBtn(icon: Icons.cameraswitch, tooltip: 'Switch camera', onTap: _cams.length > 1 ? _switch : null),
            ]),
          ),
        ]);
    }
    return Container(
      color: _state == _CamState.ready ? Colors.black : c.bg,
      child: Stack(children: [
        Positioned.fill(child: body),
        Positioned(top: Space.sm, left: Space.sm, child: SafeArea(child: IconButton.filledTonal(tooltip: 'Close camera', onPressed: widget.onClose, icon: const Icon(Icons.close)))),
      ]),
    );
  }
}

class _RoundBtn extends StatelessWidget {
  const _RoundBtn({required this.icon, required this.tooltip, required this.onTap});
  final IconData icon;
  final String tooltip;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(tooltip: tooltip, iconSize: 28, onPressed: onTap, icon: Icon(icon));
}
