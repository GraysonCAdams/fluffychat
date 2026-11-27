// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The platform interface comes in with video_player, which this fakes.
// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/video_player.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../utils/message_search/search_test_client.dart';

/// Plays nothing, reporting a ready video of [size] and recording the calls
/// the bubble makes.
class _FakeVideoPlayerPlatform extends VideoPlayerPlatform {
  Size size = const Size(1920, 1080);
  final calls = <String>[];
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
        size: size,
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
  Future<void> play(int playerId) async => calls.add('play');

  @override
  Future<void> pause(int playerId) async => calls.add('pause');

  @override
  Future<void> setVolume(int playerId, double volume) async =>
      calls.add('volume $volume');

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
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late Room room;
  late _FakeVideoPlayerPlatform platform;

  setUpAll(() async {
    // Blur hashes stand in for posters, which would need a real file.
    SharedPreferences.setMockInitialValues({
      AppSettings.showThumbnailsInTimeline.key: false,
    });
    await AppSettings.init(loadWebConfigFile: false);
    client = await createSearchTestClient();
    room = client.rooms.firstWhere((room) => !room.isSpace);
  });

  setUp(() {
    platform = _FakeVideoPlayerPlatform();
    VideoPlayerPlatform.instance = platform;
  });

  /// A video message as a phone sends a portrait clip: raw landscape frame
  /// sizes in `info`, the upright shape in the thumbnail's info.
  Event videoEvent({
    required int w,
    required int h,
    Map<String, Object?>? thumbnailInfo,
    String? thumbnailUrl,
  }) => Event(
    content: {
      'msgtype': MessageTypes.Video,
      'body': 'clip.mp4',
      'url': 'mxc://example.org/clip',
      'info': {
        'w': w,
        'h': h,
        'duration': 5000,
        'mimetype': 'video/mp4',
        'thumbnail_info': ?thumbnailInfo,
        'thumbnail_url': ?thumbnailUrl,
      },
    },
    type: EventTypes.Message,
    eventId: '\$video${w}x$h',
    senderId: client.userID!,
    originServerTs: DateTime(2026, 11, 27),
    room: room,
  );

  var loads = 0;
  Future<VideoPlayerController> fakeLoad(
    Event event,
    void Function(double?) onProgress,
  ) async {
    loads++;
    final controller = VideoPlayerController.networkUrl(
      Uri.parse('https://example.org/clip.mp4'),
    );
    await controller.initialize();
    return controller;
  }

  Future<void> pumpBubble(
    WidgetTester tester,
    Event event, {
    Future<double?> Function(Event)? measureThumbnail,
  }) async {
    loads = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: EventVideoPlayer(
              event,
              playInline: true,
              loadController: fakeLoad,
              measureThumbnail: measureThumbnail,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  // The bubble's own InkWell; its buttons hold more inside it.
  Finder bubble() => find
      .descendant(
        of: find.byType(EventVideoPlayer),
        matching: find.byType(InkWell),
      )
      .first;

  Size bubbleSize(WidgetTester tester) => tester.getSize(bubble());

  group('videoBubbleSize', () {
    test('a portrait video gets a portrait bubble', () {
      expect(videoBubbleSize(9 / 16), const Size(180, 320));
    });

    test('a landscape video gets a landscape bubble', () {
      expect(videoBubbleSize(16 / 9), const Size(280, 157.5));
    });

    test('extreme shapes are clamped', () {
      expect(videoBubbleSize(1 / 10).width, closeTo(320 * 9 / 21, 0.01));
      expect(videoBubbleSize(10).height, closeTo(280 * 9 / 21, 0.01));
    });
  });

  testWidgets('a portrait clip sent as rotated landscape frames is portrait', (
    tester,
  ) async {
    await pumpBubble(
      tester,
      videoEvent(w: 3840, h: 2160, thumbnailInfo: {'w': 1080, 'h': 1920}),
    );
    expect(bubbleSize(tester), const Size(180, 320));
  });

  testWidgets('a portrait clip takes the shape of its thumbnail image when '
      'the thumbnail info has no size', (tester) async {
    // As Seam sent it: the raw landscape frame size, and a portrait
    // thumbnail whose info carries no size.
    await AppSettings.showThumbnailsInTimeline.setItem(true);
    addTearDown(() => AppSettings.showThumbnailsInTimeline.setItem(false));
    final measured = <String>[];
    await pumpBubble(
      tester,
      videoEvent(
        w: 3840,
        h: 2160,
        thumbnailInfo: {'mimetype': 'image/jpeg', 'size': 210559},
        thumbnailUrl: 'mxc://example.org/thumb',
      ),
      measureThumbnail: (event) async {
        measured.add(event.eventId);
        return 2160 / 3840;
      },
    );
    expect(measured, hasLength(1));
    expect(bubbleSize(tester), const Size(180, 320));
    expect(loads, 0);
  });

  testWidgets('a thumbnail with a size in its info is not measured', (
    tester,
  ) async {
    await AppSettings.showThumbnailsInTimeline.setItem(true);
    addTearDown(() => AppSettings.showThumbnailsInTimeline.setItem(false));
    var measured = 0;
    await pumpBubble(
      tester,
      videoEvent(
        w: 1920,
        h: 1080,
        thumbnailInfo: {'w': 640, 'h': 360},
        thumbnailUrl: 'mxc://example.org/thumb2',
      ),
      measureThumbnail: (event) async {
        measured++;
        return 1;
      },
    );
    expect(measured, 0);
    expect(bubbleSize(tester), const Size(280, 157.5));
  });

  testWidgets('a landscape clip is landscape', (tester) async {
    await pumpBubble(tester, videoEvent(w: 1920, h: 1080));
    expect(bubbleSize(tester), const Size(280, 157.5));
  });

  testWidgets('the centre button plays and pauses the video in place', (
    tester,
  ) async {
    await pumpBubble(tester, videoEvent(w: 1920, h: 1080));

    await tester.tap(find.byTooltip('Play video'));
    await tester.pumpAndSettle();
    expect(loads, 1);
    expect(platform.calls, contains('play'));
    expect(find.byType(ImageViewer), findsNothing);

    // Playing, the button reads as pause, even once it has faded out.
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byTooltip('Pause video'), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(platform.calls.last, 'pause');
    expect(find.byTooltip('Play video'), findsOneWidget);
    expect(find.byType(ImageViewer), findsNothing);
  });

  testWidgets('the corner button mutes and unmutes', (tester) async {
    await pumpBubble(tester, videoEvent(w: 1920, h: 1080));
    await tester.tap(find.byTooltip('Play video'));
    await tester.pumpAndSettle();
    expect(platform.calls, contains('volume 1.0'));

    await tester.tap(find.byTooltip('Mute'));
    await tester.pump();
    expect(platform.calls.last, 'volume 0.0');
    expect(find.byTooltip('Unmute'), findsOneWidget);

    await tester.tap(find.byTooltip('Unmute'));
    await tester.pump();
    expect(platform.calls.last, 'volume 1.0');
    expect(find.byType(ImageViewer), findsNothing);
  });

  testWidgets('a tap away from the buttons opens the full screen viewer', (
    tester,
  ) async {
    await pumpBubble(tester, videoEvent(w: 1920, h: 1080));
    final box = tester.getRect(bubble());
    await tester.tapAt(box.bottomRight - const Offset(24, 24));
    // The viewer is a page of its own, built on the frame after the push.
    await tester.pump();
    await tester.pump();
    expect(find.byType(ImageViewer), findsOneWidget);
    expect(loads, 0);
    // Let the viewer's download request to the fake server and the
    // database finish in real time.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(milliseconds: 10));
  });
}
