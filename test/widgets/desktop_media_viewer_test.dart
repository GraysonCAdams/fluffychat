// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The platform interface comes in with video_player, which this fakes.
// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:async';

import 'package:chewie/chewie.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer_view.dart';
import 'package:fluffychat/pages/image_viewer/video_player.dart';
import 'package:fluffychat/utils/windows_shell_ffi.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../pages/chat_list/chat_list_fakes.dart';

const _texture = Key('texture');

/// Plays nothing. Reports every video as 1920x1080 with no rotation, as
/// video_player_media_kit does on Windows for a phone's portrait clip (mpv's
/// raw frame size, its rotation dropped), and draws the upright 1080x1920
/// frame fitted into its box, as media_kit's `Video` widget does.
class _WindowsLikePlatform extends VideoPlayerPlatform {
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
        size: const Size(1920, 1080),
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
  Widget buildViewWithOptions(VideoViewOptions options) => const FittedBox(
    child: SizedBox(
      width: 1080,
      height: 1920,
      child: ColoredBox(key: _texture, color: Colors.orange),
    ),
  );

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;

  setUp(() async {
    client = await setUpFakeChatList('desktop media viewer');
    room = addFakeChat(client, '!mia:x', 'Mia', partner: '@mia:x');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMaximized' ? false : null,
        );
    VideoPlayerPlatform.instance = _WindowsLikePlatform();
    EventVideoPlayer.load = (event, onProgress) async {
      final controller = VideoPlayerController.networkUrl(
        Uri.parse('https://x/${event.eventId}.mp4'),
      );
      await controller.initialize();
      return controller;
    };
  });

  tearDown(() {
    EventVideoPlayer.load = videoControllerForEvent;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    tearDownFakeChatList(client);
  });

  Event media(int i, String type) => Event(
    content: {
      'msgtype': type,
      'body': 'm$i',
      'url': 'mxc://x/m$i',
      'info': type == MessageTypes.Video
          ? {'w': 1080, 'h': 1920, 'mimetype': 'video/mp4'}
          : {'w': 4000, 'h': 3000, 'mimetype': 'image/jpeg'},
    },
    type: EventTypes.Message,
    eventId: '\$m$i',
    senderId: '@mia:x',
    originServerTs: DateTime(2026, 11, 27, 9, i),
    room: room,
  );

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  /// The app as Windows draws it in a window [size] large, with the chat
  /// list under the title bar, and the viewer open over it on the video
  /// (or, with [video] false, the photo) of a picture, a video and a
  /// picture.
  Future<void> open(WidgetTester tester, Size size, {bool video = true}) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => const ChatList(activeChat: null),
        ),
      ],
    );
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp.router(
          theme: ThemeData(
            appBarTheme: const AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle.dark,
            ),
          ),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
          builder: (context, child) => WindowsChrome(
            showChatList: () => router.go('/rooms'),
            child: child!,
          ),
        ),
      ),
    );
    await settle(tester);
    final events = [
      media(3, MessageTypes.Image),
      media(2, MessageTypes.Video),
      media(1, MessageTypes.Image),
    ];
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(events: events),
    );
    unawaited(
      showImageViewer(
        tester.element(find.byType(ChatList)),
        video ? events[1] : events[0],
        timeline: timeline,
      ),
    );
    await settle(tester);
  }

  Future<void> finish(WidgetTester tester) async {
    for (final controller
        in tester
            .widgetList<VideoPlayer>(find.byType(VideoPlayer))
            .map((player) => player.controller)) {
      await controller.pause();
    }
    debugDefaultTargetPlatformOverride = null;
    await finishFakeChatList(tester, client);
  }

  /// Whether the deepest widget under [point] belongs to the viewer.
  bool hitsViewer(WidgetTester tester, Offset point) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, point, tester.view.viewId);
    final viewer = tester.renderObject(find.byType(ImageViewer));
    for (final entry in result.path) {
      final target = entry.target;
      if (target is! RenderObject) continue;
      RenderObject? node = target;
      while (node != null) {
        if (node == viewer) return true;
        node = node.parent;
      }
      return false;
    }
    return false;
  }

  Finder scrubber() {
    final ours = find.byKey(const ValueKey('viewer-scrubber'));
    return ours.evaluate().isNotEmpty
        ? ours
        : find.byType(MaterialVideoProgressBar);
  }

  Finder filmstrip() {
    final ours = find.byKey(const ValueKey('viewer-filmstrip'));
    return ours.evaluate().isNotEmpty ? ours : find.byType(MediaThumbnailStrip);
  }

  const sizes = [Size(2000, 1167), Size(1436, 839), Size(1280, 800)];

  group('a portrait phone clip fills the window height', () {
    for (final size in sizes) {
      testWidgets('$size', (tester) async {
        await open(tester, size);
        final shown = tester.getRect(find.byKey(_texture));
        expect(shown.height, greaterThanOrEqualTo(size.height * 0.95));
        expect(shown.center.dx, closeTo(size.width / 2, 1));
        await finish(tester);
      });
    }
  });

  group('the video controls sit above the filmstrip, the actions on top', () {
    for (final size in sizes) {
      testWidgets('$size', (tester) async {
        await open(tester, size);
        final bar = tester.getRect(scrubber().first);
        final strip = tester.getRect(filmstrip().first);
        expect(bar.overlaps(strip), isFalse, reason: '$bar over $strip');
        expect(bar.bottom, lessThanOrEqualTo(strip.top));
        final forward = tester.getRect(find.byTooltip('Forward'));
        expect(forward.center.dy, lessThan(48));
        await finish(tester);
      });
    }
  });

  group('the viewer covers the title bar and keeps the window buttons', () {
    for (final size in sizes) {
      testWidgets('$size', (tester) async {
        await open(tester, size);
        // The rail's band, the chat list's title and the middle of the bar.
        for (final x in [40.0, 120.0, size.width / 2]) {
          expect(hitsViewer(tester, Offset(x, 24)), isTrue, reason: 'x=$x');
        }
        expect(find.text('Chats').hitTestable(), findsNothing);
        expect(tester.getRect(find.byTooltip('Close')).top, lessThan(48));
        final glyphs = find.descendant(
          of: find.byType(ImageViewer),
          matching: find.byWidgetPredicate(
            (widget) =>
                widget is CustomPaint &&
                widget.painter.runtimeType.toString() == '_CaptionGlyphPainter',
          ),
        );
        expect(glyphs, findsNWidgets(3));
        // At the window's right edge, where Windows puts them.
        expect(tester.getRect(glyphs.last).center.dx, size.width - 23);
        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await settle(tester);
        expect(find.byType(ImageViewer), findsNothing);
        await finish(tester);
      });
    }
  });

  testWidgets('the keyboard and the wheel zoom a photo in steps', (
    tester,
  ) async {
    await open(tester, const Size(1280, 800), video: false);
    expect(find.text('Fit'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await settle(tester);
    expect(find.text('125%'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await settle(tester);
    expect(find.text('Fit'), findsOneWidget);
    // One notch of the wheel is one step, not a leap.
    tester.binding.handlePointerEvent(
      const PointerScrollEvent(
        kind: PointerDeviceKind.mouse,
        position: Offset(640, 400),
        scrollDelta: Offset(0, -120),
      ),
    );
    await settle(tester);
    final label = find.textContaining('%').evaluate().single.widget as Text;
    final percent = int.parse(label.data!.replaceAll('%', ''));
    expect(percent, inInclusiveRange(110, 130));
    await finish(tester);
  });

  testWidgets('the keys zoom a photo paged to from a video', (tester) async {
    await open(tester, const Size(1280, 800));
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);
    expect(find.text('Fit'), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.equal);
    await settle(tester);
    expect(find.text('125%'), findsOneWidget);
    await finish(tester);
  });

  group('the bottom bar is centred in the window', () {
    for (final size in const [Size(1920, 1080), Size(1280, 800)]) {
      for (final video in [true, false]) {
        testWidgets('$size, ${video ? 'video' : 'photo'}', (tester) async {
          await open(tester, size, video: video);
          final centre = size.width / 2;
          if (video) {
            final pill = tester.getRect(
              find.byKey(const ValueKey('viewer-video-controls')),
            );
            expect(pill.center.dx, closeTo(centre, 1));
          }
          final thumbs = tester.getRect(
            find.byKey(const ValueKey('viewer-filmstrip-row')),
          );
          expect(thumbs.center.dx, closeTo(centre, 1));
          await finish(tester);
        });
      }
    }
  });
}
