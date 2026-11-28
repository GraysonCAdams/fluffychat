// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages, implementation_imports

// Measures the desktop media viewer's layout bugs, printing what it finds:
//
//   flutter test test/mockups/desktop_viewer_repro_test.dart
//
// 1. A phone's portrait clip shrinks once it starts playing. Phones store
//    portrait video as landscape frames plus a rotation, and on Windows
//    video_player_media_kit reports mpv's raw `dw`/`dh`, ignoring `rotate`.
//    The fake platform here does the same: it reports 1920x1080 and draws the
//    upright frame the way media_kit's `Video` does, fitted into its box.
// 2. Chewie's control bar runs under the viewer's thumbnail strip.

import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer_view.dart';
import 'package:fluffychat/pages/image_viewer/video_player.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../pages/chat_list/chat_list_fakes.dart';

const _texture = Key('texture');

/// Reports a ready video of [reported] size, as the platform plugin would,
/// and draws an upright [frame] fitted into its box, as media_kit's `Video`
/// widget does (FittedBox, BoxFit.contain).
class _FakePlatform extends VideoPlayerPlatform {
  _FakePlatform({required this.reported, required this.frame});

  final Size reported;
  final Size frame;
  final _events = <int, StreamController<VideoEvent>>{};
  var _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    events.add(
      VideoEvent(
        eventType: VideoEventType.initialized,
        size: reported,
        duration: const Duration(seconds: 16),
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
  Widget buildViewWithOptions(VideoViewOptions options) => FittedBox(
    child: SizedBox.fromSize(
      size: frame,
      child: const ColoredBox(key: _texture, color: Colors.orange),
    ),
  );

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

void main() {
  const sizes = [Size(2000, 1167), Size(1436, 839), Size(1280, 800)];

  group('1. a portrait clip shrinks once it plays', () {
    for (final window in sizes) {
      for (final reported in const [Size(1920, 1080), Size(1080, 1920)]) {
        testWidgets('window $window, player reports $reported', (tester) async {
          tester.view.physicalSize = window;
          tester.view.devicePixelRatio = 1;
          addTearDown(tester.view.reset);
          VideoPlayerPlatform.instance = _FakePlatform(
            reported: reported,
            frame: const Size(1080, 1920),
          );
          final controller = VideoPlayerController.networkUrl(
            Uri.parse('https://x/clip.mp4'),
          );
          await controller.initialize();
          final chewie = videoChewieController(controller, looping: true);
          // The event's info: the portrait size the sender stated.
          const infoW = 1080, infoH = 1920;
          await tester.pumpWidget(
            MaterialApp(
              theme: ThemeData(platform: TargetPlatform.windows),
              home: Scaffold(
                backgroundColor: Colors.black,
                // image_viewer_view.dart:129-131, the video page.
                body: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 72),
                  child: Center(
                    child: Builder(
                      builder: (context) {
                        // video_player.dart:119-131, once initialized.
                        final height = MediaQuery.sizeOf(context).height - 52;
                        final width = infoW * (height / infoH);
                        return Center(
                          child: SizedBox(
                            key: const Key('box'),
                            width: width,
                            height: height,
                            child: Chewie(controller: chewie),
                          ),
                        );
                      },
                    ),
                  ),
                ),
              ),
            ),
          );
          await tester.pump(const Duration(milliseconds: 500));
          final box = tester.getRect(find.byKey(const Key('box')));
          final shown = tester.getRect(find.byKey(_texture));
          final bar = tester.getRect(
            find.byType(MaterialVideoProgressBar).first,
          );
          // ignore: avoid_print
          print(
            'REPRO1 window=${window.width.toInt()}x${window.height.toInt()} '
            'reported=${reported.width.toInt()}x${reported.height.toInt()} '
            'box=${_r(box)} video=${_r(shown)} '
            'fills=${(shown.height / box.height * 100).round()}% of box height '
            'scrubber=${_r(bar)}',
          );
          if (reported.width > reported.height) {
            // The bug: the upright frame drawn at a fraction of its box.
            expect(shown.height, lessThan(box.height * 0.5));
          } else {
            expect(shown.height, closeTo(box.height, 1));
          }
          // Stops playback's position timer before the tree goes.
          await controller.pause();
          await tester.pumpWidget(const SizedBox());
          await tester.pump(const Duration(seconds: 5));
        });
      }
    }
  });

  group('2. the control bar runs under the thumbnail strip', () {
    late FakeChatListClient client;
    late FakeChatListRoom room;

    setUp(() async {
      client = await setUpFakeChatList('desktop viewer repro');
      room = addFakeChat(client, '!mia:x', 'Mia', partner: '@mia:x');
    });

    tearDown(() => tearDownFakeChatList(client));

    Event media(int i, String type, int w, int h) => Event(
      content: {
        'msgtype': type,
        'body': 'm$i',
        'url': 'mxc://x/m$i',
        'info': {'w': w, 'h': h, 'mimetype': 'image/jpeg'},
      },
      type: EventTypes.Message,
      eventId: '\$m$i',
      senderId: '@mia:x',
      originServerTs: DateTime(2026, 11, 27, 9, i),
      room: room,
    );

    for (final window in sizes) {
      testWidgets('window $window', (tester) async {
        tester.view.physicalSize = window;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final prefs = await SharedPreferences.getInstance();
        final events = [
          media(3, MessageTypes.Image, 4000, 3000),
          media(2, MessageTypes.Video, 1080, 1920),
          media(1, MessageTypes.Image, 4000, 3000),
        ];
        final timeline = Timeline(
          room: room,
          chunk: TimelineChunk(events: events),
        );
        await tester.pumpWidget(
          Provider<MatrixState>.value(
            value: FakeMatrix(client, prefs),
            child: MaterialApp(
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              home: Builder(
                builder: (context) => Scaffold(
                  body: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      PageRouteBuilder<void>(
                        opaque: false,
                        pageBuilder: (_, _, _) => ImageViewer(
                          events[1],
                          timeline: timeline,
                          outerContext: context,
                          onReply: (_) {},
                          onShowInChat: (_) {},
                        ),
                      ),
                    ),
                    child: const Text('open'),
                  ),
                ),
              ),
            ),
          ),
        );
        Future<void> settle() async {
          for (var i = 0; i < 4; i++) {
            await tester.runAsync(
              () => Future<void>.delayed(const Duration(milliseconds: 30)),
            );
            await tester.pump(const Duration(milliseconds: 150));
          }
        }

        await settle();
        await tester.tap(find.text('open'));
        await settle();
        // Before it plays, the poster holds the box the player then takes.
        final poster = tester.getRect(
          find
              .descendant(
                of: find.byType(EventVideoPlayer),
                matching: find.byType(Hero),
              )
              .first,
        );
        final strip = tester.getRect(find.byType(MediaThumbnailStrip));
        final reply = tester.getRect(find.byTooltip('Reply'));
        final forward = tester.getRect(find.byTooltip('Forward'));
        // ignore: avoid_print
        print(
          'REPRO2 window=${window.width.toInt()}x${window.height.toInt()} '
          'player box=${_r(poster)} strip=${_r(strip)} '
          'strip overlaps player bottom by ${(poster.bottom - strip.top).round()} '
          'reply.x=${reply.center.dx.round()} '
          'forward.x=${forward.center.dx.round()} '
          'gap=${(forward.center.dx - reply.center.dx).round()}',
        );
        expect(strip.top, lessThan(poster.bottom));
        // Drains the failed download's error report.
        await tester.pump(const Duration(seconds: 1));
      });
    }
  });
}

String _r(Rect r) =>
    '(${r.left.round()},${r.top.round()} '
    '${r.width.round()}x${r.height.round()})';
