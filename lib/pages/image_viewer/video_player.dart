// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:fluffychat/pages/chat/events/video_player.dart'
    show sentVideoAspectRatio;
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/event_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/blur_hash.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../../../utils/error_reporter.dart';
import '../../widgets/mxc_image.dart';

/// A video in the image viewer, looping, at its upright shape (see
/// [uprightVideoAspectRatio]).
///
/// On a phone it fills the viewer's height under Chewie's controls. With
/// [desktop] it fits the space it gets, letterboxed, with no controls of its
/// own: the viewer draws those, and gets the player from [onController].
class EventVideoPlayer extends StatefulWidget {
  final Event event;

  /// Where playback starts, for a video already partly watched in its chat
  /// message. Without it the video starts at the beginning.
  final Duration? startAt;

  final bool desktop;

  /// Told the player once it is ready, and null when it goes.
  final void Function(VideoPlayerController? controller)? onController;

  const EventVideoPlayer(
    this.event, {
    this.startAt,
    this.desktop = false,
    this.onController,
    super.key,
  });

  /// Downloads [event]'s video and opens a player on it. Tests swap in a
  /// fake.
  @visibleForTesting
  static Future<VideoPlayerController> Function(
    Event event,
    void Function(double? progress) onProgress,
  )
  load = videoControllerForEvent;

  @override
  EventVideoPlayerState createState() => EventVideoPlayerState();
}

class EventVideoPlayerState extends State<EventVideoPlayer> {
  ChewieController? _chewieController;
  VideoPlayerController? _videoPlayerController;

  double? _downloadProgress;

  final _supportsVideoPlayer = PlatformInfos.supportsVideoPlayer;

  Future<void> _downloadAction() async {
    if (!_supportsVideoPlayer) {
      widget.event.saveFile(context);
      return;
    }

    try {
      final videoPlayerController = await EventVideoPlayer.load(widget.event, (
        progress,
      ) {
        if (mounted) setState(() => _downloadProgress = progress);
      });
      if (!mounted) {
        videoPlayerController.dispose();
        return;
      }

      // Dispose the controllers if we already have them.
      _disposeControllers();
      _videoPlayerController = videoPlayerController;

      final startAt = widget.startAt;
      if (startAt != null) await videoPlayerController.seekTo(startAt);
      if (!mounted) return;

      if (widget.desktop) {
        await videoPlayerController.setLooping(true);
        await videoPlayerController.play();
        if (!mounted) return;
        setState(() {});
        widget.onController?.call(videoPlayerController);
        return;
      }

      // Create a ChewieController on top.
      setState(() {
        _chewieController = videoChewieController(
          videoPlayerController,
          looping: true,
          aspectRatio: uprightVideoAspectRatio(
            widget.event,
            videoPlayerController.value,
          ),
        );
      });
    } on IOException catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
    } catch (e, s) {
      if (!mounted) return;
      ErrorReporter(context, 'Unable to play video').onErrorCallback(e, s);
    }
  }

  void _disposeControllers() {
    _chewieController?.dispose();
    _videoPlayerController?.dispose();
    _chewieController = null;
    _videoPlayerController = null;
  }

  @override
  void dispose() {
    if (_videoPlayerController != null) widget.onController?.call(null);
    _disposeControllers();
    super.dispose();
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _downloadAction();
    });
  }

  static const String fallbackBlurHash = 'L5H2EC=PM+yV0g-mq.wG9c010J}I';

  /// The video's first frame or its blur hash, under a spinner, until the
  /// player is ready.
  Widget _poster({required double width, required double height}) {
    final blurHash =
        (widget.event.infoMap as Map<String, dynamic>).tryGet<String>(
          'xyz.amorgan.blurhash',
        ) ??
        fallbackBlurHash;
    return Stack(
      children: [
        Center(
          child: Hero(
            tag: widget.event.eventId,
            child: widget.event.hasThumbnail
                ? MxcImage(
                    event: widget.event,
                    isThumbnail: true,
                    width: width,
                    height: height,
                    fit: BoxFit.cover,
                    placeholder: (context) => BlurHash(
                      blurhash: blurHash,
                      width: width,
                      height: height,
                      fit: BoxFit.cover,
                    ),
                  )
                : BlurHash(blurhash: blurHash, width: width, height: height),
          ),
        ),
        Center(
          child: CircularProgressIndicator.adaptive(value: _downloadProgress),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final aspectRatio =
        uprightVideoAspectRatio(widget.event, _videoPlayerController?.value) ??
        4 / 3;

    if (widget.desktop) {
      final controller = _videoPlayerController;
      return Center(
        child: AspectRatio(
          aspectRatio: aspectRatio,
          child: controller != null
              ? VideoPlayer(controller)
              : LayoutBuilder(
                  builder: (context, constraints) => _poster(
                    width: constraints.maxWidth,
                    height: constraints.maxHeight,
                  ),
                ),
        ),
      );
    }

    final height = MediaQuery.sizeOf(context).height - 52;
    final width = aspectRatio * height;

    final chewieController = _chewieController;
    return chewieController != null
        ? Center(
            child: SizedBox(
              width: width,
              height: height,
              child: Chewie(controller: chewieController),
            ),
          )
        : _poster(width: width, height: height);
  }
}

/// The shape [event]'s video shows at, width over height: as the event
/// states it (see [sentVideoAspectRatio]), else the player's frame size
/// turned by its rotation correction.
///
/// The event comes first because the player's size is not always upright.
/// A phone stores a portrait clip as landscape frames plus a rotation, and
/// on Windows video_player_media_kit reports mpv's raw frame size without
/// that rotation, while media_kit still draws the frame upright, fitted
/// into whatever box it is given.
double? uprightVideoAspectRatio(Event event, VideoPlayerValue? value) {
  final sent = sentVideoAspectRatio(event);
  if (sent != null) return sent;
  if (value == null || value.size.isEmpty) return null;
  final quarterTurns = value.rotationCorrection ~/ 90;
  final size = quarterTurns.isOdd ? value.size.flipped : value.size;
  return size.width / size.height;
}

/// Downloads [event]'s video and returns an initialized player for it,
/// reporting the download's progress from 0 to 1 to [onProgress] while the
/// size is known and null once it is done. The chat message and the image
/// viewer both play through it.
Future<VideoPlayerController> videoControllerForEvent(
  Event event,
  void Function(double? progress) onProgress,
) async {
  final fileSize = event.content
      .tryGetMap<String, Object?>('info')
      ?.tryGet<int>('size');
  final videoFile = await event.downloadAndDecryptAttachment(
    onDownloadProgress: fileSize == null
        ? null
        : (progress) {
            final fraction = progress / fileSize;
            onProgress(fraction < 1 ? fraction : null);
          },
  );

  final VideoPlayerController controller;
  if (kIsWeb) {
    controller = VideoPlayerController.networkUrl(
      Uri.dataFromBytes(videoFile.bytes, mimeType: videoFile.mimeType),
    );
  } else {
    final tempDir = await getTemporaryDirectory();
    final fileNameStr = event.attachmentMxcUrl?.pathSegments.last ?? event.body;
    final fileName = Uri.encodeComponent(fileNameStr);
    final file = File('${tempDir.path}/${fileName}_${videoFile.name}');
    if (await file.exists() == false) {
      await file.writeAsBytes(videoFile.bytes);
    }
    controller = VideoPlayerController.file(file, viewType: eventVideoViewType);
  }
  await controller.initialize();
  return controller;
}

/// How a played video shows its frames.
///
/// On Android a Flutter texture loses most frames: ExoPlayer renders into the
/// texture's ImageReader, finds its frames late and drops them, so a 60 fps
/// clip plays at about 11 fps whatever its resolution. A platform view hands
/// the decoder a SurfaceView and plays every frame. Elsewhere the texture
/// keeps up.
VideoViewType get eventVideoViewType => PlatformInfos.isAndroid
    ? VideoViewType.platformView
    : VideoViewType.textureView;

/// The playback controls on top of [controller], an initialized video:
/// playing at once with its controls hidden until a tap, looping when
/// [looping], shaped [aspectRatio] (the player's own frame size without
/// one). The phone's image viewer and a video staged in the composer use
/// it.
ChewieController videoChewieController(
  VideoPlayerController controller, {
  required bool looping,
  double? aspectRatio,
}) => ChewieController(
  videoPlayerController: controller,
  showControlsOnInitialize: false,
  autoPlay: true,
  autoInitialize: true,
  looping: looping,
  aspectRatio: aspectRatio ?? controller.value.aspectRatio,
  // Chewie's options open as a bottom sheet, which suits phones but spans
  // the whole window on desktop. Desktop gets a speed menu on the control
  // bar instead, opening next to its button.
  showOptions: !PlatformInfos.isDesktop,
  additionalControls: PlatformInfos.isDesktop
      ? (context) => [_PlaybackSpeedButton(controller)]
      : null,
);

class _PlaybackSpeedButton extends StatelessWidget {
  final VideoPlayerController controller;

  const _PlaybackSpeedButton(this.controller);

  static const _speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  Widget build(BuildContext context) => PopupMenuButton<double>(
    icon: const Icon(Icons.speed, color: Colors.white),
    initialValue: controller.value.playbackSpeed,
    onSelected: controller.setPlaybackSpeed,
    itemBuilder: (context) => [
      for (final speed in _speeds)
        PopupMenuItem(
          value: speed,
          child: Text(
            '${speed == speed.roundToDouble() ? speed.toInt() : speed}x',
          ),
        ),
    ],
  );
}
