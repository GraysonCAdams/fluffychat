// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:chewie/chewie.dart';
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

/// A video in the image viewer, filling its height and looping.
class EventVideoPlayer extends StatefulWidget {
  final Event event;

  /// Where playback starts, for a video already partly watched in its chat
  /// message. Without it the video starts at the beginning.
  final Duration? startAt;

  const EventVideoPlayer(this.event, {this.startAt, super.key});

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
      final videoPlayerController = await EventVideoPlayer.load(
        widget.event,
        (progress) {
          if (mounted) setState(() => _downloadProgress = progress);
        },
      );
      if (!mounted) {
        videoPlayerController.dispose();
        return;
      }

      // Dispose the controllers if we already have them.
      _disposeControllers();
      _videoPlayerController = videoPlayerController;

      final startAt = widget.startAt;
      if (startAt != null) await videoPlayerController.seekTo(startAt);

      // Create a ChewieController on top.
      setState(() {
        _chewieController = videoChewieController(
          videoPlayerController,
          looping: true,
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

  @override
  Widget build(BuildContext context) {
    final hasThumbnail = widget.event.hasThumbnail;
    final blurHash =
        (widget.event.infoMap as Map<String, dynamic>).tryGet<String>(
          'xyz.amorgan.blurhash',
        ) ??
        fallbackBlurHash;
    final infoMap = widget.event.content.tryGetMap<String, Object?>('info');
    final videoWidth = infoMap?.tryGet<int>('w') ?? 400;
    final videoHeight = infoMap?.tryGet<int>('h') ?? 300;
    final height = MediaQuery.sizeOf(context).height - 52;
    final width = videoWidth * (height / videoHeight);

    final chewieController = _chewieController;
    return chewieController != null
        ? Center(
            child: SizedBox(
              width: width,
              height: height,
              child: Chewie(controller: chewieController),
            ),
          )
        : Stack(
            children: [
              Center(
                child: Hero(
                  tag: widget.event.eventId,
                  child: hasThumbnail
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
                      : BlurHash(
                          blurhash: blurHash,
                          width: width,
                          height: height,
                        ),
                ),
              ),
              Center(
                child: CircularProgressIndicator.adaptive(
                  value: _downloadProgress,
                ),
              ),
            ],
          );
  }
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
/// [looping]. The image viewer and a video staged in the composer use it.
ChewieController videoChewieController(
  VideoPlayerController controller, {
  required bool looping,
}) => ChewieController(
  videoPlayerController: controller,
  showControlsOnInitialize: false,
  autoPlay: true,
  autoInitialize: true,
  looping: looping,
  aspectRatio: controller.value.aspectRatio,
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
