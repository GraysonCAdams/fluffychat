// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/file_description.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/utils/video_poster.dart';
import 'package:fluffychat/widgets/blur_hash.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player/video_player.dart';

import '../../../utils/error_reporter.dart';
import '../../image_viewer/image_viewer.dart';
import '../../image_viewer/video_player.dart' as viewer;

/// The size of a video bubble showing a video of [aspectRatio] (width over
/// height): the video's own shape, no larger than [maxWidth] by [maxHeight].
/// Extreme shapes are clamped so a bubble never becomes a sliver; the video
/// is then cropped to fill it. Without an aspect ratio the bubble is 16:9.
Size videoBubbleSize(
  double? aspectRatio, {
  double maxWidth = 280,
  double maxHeight = 320,
}) {
  final ratio =
      (aspectRatio == null || !aspectRatio.isFinite || aspectRatio <= 0
              ? 16 / 9
              : aspectRatio)
          .clamp(minAspectRatio, maxAspectRatio);
  var width = maxWidth;
  var height = width / ratio;
  if (height > maxHeight) {
    height = maxHeight;
    width = height * ratio;
  }
  return Size(width, height);
}

/// The narrowest and widest shapes a video bubble takes.
const minAspectRatio = 9 / 21;
const maxAspectRatio = 21 / 9;

/// The shape of [event]'s video as sent: the thumbnail's size first, since a
/// thumbnail is a frame as it is shown, then the video's own `w` and `h`.
/// Phones record portrait video as landscape frames plus a rotation, and some
/// clients report those raw frame sizes, which the thumbnail does not have.
double? sentVideoAspectRatio(Event event) {
  double? ratio(Map<String, Object?> info) {
    final w = info.tryGet<int>('w');
    final h = info.tryGet<int>('h');
    if (w == null || h == null || w <= 0 || h <= 0) return null;
    return w / h;
  }

  return ratio(event.thumbnailInfoMap) ?? ratio(event.infoMap);
}

/// A video in the timeline, in a bubble of the video's own shape. Its
/// poster frame shows until it plays. Where video playback is supported and
/// [playInline] is set, the centre button plays and pauses the video in
/// place, the corner button mutes it, and a tap anywhere else opens the full
/// screen viewer at the same position. Without [playInline] any tap opens
/// the viewer. Where playback is unsupported a tap saves the file.
class EventVideoPlayer extends StatefulWidget {
  final Event event;
  final Timeline? timeline;
  final Color? textColor;
  final Color? linkColor;

  /// Whether the video plays inside the message. Set for messages in the
  /// chat timeline.
  final bool playInline;

  /// Makes the player for this video. Defaults to downloading the file;
  /// tests pass a fake.
  final Future<VideoPlayerController> Function(
    Event event,
    void Function(double? progress) onProgress,
  )?
  loadController;

  const EventVideoPlayer(
    this.event, {
    this.timeline,
    this.textColor,
    this.linkColor,
    this.playInline = false,
    this.loadController,
    super.key,
  });

  @override
  State<EventVideoPlayer> createState() => _EventVideoPlayerState();
}

class _EventVideoPlayerState extends State<EventVideoPlayer> {
  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  /// The shape of each video once its player has measured it, so a bubble
  /// built again later starts at the right size.
  static final _measuredAspectRatios = <String, double>{};

  /// Whether inline videos play without sound. A choice made on one video
  /// carries over to the next one played in this session.
  static bool _muted = false;

  VideoPlayerController? _controller;
  bool _loading = false;
  double? _downloadProgress;
  bool _controlsVisible = true;
  Timer? _hideControlsTimer;

  Event get event => widget.event;

  bool get _inline => widget.playInline && PlatformInfos.supportsVideoPlayer;

  @override
  void dispose() {
    _hideControlsTimer?.cancel();
    _controller?.removeListener(_onControllerChanged);
    _controller?.dispose();
    super.dispose();
  }

  double? get _aspectRatio =>
      _measuredAspectRatios[event.eventId] ?? sentVideoAspectRatio(event);

  Future<void> _loadAndPlay() async {
    if (_loading) return;
    setState(() => _loading = true);
    try {
      final load = widget.loadController ?? viewer.videoControllerForEvent;
      final controller = await load(event, (progress) {
        if (mounted) setState(() => _downloadProgress = progress);
      });
      if (!mounted) {
        controller.dispose();
        return;
      }
      await controller.setVolume(_muted ? 0 : 1);
      final value = controller.value;
      if (value.size.width > 0 && value.size.height > 0) {
        final quarterTurns = value.rotationCorrection ~/ 90;
        _measuredAspectRatios[event.eventId] = quarterTurns.isOdd
            ? value.size.height / value.size.width
            : value.size.width / value.size.height;
      }
      controller.addListener(_onControllerChanged);
      setState(() {
        _controller = controller;
        _loading = false;
        _downloadProgress = null;
      });
      await controller.play();
      _scheduleHideControls();
    } on IOException catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } catch (e, s) {
      if (!mounted) return;
      setState(() => _loading = false);
      ErrorReporter(context, 'Unable to play video').onErrorCallback(e, s);
    }
  }

  bool _wasPlaying = false;

  void _onControllerChanged() {
    final playing = _controller?.value.isPlaying ?? false;
    if (playing == _wasPlaying) return;
    _wasPlaying = playing;
    if (!playing) {
      // Paused or finished: bring the controls back for the next tap.
      _hideControlsTimer?.cancel();
      if (mounted) setState(() => _controlsVisible = true);
    }
  }

  void _scheduleHideControls() {
    _hideControlsTimer?.cancel();
    _hideControlsTimer = Timer(const Duration(seconds: 2), () {
      if (mounted && (_controller?.value.isPlaying ?? false)) {
        setState(() => _controlsVisible = false);
      }
    });
  }

  bool get _finished {
    final value = _controller?.value;
    if (value == null || value.isPlaying) return false;
    return value.isCompleted ||
        (value.duration > Duration.zero && value.position >= value.duration);
  }

  Future<void> _togglePlay() async {
    final controller = _controller;
    if (controller == null) return _loadAndPlay();
    if (controller.value.isPlaying) {
      await controller.pause();
      setState(() => _controlsVisible = true);
      return;
    }
    if (_finished) await controller.seekTo(Duration.zero);
    await controller.play();
    setState(() => _controlsVisible = true);
    _scheduleHideControls();
  }

  Future<void> _toggleMute() async {
    setState(() => _muted = !_muted);
    await _controller?.setVolume(_muted ? 0 : 1);
    if (_controller?.value.isPlaying ?? false) _scheduleHideControls();
  }

  Future<void> _openFullScreen() async {
    if (!PlatformInfos.supportsVideoPlayer) {
      event.saveFile(context);
      return;
    }
    final controller = _controller;
    final position = controller?.value.position;
    if (controller != null && controller.value.isPlaying) {
      await controller.pause();
    }
    if (!mounted) return;
    await showImageViewer(
      context,
      event,
      timeline: widget.timeline,
      videoStartPosition: _finished ? null : position,
    );
  }

  String _formatDuration(Duration duration) =>
      '${duration.inMinutes.toString().padLeft(2, '0')}:'
      '${(duration.inSeconds % 60).toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final textColor = widget.textColor;
    final linkColor = widget.linkColor;
    final fileDescription = event.fileDescription;
    final size = videoBubbleSize(_aspectRatio);
    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);

    return Column(
      mainAxisSize: .min,
      spacing: 8,
      children: [
        Material(
          color: Colors.black,
          borderRadius: borderRadius,
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: _openFullScreen,
            child: SizedBox.fromSize(
              size: size,
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Hero(
                    tag: event.eventId,
                    child: _VideoPoster(event: event, size: size),
                  ),
                  if (_controller case final controller?)
                    _VideoFrame(controller: controller),
                  _buildControls(context),
                ],
              ),
            ),
          ),
        ),
        if (fileDescription != null && textColor != null && linkColor != null)
          SizedBox(
            width: size.width,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Linkify(
                text: fileDescription,
                textScaleFactor: MediaQuery.textScalerOf(context).scale(1),
                style: TextStyle(
                  color: textColor,
                  fontSize: AppConfig.messageFontSize,
                ),
                options: const LinkifyOptions(humanize: false),
                linkStyle: TextStyle(
                  color: linkColor,
                  fontSize: AppConfig.messageFontSize,
                  decoration: TextDecoration.underline,
                  decorationColor: linkColor,
                ),
                onOpen: (url) => UrlLauncher(context, url.url).launchUrl(),
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildControls(BuildContext context) {
    final l10n = L10n.of(context);
    final controller = _controller;
    final durationMs = event.infoMap.tryGet<int>('duration');
    final sentDuration = durationMs == null
        ? null
        : Duration(milliseconds: durationMs);

    if (!_inline) {
      return Stack(
        children: [
          Center(
            child: _RoundButton(
              icon: PlatformInfos.supportsVideoPlayer
                  ? Icons.play_arrow_rounded
                  : Icons.file_download_outlined,
              tooltip: PlatformInfos.supportsVideoPlayer
                  ? l10n.playVideo
                  : l10n.downloadFile,
              onPressed: _openFullScreen,
            ),
          ),
          if (sentDuration != null)
            _DurationLabel(text: _formatDuration(sentDuration)),
        ],
      );
    }

    if (controller == null) return _inlineControls(context, null, sentDuration);
    return ValueListenableBuilder<VideoPlayerValue>(
      valueListenable: controller,
      builder: (context, value, _) =>
          _inlineControls(context, value, sentDuration),
    );
  }

  Widget _inlineControls(
    BuildContext context,
    VideoPlayerValue? value,
    Duration? sentDuration,
  ) {
    final l10n = L10n.of(context);
    final playing = value?.isPlaying ?? false;
    final duration = value != null && value.duration > Duration.zero
        ? value.duration
        : sentDuration;
    final position = value?.position ?? Duration.zero;
    final showControls = _controlsVisible || !playing;
    final IconData icon;
    final String tooltip;
    if (playing) {
      icon = Icons.pause_rounded;
      tooltip = l10n.pauseVideo;
    } else if (_finished) {
      icon = Icons.replay_rounded;
      tooltip = l10n.replayVideo;
    } else {
      icon = Icons.play_arrow_rounded;
      tooltip = l10n.playVideo;
    }
    return Stack(
      children: [
        Center(
          child: AnimatedOpacity(
            opacity: showControls ? 1 : 0,
            duration: const Duration(milliseconds: 200),
            child: _loading
                ? _LoadingButton(progress: _downloadProgress)
                : _RoundButton(
                    icon: icon,
                    tooltip: tooltip,
                    onPressed: _togglePlay,
                  ),
          ),
        ),
        Positioned(
          top: 6,
          right: 6,
          child: _RoundButton(
            icon: _muted ? Icons.volume_off_rounded : Icons.volume_up_rounded,
            tooltip: _muted ? l10n.unmute : l10n.mute,
            onPressed: _toggleMute,
            small: true,
          ),
        ),
        if (duration != null)
          _DurationLabel(
            text: _formatDuration(
              value != null && (playing || position > Duration.zero)
                  ? duration - position
                  : duration,
            ),
          ),
        if (value != null && duration != null && duration > Duration.zero)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: LinearProgressIndicator(
              value: (position.inMilliseconds / duration.inMilliseconds).clamp(
                0.0,
                1.0,
              ),
              minHeight: 3,
              color: Colors.white,
              backgroundColor: Colors.white24,
            ),
          ),
      ],
    );
  }
}

/// The still shown until the video plays: the sent thumbnail, a frame taken
/// from the file where the platform can, or the blur hash.
class _VideoPoster extends StatelessWidget {
  final Event event;
  final Size size;

  const _VideoPoster({required this.event, required this.size});

  @override
  Widget build(BuildContext context) {
    final blurHash =
        event.infoMap.tryGet<String>('xyz.amorgan.blurhash') ??
        _EventVideoPlayerState.fallbackBlurHash;
    final placeholder = BlurHash(
      blurhash: blurHash,
      width: size.width,
      height: size.height,
      fit: BoxFit.cover,
    );
    if (!AppSettings.showThumbnailsInTimeline.value) return placeholder;
    if (event.hasThumbnail) {
      return MxcImage(
        event: event,
        cacheKey: event.transactionId ?? event.eventId,
        cacheName: event.room.id,
        isThumbnail: true,
        width: size.width,
        height: size.height,
        fit: BoxFit.cover,
        placeholder: (_) => placeholder,
      );
    }
    if (!VideoPoster.isSupported) return placeholder;
    return FutureBuilder(
      future: VideoPoster.forEvent(event),
      builder: (context, snapshot) {
        final poster = snapshot.data;
        if (poster == null) return placeholder;
        return Image.memory(
          poster,
          width: size.width,
          height: size.height,
          fit: BoxFit.cover,
          // Posters are full-size frames; decode them at the size they are
          // shown.
          cacheWidth: (size.width * MediaQuery.devicePixelRatioOf(context))
              .round(),
        );
      },
    );
  }
}

/// The playing video, filling the bubble edge to edge. The bubble already
/// has the video's shape, so cropping only trims a clamped extreme shape.
class _VideoFrame extends StatelessWidget {
  final VideoPlayerController controller;

  const _VideoFrame({required this.controller});

  @override
  Widget build(BuildContext context) {
    final value = controller.value;
    final quarterTurns = value.rotationCorrection ~/ 90;
    final frame = quarterTurns.isOdd ? value.size.flipped : value.size;
    if (frame.isEmpty) return const SizedBox.shrink();
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox.fromSize(size: frame, child: VideoPlayer(controller)),
    );
  }
}

class _RoundButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool small;

  const _RoundButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.small = false,
  });

  @override
  Widget build(BuildContext context) => IconButton(
    onPressed: onPressed,
    tooltip: tooltip,
    iconSize: small ? 18 : 32,
    padding: EdgeInsets.all(small ? 6 : 10),
    constraints: const BoxConstraints(),
    style: IconButton.styleFrom(
      backgroundColor: Colors.black.withAlpha(110),
      foregroundColor: Colors.white,
    ),
    icon: Icon(icon),
  );
}

class _LoadingButton extends StatelessWidget {
  final double? progress;

  const _LoadingButton({required this.progress});

  @override
  Widget build(BuildContext context) => Container(
    width: 52,
    height: 52,
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: Colors.black.withAlpha(110),
      shape: BoxShape.circle,
    ),
    child: CircularProgressIndicator(
      value: progress,
      strokeWidth: 3,
      color: Colors.white,
    ),
  );
}

class _DurationLabel extends StatelessWidget {
  final String text;

  const _DurationLabel({required this.text});

  @override
  Widget build(BuildContext context) => Positioned(
    left: 8,
    bottom: 8,
    child: IgnorePointer(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        decoration: BoxDecoration(
          color: Colors.black.withAlpha(110),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(
          text,
          style: const TextStyle(color: Colors.white, fontSize: 12),
        ),
      ),
    ),
  );
}
