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

class EventVideoPlayer extends StatefulWidget {
  final Event event;

  /// The size to play at inside a chat message. Without it the video fills
  /// the height of the image viewer and loops.
  final Size? inlineSize;

  const EventVideoPlayer(this.event, {this.inlineSize, super.key});

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
      final fileSize = widget.event.content
          .tryGetMap<String, Object?>('info')
          ?.tryGet<int>('size');
      final videoFile = await widget.event.downloadAndDecryptAttachment(
        onDownloadProgress: fileSize == null
            ? null
            : (progress) {
                final progressPercentage = progress / fileSize;
                setState(() {
                  _downloadProgress = progressPercentage < 1
                      ? progressPercentage
                      : null;
                });
              },
      );

      // Dispose the controllers if we already have them.
      _disposeControllers();
      late VideoPlayerController videoPlayerController;

      // Create the VideoPlayerController from the contents of videoFile.
      if (kIsWeb) {
        videoPlayerController = VideoPlayerController.networkUrl(
          Uri.dataFromBytes(videoFile.bytes, mimeType: videoFile.mimeType),
        );
      } else {
        final tempDir = await getTemporaryDirectory();
        final fileNameStr =
            widget.event.attachmentMxcUrl?.pathSegments.last ??
            widget.event.body;
        final fileName = Uri.encodeComponent(fileNameStr);
        final file = File('${tempDir.path}/${fileName}_${videoFile.name}');
        if (await file.exists() == false) {
          await file.writeAsBytes(videoFile.bytes);
        }
        videoPlayerController = VideoPlayerController.file(file);
      }
      _videoPlayerController = videoPlayerController;

      await videoPlayerController.initialize();

      // Create a ChewieController on top.
      setState(() {
        _chewieController = ChewieController(
          videoPlayerController: videoPlayerController,
          showControlsOnInitialize: false,
          autoPlay: true,
          autoInitialize: true,
          looping: widget.inlineSize == null,
          aspectRatio: _videoPlayerController?.value.aspectRatio,
          // Chewie's options open as a bottom sheet, which suits phones but
          // spans the whole window on desktop. Desktop gets a speed menu on
          // the control bar instead, opening next to its button.
          showOptions: !PlatformInfos.isDesktop,
          additionalControls: PlatformInfos.isDesktop
              ? (context) => [_PlaybackSpeedButton(videoPlayerController)]
              : null,
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
    final inlineSize = widget.inlineSize;
    final height = inlineSize?.height ?? MediaQuery.sizeOf(context).height - 52;
    final width = inlineSize?.width ?? videoWidth * (height / videoHeight);

    final chewieController = _chewieController;
    return chewieController != null
        ? Center(
            child: SizedBox(
              width: width,
              height: height,
              child: widget.inlineSize == null
                  ? Chewie(controller: chewieController)
                  : InlineVideoFrame(
                      child: Chewie(controller: chewieController),
                    ),
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

/// Hosts a video player inside a chat message.
///
/// The chat timeline scrolls under its app bar, so a message sees the app
/// bar's height as top padding. Chewie's controls keep clear of that padding
/// with a SafeArea, which squeezes their bar to nothing in a box the size of
/// a message, so the padding is removed here.
class InlineVideoFrame extends StatelessWidget {
  final Widget child;

  const InlineVideoFrame({required this.child, super.key});

  @override
  Widget build(BuildContext context) => MediaQuery.removePadding(
    context: context,
    removeTop: true,
    removeBottom: true,
    removeLeft: true,
    removeRight: true,
    child: child,
  );
}

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
