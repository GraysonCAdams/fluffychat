// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// The platform interface comes in with video_player, which this fakes.
// ignore_for_file: depend_on_referenced_packages, implementation_imports

// Renders the built desktop media viewer to PNG: stills at 1920x1080 and
// 1280x800, and its interactions frame by frame at 30 fps, into the
// directory given as OUT:
//
//   flutter test test/mockups/desktop_viewer_after_test.dart \
//     --dart-define=OUT=<dir>
//   ffmpeg -framerate 30 -i <dir>/clip/%04d.png -c:v libx264 \
//     -pix_fmt yuv420p clip.mp4
//
// The photos are the CC0 ones in test/fixtures/pending_media; the video is
// one of them, drawn as the upright frame of a portrait phone clip.

import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/pages/image_viewer/video_player.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:video_player/video_player.dart';
import 'package:video_player_platform_interface/video_player_platform_interface.dart';

import '../pages/chat_list/chat_list_fakes.dart';

const _out = String.fromEnvironment('OUT', defaultValue: 'build/viewer_after');
const _fixtures = 'test/fixtures/pending_media';
const _frame = Duration(microseconds: 33333);

final _dog = File('$_fixtures/dog_on_deck.jpg').readAsBytesSync();
final _bulldog = File('$_fixtures/bulldog_life_jacket.jpg').readAsBytesSync();
final _onigiri = File('$_fixtures/onigiri.jpg').readAsBytesSync();

/// Signed in, so pictures load.
class _Client extends FakeChatListClient {
  _Client(super.clientName, {required super.database});

  @override
  bool isLogged() => true;
}

/// A message whose attachment is a fixture photo.
class _Photo extends Event {
  final Uint8List bytes;

  _Photo(
    this.bytes, {
    required super.content,
    required super.eventId,
    required super.originServerTs,
    required super.room,
  }) : super(type: EventTypes.Message, senderId: '@mia:x');

  @override
  Future<MatrixFile> downloadAndDecryptAttachment({
    bool getThumbnail = false,
    Future<Uint8List> Function(Uri)? downloadCallback,
    bool fromLocalStoreOnly = false,
    bool skipScanner = false,
    void Function(int)? onDownloadProgress,
  }) async =>
      MatrixImageFile(bytes: bytes, name: 'photo.jpg', mimeType: 'image/jpeg');
}

/// Plays a 16 s portrait clip: reports it as 1920x1080 with no rotation,
/// as Windows does, and draws the upright frame fitted into its box, as
/// media_kit does. Time moves 100 ms each time the player asks.
class _Platform extends VideoPlayerPlatform {
  final _events = <int, StreamController<VideoEvent>>{};
  final _position = <int, Duration>{};
  final _playing = <int, bool>{};
  var _next = 0;

  @override
  Future<void> init() async {}

  @override
  Future<int?> createWithOptions(VideoCreationOptions options) async {
    final id = _next++;
    final events = StreamController<VideoEvent>();
    _events[id] = events;
    _position[id] = const Duration(seconds: 3);
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
  Future<void> play(int playerId) async => _playing[playerId] = true;

  @override
  Future<void> pause(int playerId) async => _playing[playerId] = false;

  @override
  Future<void> setVolume(int playerId, double volume) async {}

  @override
  Future<void> setPlaybackSpeed(int playerId, double speed) async {}

  @override
  Future<void> seekTo(int playerId, Duration position) async =>
      _position[playerId] = position;

  @override
  Future<Duration> getPosition(int playerId) async {
    final now = _position[playerId]!;
    if (_playing[playerId] ?? false) {
      _position[playerId] = Duration(
        milliseconds: (now.inMilliseconds + 100) % 16000,
      );
    }
    return now;
  }

  @override
  Widget buildViewWithOptions(VideoViewOptions options) => FittedBox(
    child: SizedBox(
      width: 1080,
      height: 1920,
      child: Image.memory(_dog, fit: BoxFit.cover),
    ),
  );

  @override
  Future<void> setMixWithOthers(bool mixWithOthers) async {}
}

void main() {
  late _Client client;
  late FakeChatListRoom room;
  final boundary = GlobalKey();

  setUpAll(() async {
    final loader = FontLoader('GoogleSansFlex');
    for (final weight in ['Regular', 'Medium']) {
      loader.addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'assets/fonts/google_sans_flex/GoogleSansFlex-$weight.ttf',
            ).readAsBytesSync(),
          ),
        ),
      );
    }
    await loader.load();
    final icons = File(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
      '/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await iconLoader.load();
    }
  });

  setUp(() async {
    client = await setUpFakeChatList<_Client>(
      'desktop viewer after',
      create: (name, database) => _Client(name, database: database),
    );
    room = addFakeChat(client, '!mia:x', 'Mia Chen', partner: '@mia:x');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMaximized' ? false : null,
        );
    VideoPlayerPlatform.instance = _Platform();
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
    tearDownFakeChatList(client);
  });

  Event photo(int i, Uint8List bytes, int w, int h) => _Photo(
    bytes,
    content: {
      'msgtype': MessageTypes.Image,
      'body': 'IMG_$i.jpg',
      'url': 'mxc://x/m$i',
      'info': {'w': w, 'h': h, 'mimetype': 'image/jpeg'},
    },
    eventId: '\$m$i',
    originServerTs: DateTime(2026, 11, 27, 9, 40 + i),
    room: room,
  );

  Event video(int i) => _Photo(
    _dog,
    content: {
      'msgtype': MessageTypes.Video,
      'body': 'VID_$i.mp4',
      'url': 'mxc://x/m$i',
      'info': {
        'w': 1080,
        'h': 1920,
        'duration': 16000,
        'mimetype': 'video/mp4',
      },
    },
    eventId: '\$m$i',
    originServerTs: DateTime(2026, 11, 27, 9, 40 + i),
    room: room,
  );

  /// Lets pictures decode and the player start, in real time.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 60)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> save(WidgetTester tester, String path) async {
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path)
        ..parent.createSync(recursive: true)
        ..writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  /// The viewer open on the item [start] of eight, in a window [size]
  /// large, with [caption] under it when given.
  Future<ValueNotifier<String>> open(
    WidgetTester tester,
    Size size,
    int start, {
    bool caption = false,
  }) async {
    // Keys arrive as Windows sends them.
    debugDefaultTargetPlatformOverride = TargetPlatform.windows;
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = caption
        ? Size(size.width, size.height + 40)
        : size;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final events = [
      photo(1, _bulldog, 1024, 682),
      photo(2, _onigiri, 1024, 768),
      video(3),
      photo(4, _bulldog, 1024, 682),
      photo(5, _onigiri, 1024, 768),
      video(6),
      photo(7, _bulldog, 1024, 682),
      photo(8, _onigiri, 1024, 768),
    ];
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(events: events.reversed.toList()),
    );
    final text = ValueNotifier('');
    await tester.pumpWidget(
      RepaintBoundary(
        key: boundary,
        child: Column(
          children: [
            SizedBox.fromSize(
              size: size,
              child: Provider<MatrixState>.value(
                value: FakeMatrix(client, prefs),
                child: MaterialApp(
                  debugShowCheckedModeBanner: false,
                  theme: ThemeData(fontFamily: 'GoogleSansFlex'),
                  localizationsDelegates: L10n.localizationsDelegates,
                  supportedLocales: L10n.supportedLocales,
                  home: Builder(
                    builder: (context) {
                      scheduleMicrotask(
                        () => showImageViewer(
                          context,
                          events[start],
                          timeline: timeline,
                        ),
                      );
                      return const ColoredBox(color: Color(0xFF111318));
                    },
                  ),
                ),
              ),
            ),
            if (caption)
              Directionality(
                textDirection: TextDirection.ltr,
                child: Container(
                  height: 40,
                  width: size.width,
                  color: const Color(0xFF202124),
                  alignment: Alignment.centerLeft,
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: ValueListenableBuilder(
                    valueListenable: text,
                    builder: (context, value, _) => Text(
                      value,
                      style: const TextStyle(
                        fontFamily: 'GoogleSansFlex',
                        fontSize: 16,
                        color: Colors.white,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
    await settle(tester);
    await settle(tester);
    return text;
  }

  Future<void> finish(WidgetTester tester) async {
    for (final player in tester.widgetList<VideoPlayer>(
      find.byType(VideoPlayer),
    )) {
      await player.controller.pause();
    }
    debugDefaultTargetPlatformOverride = null;
    await finishFakeChatList(tester, client);
  }

  for (final size in const [Size(1920, 1080), Size(1280, 800)]) {
    final name = '${size.width.toInt()}';
    testWidgets('stills at $size', (tester) async {
      await open(tester, size, 5);
      final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
      await mouse.addPointer(location: Offset(size.width / 2, size.height / 2));
      await mouse.moveTo(Offset(size.width - 40, size.height / 2));
      await tester.pump(const Duration(milliseconds: 400));
      await save(tester, '$_out/after_${name}_video.png');

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump(const Duration(milliseconds: 800));
      await settle(tester);
      await tester.pump(const Duration(milliseconds: 800));
      await mouse.moveTo(Offset(size.width / 2, size.height / 2));
      // A ticker counts from the frame it starts on, so the zoom needs
      // frames, not one long pump.
      for (var i = 0; i < 3; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.equal);
        for (var f = 0; f < 20; f++) {
          await tester.pump(_frame);
        }
      }
      await settle(tester);
      // Lets the picture's fade in from its placeholder finish.
      for (var f = 0; f < 20; f++) {
        await tester.pump(_frame);
      }
      await save(tester, '$_out/after_${name}_photo.png');

      await mouse.removePointer();
      await finish(tester);
    });
  }

  testWidgets('interactions, 30 fps', (tester) async {
    const size = Size(1280, 800);
    final caption = await open(tester, size, 4, caption: true);
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    var pointer = const Offset(640, 400);
    await mouse.addPointer(location: pointer);
    var n = 0;

    Future<void> hold(double seconds) async {
      for (var i = 0; i < (seconds * 30).round(); i++) {
        await tester.pump(_frame);
        await save(
          tester,
          '$_out/clip/${(++n).toString().padLeft(4, '0')}.png',
        );
      }
    }

    Future<void> glide(Offset to, double seconds) async {
      final from = pointer;
      pointer = to;
      final steps = (seconds * 30).round();
      for (var i = 1; i <= steps; i++) {
        await mouse.moveTo(Offset.lerp(from, to, i / steps)!);
        await tester.pump(_frame);
        await save(
          tester,
          '$_out/clip/${(++n).toString().padLeft(4, '0')}.png',
        );
      }
    }

    caption.value = 'A photo; the bar holds the actions and the window buttons';
    await hold(0.8);
    caption.value = 'The mouse goes to the next arrow';
    await glide(const Offset(1240, 400), 0.6);
    caption.value =
        'Click: a portrait video fills the height, controls in a pill';
    await tester.tapAt(const Offset(1240, 400), kind: PointerDeviceKind.mouse);
    await hold(0.5);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await hold(1.0);
    caption.value = 'F hides the thumbnails';
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await hold(0.8);
    caption.value = 'F shows them again, centred under the controls';
    await tester.sendKeyEvent(LogicalKeyboardKey.keyF);
    await hold(0.8);
    caption.value = 'The volume slider opens on hover';
    await glide(const Offset(876, 668), 0.5);
    await hold(0.6);
    caption.value =
        'The mouse rests on the video: after 2.5 s everything fades';
    await glide(const Offset(640, 300), 0.3);
    await hold(3.0);
    caption.value = 'The mouse moves: everything returns';
    await glide(const Offset(660, 320), 0.2);
    await hold(0.6);
    caption.value = 'Left arrow key: back to the photo';
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await hold(0.4);
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 300)),
    );
    await hold(0.4);
    for (var i = 0; i < 5; i++) {
      caption.value = 'Ctrl+scroll zooms';
      await tester.sendEventToBinding(
        const PointerScrollEvent(
          kind: PointerDeviceKind.mouse,
          position: Offset(640, 400),
          scrollDelta: Offset(0, -120),
        ),
      );
      await hold(0.35);
    }
    await hold(0.5);
    caption.value = '0 fits it to the window again';
    await tester.sendKeyEvent(LogicalKeyboardKey.digit0);
    await hold(1.0);
    caption.value = 'Esc closes the viewer';
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await hold(0.6);

    await mouse.removePointer();
    await finish(tester);
  });
}
