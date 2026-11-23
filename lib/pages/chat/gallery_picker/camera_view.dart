// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:camera/camera.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/gallery_picker/picked_media.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:photo_manager/photo_manager.dart';

/// Whether the shutter takes a still photo or starts and stops a video.
enum CaptureMode { photo, video }

/// Live camera viewfinder shown at the top of the gallery picker while
/// nothing is selected (or after the user asks for the camera again).
///
/// The widget owns its [CameraController]: it creates one in [State.initState]
/// and disposes it when the widget leaves the tree, so the parent can simply
/// stop building this view to release the camera. Following the camera
/// package guidance, the controller is also released when the app becomes
/// inactive and recreated on resume, because Android hands the camera to
/// other apps while this one is in the background.
class CameraView extends StatefulWidget {
  /// Called with every photo taken and every finished video recording.
  final ValueChanged<CapturedMedia> onCaptured;

  /// Called by the close button in the top bar.
  final VoidCallback onClose;

  /// Another permission request to let finish before the camera asks for
  /// its own. Android shows one permission dialog at a time and fails a
  /// second request made while the first is open.
  final Future<Object?>? waitFor;

  const CameraView({
    required this.onCaptured,
    required this.onClose,
    this.waitFor,
    super.key,
  });

  @override
  State<CameraView> createState() => _CameraViewState();
}

class _CameraViewState extends State<CameraView> with WidgetsBindingObserver {
  /// Zoom presets offered as chips; each is shown only when the active lens
  /// supports it.
  static const List<double> _zoomPresets = [0.5, 1.0, 2.0];

  List<CameraDescription> _cameras = const [];
  int _cameraIndex = 0;
  CameraController? _controller;

  /// Bumped on every (re)initialisation so a slow initialise that finishes
  /// after a newer one started can tell it is stale and dispose itself.
  int _generation = 0;

  /// Camera to reopen on resume after the app went inactive.
  CameraDescription? _pausedDescription;

  bool _failed = false;
  bool _busy = false;
  bool _recording = false;
  bool _flashOn = false;
  CaptureMode _mode = CaptureMode.photo;
  double _minZoom = 1;
  double _maxZoom = 1;
  double _zoom = 1;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _setup();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _generation++;
    _controller?.dispose();
    _controller = null;
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final controller = _controller;
    if (state == AppLifecycleState.inactive) {
      // A controller that is still initialising (for example while the
      // permission dialog makes the app inactive) is left alone.
      if (controller == null || !controller.value.isInitialized) return;
      _pausedDescription = controller.description;
      _generation++;
      setState(() {
        _controller = null;
        _recording = false;
        _busy = false;
      });
      controller.dispose();
    } else if (state == AppLifecycleState.resumed) {
      final description = _pausedDescription;
      _pausedDescription = null;
      if (description != null) _initController(description);
    }
  }

  Future<void> _setup() async {
    try {
      await widget.waitFor;
    } catch (_) {
      // Only the ordering matters here; the other request reports its own
      // failure.
    }
    if (!mounted) return;
    try {
      _cameras = await availableCameras();
    } on CameraException catch (e, s) {
      Logs().w('Unable to list cameras', e, s);
      _cameras = const [];
    }
    if (!mounted) return;
    if (_cameras.isEmpty) {
      setState(() => _failed = true);
      return;
    }
    final back = _cameras.indexWhere(
      (camera) => camera.lensDirection == CameraLensDirection.back,
    );
    _cameraIndex = back == -1 ? 0 : back;
    await _initController(_cameras[_cameraIndex]);
  }

  Future<void> _initController(CameraDescription description) async {
    final generation = ++_generation;
    final previous = _controller;
    if (previous != null) {
      setState(() => _controller = null);
      await previous.dispose();
    }

    var controller = CameraController(description, ResolutionPreset.high);
    try {
      try {
        await controller.initialize();
      } on CameraException catch (e) {
        // Microphone access is only needed for video sound. If it was
        // refused, keep the camera usable and record silent video instead.
        if (!e.code.contains('Audio')) rethrow;
        await controller.dispose();
        controller = CameraController(
          description,
          ResolutionPreset.high,
          enableAudio: false,
        );
        await controller.initialize();
      }
    } on CameraException catch (e, s) {
      Logs().w('Unable to open camera', e, s);
      await controller.dispose();
      if (mounted && generation == _generation) {
        setState(() => _failed = true);
      }
      return;
    }

    if (!mounted || generation != _generation) {
      await controller.dispose();
      return;
    }

    var minZoom = 1.0;
    var maxZoom = 1.0;
    try {
      minZoom = await controller.getMinZoomLevel();
      maxZoom = await controller.getMaxZoomLevel();
    } on CameraException catch (e, s) {
      Logs().w('Unable to read zoom range', e, s);
    }
    await _applyFlash(controller);

    if (!mounted || generation != _generation) {
      await controller.dispose();
      return;
    }
    setState(() {
      _controller = controller;
      _failed = false;
      _minZoom = minZoom;
      _maxZoom = maxZoom;
      _zoom = 1.0.clamp(minZoom, maxZoom);
    });
  }

  /// Flash fires once per photo, but video needs the torch held on.
  Future<void> _applyFlash(CameraController controller) async {
    final mode = !_flashOn
        ? FlashMode.off
        : _mode == CaptureMode.video
        ? FlashMode.torch
        : FlashMode.always;
    try {
      await controller.setFlashMode(mode);
    } on CameraException catch (e, s) {
      // Front cameras usually have no flash; the toggle then has no effect.
      Logs().w('Unable to set flash mode', e, s);
    }
  }

  void _toggleFlash() {
    setState(() => _flashOn = !_flashOn);
    final controller = _controller;
    if (controller != null) _applyFlash(controller);
  }

  void _setMode(CaptureMode mode) {
    if (_recording || mode == _mode) return;
    setState(() => _mode = mode);
    final controller = _controller;
    if (controller != null) _applyFlash(controller);
  }

  void _switchCamera() {
    if (_cameras.length < 2 || _recording || _busy) return;
    _cameraIndex = (_cameraIndex + 1) % _cameras.length;
    _initController(_cameras[_cameraIndex]);
  }

  Future<void> _setZoom(double level) async {
    final controller = _controller;
    if (controller == null) return;
    setState(() => _zoom = level);
    try {
      await controller.setZoomLevel(level);
    } on CameraException catch (e, s) {
      Logs().w('Unable to set zoom', e, s);
    }
  }

  /// Width over height of the captured media held upright. The controller
  /// reports the sensor's landscape ratio, so it is inverted for portrait.
  double _portraitAspect(CameraController controller) {
    final ratio = controller.value.aspectRatio;
    return ratio > 0 ? 1 / ratio : 3 / 4;
  }

  Future<void> _onShutter() async {
    final controller = _controller;
    if (controller == null || _busy) return;
    setState(() => _busy = true);
    try {
      if (_mode == CaptureMode.photo) {
        final file = await controller.takePicture();
        widget.onCaptured(
          CapturedMedia(
            file: XFile(file.path, mimeType: 'image/jpeg'),
            isVideo: false,
            aspectRatio: _portraitAspect(controller),
          ),
        );
      } else if (_recording) {
        final file = await controller.stopVideoRecording();
        if (mounted) setState(() => _recording = false);
        widget.onCaptured(
          CapturedMedia(
            file: XFile(
              file.path,
              mimeType: file.path.toLowerCase().endsWith('.mov')
                  ? 'video/quicktime'
                  : 'video/mp4',
            ),
            isVideo: true,
            aspectRatio: _portraitAspect(controller),
          ),
        );
      } else {
        await controller.prepareForVideoRecording();
        await controller.startVideoRecording();
        if (mounted) setState(() => _recording = true);
      }
    } on CameraException catch (e, s) {
      Logs().w('Camera capture failed', e, s);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final controller = _controller;
    final zoomLevels = _zoomPresets
        .where((level) => level >= _minZoom - 0.01 && level <= _maxZoom + 0.01)
        .toList();

    return Stack(
      fit: StackFit.expand,
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(28),
          child: ColoredBox(
            color: theme.colorScheme.surfaceContainerLowest,
            child: _failed
                ? _CameraUnavailable(message: l10n.allowCameraAccess)
                : controller == null
                ? const SizedBox.shrink()
                : _CoverPreview(controller: controller),
          ),
        ),
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          child: SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.all(8),
              child: Row(
                children: [
                  IconButton(
                    tooltip: l10n.close,
                    icon: const Icon(Icons.close),
                    onPressed: widget.onClose,
                  ),
                  const Spacer(),
                  if (controller != null)
                    IconButton(
                      tooltip: _flashOn ? l10n.flashOn : l10n.flashOff,
                      icon: Icon(_flashOn ? Icons.flash_on : Icons.flash_off),
                      onPressed: _toggleFlash,
                    ),
                ],
              ),
            ),
          ),
        ),
        if (!_failed)
          Positioned(
            left: 0,
            right: 0,
            bottom: 20,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                if (zoomLevels.length > 1) ...[
                  _ZoomChips(
                    levels: zoomLevels,
                    selected: _zoom,
                    onSelected: _setZoom,
                  ),
                  const SizedBox(height: 24),
                ],
                Row(
                  children: [
                    const Spacer(),
                    _ShutterButton(
                      mode: _mode,
                      recording: _recording,
                      onPressed: controller == null ? null : _onShutter,
                    ),
                    Expanded(
                      child: Center(
                        child: _cameras.length > 1
                            ? _SwitchCameraButton(
                                tooltip: l10n.switchCamera,
                                onPressed: _recording || _busy
                                    ? null
                                    : _switchCamera,
                              )
                            : null,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _ModeChip(
                      label: l10n.photo,
                      selected: _mode == CaptureMode.photo,
                      onTap: () => _setMode(CaptureMode.photo),
                    ),
                    const SizedBox(width: 8),
                    _ModeChip(
                      label: l10n.video,
                      selected: _mode == CaptureMode.video,
                      onTap: () => _setMode(CaptureMode.video),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Scales the preview to cover its box the way a system camera does,
/// cropping whatever overflows instead of letterboxing.
class _CoverPreview extends StatelessWidget {
  final CameraController controller;

  const _CoverPreview({required this.controller});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) => SizedBox.expand(
      child: FittedBox(
        fit: BoxFit.cover,
        clipBehavior: Clip.hardEdge,
        child: SizedBox(
          width: constraints.maxWidth,
          child: CameraPreview(controller),
        ),
      ),
    ),
  );
}

/// Shown in place of the viewfinder when there is no camera or the camera
/// permission was refused. Opening the app settings lets the user grant it.
class _CameraUnavailable extends StatelessWidget {
  final String message;

  const _CameraUnavailable({required this.message});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.no_photography_outlined,
              size: 48,
              color: theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 16),
            Text(
              message,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonal(
              onPressed: PhotoManager.openSetting,
              child: Text(L10n.of(context).openSettings),
            ),
          ],
        ),
      ),
    );
  }
}

/// Row of zoom presets in a translucent pill over the viewfinder.
class _ZoomChips extends StatelessWidget {
  final List<double> levels;
  final double selected;
  final ValueChanged<double> onSelected;

  const _ZoomChips({
    required this.levels,
    required this.selected,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.scrim.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 12,
          children: [
            for (final level in levels)
              _ZoomChip(
                label: level.toStringAsFixed(1),
                selected: (level - selected).abs() < 0.01,
                onTap: () => onSelected(level),
              ),
          ],
        ),
      ),
    );
  }
}

class _ZoomChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ZoomChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 44,
        height: 44,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: selected
              ? theme.colorScheme.primaryContainer
              : theme.colorScheme.scrim.withValues(alpha: 0.3),
        ),
        child: Text(
          label,
          style: theme.textTheme.labelLarge?.copyWith(
            color: selected
                ? theme.colorScheme.onPrimaryContainer
                : theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// The 80dp shutter: a white ring around a white disc for photos, a red disc
/// for video, and a red rounded square while recording. White and red are
/// fixed on purpose: they are the universal camera affordances and must stay
/// legible over any scene, whatever the app's colour scheme.
class _ShutterButton extends StatelessWidget {
  final CaptureMode mode;
  final bool recording;
  final VoidCallback? onPressed;

  const _ShutterButton({
    required this.mode,
    required this.recording,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final video = mode == CaptureMode.video;
    final innerSize = recording ? 32.0 : 64.0;
    return Semantics(
      button: true,
      child: GestureDetector(
        onTap: onPressed,
        child: Container(
          width: 80,
          height: 80,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 4),
          ),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            curve: Curves.easeOutCubic,
            width: innerSize,
            height: innerSize,
            decoration: BoxDecoration(
              color: video ? Colors.red.shade600 : Colors.white,
              borderRadius: BorderRadius.circular(recording ? 8 : 32),
            ),
          ),
        ),
      ),
    );
  }
}

class _SwitchCameraButton extends StatelessWidget {
  final String tooltip;
  final VoidCallback? onPressed;

  const _SwitchCameraButton({required this.tooltip, required this.onPressed});

  @override
  Widget build(BuildContext context) => IconButton(
    tooltip: tooltip,
    onPressed: onPressed,
    iconSize: 32,
    style: IconButton.styleFrom(
      fixedSize: const Size.square(56),
      side: BorderSide(
        color: Theme.of(context).colorScheme.onSurface,
        width: 2,
      ),
    ),
    icon: const Icon(Icons.cameraswitch_outlined),
  );
}

/// One half of the Photo / Video toggle; the active half sits in a filled
/// tonal pill.
class _ModeChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _ModeChip({
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      type: MaterialType.transparency,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(24),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 200),
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? theme.colorScheme.secondaryContainer
                : Colors.transparent,
            borderRadius: BorderRadius.circular(24),
          ),
          child: Text(
            label,
            style: theme.textTheme.titleMedium?.copyWith(
              color: selected
                  ? theme.colorScheme.onSecondaryContainer
                  : theme.colorScheme.onSurface,
            ),
          ),
        ),
      ),
    );
  }
}
