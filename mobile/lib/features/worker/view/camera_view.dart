import 'dart:async';

import 'package:camera/camera.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:permission_handler/permission_handler.dart';

import '../../../app/theme/tokens.dart';
import '../../../app/ui/mg_button.dart';
import '../widgets/self_timer.dart';
import '../widgets/silhouette_overlay.dart';

/// Full-bleed live camera. Required steps (permission, camera list, initialise) are separated from optional ones
/// (flash, zoom) so a platform that lacks flash/zoom (web) still gets a working preview. Resolution steps down
/// when the device refuses the first choice, init has a timeout, and every failure ends on a screen with a way
/// forward (retry, the device's own camera app, or back to the gallery) instead of a spinner.
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

const _initTimeout = Duration(seconds: 15);
const _resolutions = [ResolutionPreset.veryHigh, ResolutionPreset.high, ResolutionPreset.medium];

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  CameraController? _ctrl;
  List<CameraDescription> _cams = const [];
  int _index = 0;
  int _initRun = 0;
  _CamState _state = _CamState.init;
  String? _detail;
  FlashMode _flash = FlashMode.off;
  bool _flashOk = false;
  bool _zoomOk = false;
  bool _timerOn = false;
  bool _busy = false;
  double _zoom = 1, _zoomBase = 1, _minZoom = 1, _maxZoom = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  static bool _isDenied(Object e) {
    final s = e is CameraException ? '${e.code} ${e.description}' : '$e';
    final l = s.toLowerCase();
    return l.contains('denied') || l.contains('notallowed') || l.contains('permission');
  }

  Future<void> _init({bool keepIndex = false}) async {
    final run = ++_initRun;
    bool stale() => !mounted || run != _initRun;
    setState(() {
      _state = _CamState.init;
      _detail = null;
    });
    try {
      // On web the browser prompts during initialize(); permission_handler has no camera support there.
      final granted = kIsWeb || (await Permission.camera.request()).isGranted;
      if (stale()) return;
      if (!granted) {
        setState(() => _state = _CamState.denied);
        return;
      }
      try {
        _cams = await availableCameras().timeout(_initTimeout);
      } on CameraException catch (e) {
        if (stale()) return;
        setState(() => _state = _isDenied(e) ? _CamState.denied : _CamState.none);
        if (!_isDenied(e)) widget.onNoCamera?.call();
        return;
      }
      if (stale()) return;
      if (_cams.isEmpty) {
        setState(() => _state = _CamState.none);
        widget.onNoCamera?.call();
        return;
      }
      if (!keepIndex) {
        final back = _cams.indexWhere((c) => c.lensDirection == CameraLensDirection.back);
        _index = back >= 0 ? back : 0;
      }

      // Required: a controller that initialises. Step the resolution down if the device refuses.
      CameraController? ready;
      Object? lastError;
      for (final preset in _resolutions) {
        final c = CameraController(_cams[_index], preset, enableAudio: false, imageFormatGroup: kIsWeb ? null : ImageFormatGroup.jpeg);
        try {
          await c.initialize().timeout(_initTimeout);
          ready = c;
          break;
        } catch (e) {
          lastError = e;
          unawaited(c.dispose().catchError((_) {}));
          if (_isDenied(e)) {
            if (!stale()) setState(() => _state = _CamState.denied);
            return;
          }
        }
      }
      if (stale()) {
        unawaited(ready?.dispose().catchError((_) {}) ?? Future<void>.value());
        return;
      }
      if (ready == null) {
        setState(() {
          _state = _CamState.error;
          _detail = lastError is CameraException ? lastError.code : (lastError is TimeoutException ? 'timeout' : null);
        });
        return;
      }

      // Optional: each capability is probed on its own and simply hidden when unsupported.
      _flashOk = false;
      _zoomOk = false;
      if (!kIsWeb) {
        try {
          await ready.setFlashMode(_flash);
          _flashOk = true;
        } catch (_) {}
      }
      try {
        _minZoom = await ready.getMinZoomLevel();
        _maxZoom = await ready.getMaxZoomLevel();
        _zoom = _minZoom;
        _zoomOk = _maxZoom > _minZoom;
      } catch (_) {}

      if (stale()) {
        unawaited(ready.dispose().catchError((_) {}));
        return;
      }
      setState(() {
        _ctrl = ready;
        _state = _CamState.ready;
      });
    } catch (e) {
      if (stale()) return;
      setState(() {
        _state = _isDenied(e) ? _CamState.denied : _CamState.error;
        _detail = e is CameraException ? e.code : null;
      });
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final c = _ctrl;
    if (state == AppLifecycleState.inactive) {
      _initRun++;
      _ctrl = null;
      unawaited(c?.dispose().catchError((_) {}) ?? Future<void>.value());
      if (mounted) setState(() => _state = _CamState.init);
    } else if (state == AppLifecycleState.resumed && _ctrl == null) {
      _init(keepIndex: true);
    }
  }

  @override
  void dispose() {
    _initRun++;
    WidgetsBinding.instance.removeObserver(this);
    final c = _ctrl;
    if (c != null) unawaited(c.dispose().catchError((_) {}));
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

  /// The device's own camera (phone camera app, or the browser's capture dialog) as a way forward when live preview fails.
  Future<void> _deviceCamera() async {
    try {
      final f = await ImagePicker().pickImage(source: ImageSource.camera);
      if (f == null) return;
      final at = DateTime.now().toUtc();
      final bytes = await f.readAsBytes();
      if (mounted) widget.onCaptured(bytes, at);
    } catch (_) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Could not open the camera')));
    }
  }

  Future<void> _cycleFlash() async {
    final next = switch (_flash) { FlashMode.off => FlashMode.auto, FlashMode.auto => FlashMode.torch, _ => FlashMode.off };
    try {
      await _ctrl?.setFlashMode(next);
      if (mounted) setState(() => _flash = next);
    } catch (_) {}
  }

  Future<void> _switch() async {
    if (_cams.length < 2) return;
    _index = (_index + 1) % _cams.length;
    final old = _ctrl;
    _ctrl = null;
    await old?.dispose().catchError((_) {});
    await _init(keepIndex: true);
  }

  Widget _problem(BuildContext context, {required IconData icon, required String title, required String message, bool retry = true, bool settings = false}) {
    final t = Theme.of(context).textTheme;
    final c = MgColors.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(Space.x2),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: Widths.form),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Icon(icon, size: 48, color: c.muted),
            const SizedBox(height: Space.md),
            Text(title, textAlign: TextAlign.center, style: t.headlineSmall),
            const SizedBox(height: Space.sm),
            Text(message, textAlign: TextAlign.center, style: t.bodyMedium),
            if (_detail != null) ...[const SizedBox(height: Space.xs), Text('(${_detail!})', textAlign: TextAlign.center, style: t.bodySmall)],
            const SizedBox(height: Space.x2),
            if (retry) MgButton(label: 'Try again', icon: Icons.refresh, expand: true, onPressed: () => _init(keepIndex: true)),
            if (settings && !kIsWeb) ...[const SizedBox(height: Space.md), MgButton(label: 'Open settings', icon: Icons.settings, expand: true, kind: MgButtonKind.secondary, onPressed: openAppSettings)],
            const SizedBox(height: Space.md),
            MgButton(label: 'Use the device camera', icon: Icons.photo_camera_outlined, expand: true, kind: MgButtonKind.secondary, onPressed: _deviceCamera),
            const SizedBox(height: Space.md),
            MgButton(label: 'Back to choose from gallery', icon: Icons.photo_library_outlined, expand: true, kind: MgButtonKind.ghost, onPressed: widget.onClose),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = MgColors.of(context);
    Widget body;
    switch (_state) {
      case _CamState.init:
        body = Center(
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const CircularProgressIndicator(),
            const SizedBox(height: Space.lg),
            Text(kIsWeb ? 'Allow camera access in your browser…' : 'Starting camera…', style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: Space.lg),
            TextButton(onPressed: widget.onClose, child: const Text('Cancel')),
          ]),
        );
      case _CamState.denied:
        body = _problem(
          context,
          icon: Icons.no_photography,
          title: 'Camera permission needed',
          message: kIsWeb ? 'Click the camera icon in the address bar, choose Allow, then try again.' : 'Allow camera access in settings to take your photo.',
          settings: true,
        );
      case _CamState.none:
        body = _problem(context, icon: Icons.videocam_off, title: 'No camera found', message: 'This device has no camera we can use live.', retry: false);
      case _CamState.error:
        body = _problem(context, icon: Icons.error_outline, title: 'Camera could not start', message: 'Another app may be using it. Try again, or use the device camera.');
      case _CamState.ready:
        final ctrl = _ctrl!;
        body = Stack(fit: StackFit.expand, children: [
          GestureDetector(
            behavior: HitTestBehavior.opaque,
            onScaleStart: (_) => _zoomBase = _zoom,
            onScaleUpdate: (d) async {
              if (!_zoomOk) return;
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
              if (_flashOk) _RoundBtn(icon: switch (_flash) { FlashMode.off => Icons.flash_off, FlashMode.auto => Icons.flash_auto, _ => Icons.flashlight_on }, tooltip: 'Flash', onTap: _cycleFlash),
              _RoundBtn(icon: _timerOn ? Icons.timer_off : Icons.timer, tooltip: '5 second self-timer', onTap: () => setState(() => _timerOn = !_timerOn)),
              Semantics(
                button: true,
                label: 'Take photo',
                child: GestureDetector(
                  onTap: _timerOn ? null : _shoot,
                  child: Container(width: 76, height: 76, decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.white, border: Border.all(color: c.amber500, width: 5))),
                ),
              ),
              if (_cams.length > 1) _RoundBtn(icon: Icons.cameraswitch, tooltip: 'Switch camera', onTap: _switch),
              _RoundBtn(icon: Icons.photo_camera_outlined, tooltip: 'Use the device camera instead', onTap: _deviceCamera),
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
