// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:chewie/chewie.dart';
import 'package:fluffychat/pages/image_viewer/video_player.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

/// Reports a 16:9 video that is ready to play, so Chewie builds its controls
/// without a real decoder.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  final _events = <int, StreamController<VideoEvent>>{};
  var _nextId = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _nextId++;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: const Size(1920, 1080),
        duration: const Duration(seconds: 30),
      ),
    );
    return id;
  }

  @override
  Stream<VideoEvent> videoEventsFor(int playerId) => _events[playerId]!.stream;

  @override
  Future<void> dispose(int playerId) async => _events.remove(playerId)?.close();

  @override
  Future<void> setLooping(int playerId, bool looping) async {}

  @override
  Future<void> play(int playerId) async {}

  @override
  Future<void> pause(int playerId) async {}

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async {}

  @override
  Future<Duration> getPosition(int playerId) async => Duration.zero;

  @override
  Widget buildViewWithOptions(VideoViewOptions options) =>
      const ColoredBox(color: Colors.black);

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

void main() {
  testWidgets('desktop controls of an inline video fit inside its box', (
    tester,
  ) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    VideoPlayerPlatform.instance = _FakeVideoPlayerPlatform();
    await tester.binding.setSurfaceSize(const Size(1600, 1000));

    final video = VideoPlayerController.file(File('video.mp4'));
    await video.initialize();
    final chewie = ChewieController(
      videoPlayerController: video,
      aspectRatio: video.value.aspectRatio,
    );
    const box = Key('box');
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            // The chat timeline scrolls under its app bar, so messages see
            // the app bar's height as top padding.
            child: MediaQuery(
              data: const MediaQueryData(
                size: Size(1600, 1000),
                padding: EdgeInsets.only(top: 80),
              ),
              child: SizedBox(
                key: box,
                width: 300,
                height: 300,
                child: InlineVideoFrame(child: Chewie(controller: chewie)),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump(const Duration(milliseconds: 500));

    final boxRect = tester.getRect(find.byKey(box));
    final expand = tester.getRect(find.byIcon(Icons.fullscreen));
    final progress = tester.getRect(find.byType(MaterialVideoProgressBar));

    expect(expand.height, greaterThan(0));
    expect(progress.height, greaterThan(0));
    expect(boxRect.contains(expand.bottomRight), isTrue);
    expect(boxRect.bottom, greaterThanOrEqualTo(progress.bottom));

    debugDefaultTargetPlatformOverride = null;
  });
}
