// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

// Renders the real chat with data detections, to PNG files under
// build/data_detectors, to compare with the approved design
// (test/mockups/data_detectors_v3_test.dart on mock/data-detectors-v2):
//
//   flutter test test/screenshots/data_detectors_test.dart
//
// <scene>_<brightness>.png   one per scene of the design's contact sheet
// frames_flow/               one PNG per 1/30 s of a message arriving, its
//                            menu opening and closing, its chip pressed,
//                            and a newer message taking the chip; join
//                            with ffmpeg
//
// Detection is Seam's own detector with Android's action titles added. App
// icons are read from build/data_detectors_icons/<title>.png when present
// (not in the repository), standing in for the icons Android supplies;
// without them the actions show Material icons.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/data_detectors/data_detections.dart';
import 'package:fluffychat/utils/data_detectors/data_detector_platform.dart';
import 'package:fluffychat/utils/data_detectors/detection_actions.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';
import '../utils/data_detectors/data_detector_fakes.dart';

final _out = Directory('build/data_detectors');
final _iconDir = Directory('build/data_detectors_icons');
const _seed = Color(0xFF1A5AD7);
const _address = '3456 Chelsea Park Lane Apt D, Peachtree Corners GA 30092';
const _phoneText = 'Works. Call me at (404) 555-0123 when you are close';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

/// One message of a scene: (sender, body), sender null for the user.
typedef _Line = (String? sender, String body);

class _Scene {
  const _Scene(
    this.name,
    this.lines, {
    this.reactions = const [],
    this.tap,
    this.android = true,
    this.width = 412,
  });
  final String name;
  final List<_Line> lines;

  /// Reaction keys on the last message.
  final List<String> reactions;

  /// The detected text to tap, opening its menu.
  final String? tap;
  final bool android;
  final double width;
}

const _scenes = [
  _Scene('incoming', [
    ('@drew:x', 'My new number is (404) 555-0188'),
    (null, 'Got it'),
    ('@drew:x', 'Come by whenever. $_address'),
  ]),
  _Scene('outgoing', [
    ('@drew:x', 'I can meet you out front'),
    (null, _phoneText),
  ]),
  _Scene(
    'reactions_wide',
    [
      (null, 'Where should I head?'),
      ('@drew:x', 'Come by whenever. $_address'),
    ],
    reactions: ['❤️', '👍'],
  ),
  _Scene(
    'reactions_narrow',
    [('@drew:x', 'What time works?'), (null, 'Saturday at 7pm')],
    reactions: ['👍', '🎉'],
  ),
  _Scene('two_detections', [
    (null, 'Where should I head?'),
    ('@drew:x', 'Come to $_address and ring (404) 555-0123 at the gate'),
  ]),
  _Scene('tap_span', [
    ('@drew:x', 'I can meet you out front'),
    (null, _phoneText),
  ], tap: '(404) 555-0123'),
  _Scene(
    'windows',
    [('@drew:x', 'I can meet you out front'), (null, _phoneText)],
    tap: '(404) 555-0123',
    android: false,
    width: 848,
  ),
];

void main() {
  late FakeChatListClient client;
  final icons = <String, Uint8List>{};
  var rooms = 0;

  setUpAll(() async {
    _out.createSync(recursive: true);
    final loader = FontLoader('GoogleSansFlex');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final file = File(
        'assets/fonts/google_sans_flex/GoogleSansFlex-$weight.ttf',
      );
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
    await loader.load();
    // The icon font ships with the Flutter SDK, beside the test engine.
    final iconFont = File(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
      '/material_fonts/MaterialIcons-Regular.otf',
    );
    if (iconFont.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(
          Future.value(ByteData.sublistView(iconFont.readAsBytesSync())),
        );
      await iconLoader.load();
    }
    // Reaction emoji need a colour emoji font; Windows ships one.
    final emoji = File(r'C:\Windows\Fonts\seguiemj.ttf');
    if (emoji.existsSync()) {
      final emojiLoader = FontLoader('SegoeEmoji')
        ..addFont(Future.value(ByteData.sublistView(emoji.readAsBytesSync())));
      await emojiLoader.load();
    }
    if (_iconDir.existsSync()) {
      for (final file in _iconDir.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (name.endsWith('.png')) {
          icons[name.substring(0, name.length - 4)] = file.readAsBytesSync();
        }
      }
    }
  });

  setUp(() async {
    client = await setUpFakeChatList('data detector screenshots');
    DetectionActions.launcher = FakeLauncher();
    DataDetections.instance.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() {
    DataDetectorPlatform.instance = null;
    DetectionActions.launcher = const DetectionLauncher();
    tearDownFakeChatList(client);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  var batch = 0;

  Future<void> receive(
    WidgetTester tester,
    Room room,
    List<_Line> lines, {
    List<String> reactions = const [],
  }) async {
    batch++;
    final base = DateTime(2026, 11, 27, 13).add(Duration(minutes: batch * 5));
    final ids = [for (var i = 0; i < lines.length; i++) '\$m$batch-$i'];
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 's$batch',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [
                    for (final (i, (sender, body)) in lines.indexed)
                      MatrixEvent(
                        type: EventTypes.Message,
                        content: {'msgtype': 'm.text', 'body': body},
                        senderId: sender ?? client.userID!,
                        eventId: ids[i],
                        originServerTs: base.add(Duration(minutes: i)),
                      ),
                    for (final (i, key) in reactions.indexed)
                      MatrixEvent(
                        type: EventTypes.Reaction,
                        content: {
                          'm.relates_to': {
                            'rel_type': RelationshipTypes.reaction,
                            'event_id': ids.last,
                            'key': key,
                          },
                        },
                        senderId: i == 0 ? '@drew:x' : client.userID!,
                        eventId: '\$r$batch-$i',
                        originServerTs: base.add(const Duration(minutes: 4)),
                      ),
                  ],
                ),
              ),
            },
          ),
        ),
      ),
    );
  }

  /// Opens a direct chat with Drew in [brightness] at [width] by 560.
  Future<Room> open(
    WidgetTester tester,
    Brightness brightness, {
    double width = 412,
    double height = 560,
  }) async {
    tester.view.physicalSize = Size(width, height) * 2;
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final room = addFakeChat(
      client,
      '!shot${rooms++}:x',
      'Drew Andersen',
      partner: '@drew:x',
    );
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('chat list')),
          routes: [
            GoRoute(
              path: 'chat',
              builder: (_, _) => ChatPage(roomId: room.id),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: Provider<MatrixState>.value(
          value: _Matrix(client, prefs),
          child: Builder(
            builder: (context) {
              final theme = FluffyThemes.buildTheme(context, brightness, _seed);
              return MaterialApp.router(
                debugShowCheckedModeBanner: false,
                theme: theme.copyWith(
                  textTheme: theme.textTheme.apply(
                    fontFamilyFallback: const ['SegoeEmoji'],
                  ),
                ),
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                routerConfig: router,
              );
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/chat');
    await settle(tester);
    return room;
  }

  Future<void> capture(WidgetTester tester, String path) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(path).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  /// The centre on screen of [piece] in the message text.
  Offset centreOf(WidgetTester tester, String piece) {
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
      find.byType(RichText),
    )) {
      final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
      final at = plain.indexOf(piece);
      if (at < 0) continue;
      final box = paragraph
          .getBoxesForSelection(
            TextSelection(baseOffset: at, extentOffset: at + piece.length),
          )
          .first;
      return paragraph.localToGlobal(box.toRect().center);
    }
    throw StateError('No paragraph shows $piece');
  }

  for (final brightness in Brightness.values) {
    for (final scene in _scenes) {
      testWidgets('${scene.name}, ${brightness.name}', (tester) async {
        debugDisableShadows = false;
        DataDetectorPlatform.instance = FakeDetector(
          android: scene.android,
          icons: icons,
        );
        final room = await open(tester, brightness, width: scene.width);
        await receive(tester, room, scene.lines, reactions: scene.reactions);
        await settle(tester);
        await tester.pumpAndSettle();
        final tap = scene.tap;
        if (tap != null) {
          await tester.tapAt(centreOf(tester, tap));
          await tester.pumpAndSettle();
          // The menu's app icons decode off the frame clock.
          await settle(tester);
        }
        await capture(
          tester,
          '${_out.path}/${scene.name}_${brightness.name}.png',
        );
        debugDisableShadows = true;
      });
    }
  }

  testWidgets('flow', (tester) async {
    debugDisableShadows = false;
    DataDetectorPlatform.instance = FakeDetector(android: true, icons: icons);
    final frames = Directory('${_out.path}/frames_flow');
    if (frames.existsSync()) frames.deleteSync(recursive: true);
    frames.createSync(recursive: true);
    final room = await open(tester, Brightness.dark, height: 660);
    await receive(tester, room, [
      ('@drew:x', 'Almost there?'),
      (null, 'Ten minutes out'),
    ]);
    await settle(tester);

    var index = 0;
    Future<void> record(double seconds) async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byKey(const ValueKey('shot')),
      );
      for (var i = 0; i < (seconds * 30).round(); i++) {
        await tester.pump(const Duration(microseconds: 33333));
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${frames.path}/f${(index++).toString().padLeft(4, '0')}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
    }

    /// Lets the timeline take in a sync, recording as it goes.
    Future<void> take(List<_Line> lines) async {
      await receive(tester, room, lines);
      for (var i = 0; i < 3; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await record(0.2);
      }
    }

    await record(0.6);
    // 1. The message arrives, underlined, with its chip.
    await take([('@drew:x', _phoneText)]);
    await record(1.2);
    expect(find.byType(ActionChip), findsOneWidget);

    // 2. A tap on the span opens the anchored menu.
    final gesture = await tester.startGesture(
      centreOf(tester, '(404) 555-0123'),
    );
    await record(0.1);
    await gesture.up();
    await record(2.0);

    // 3. A tap outside closes it.
    await tester.tapAt(const Offset(206, 120));
    await record(0.8);

    // 4. A tap on the chip: its pressed state.
    final chip = await tester.startGesture(
      tester.getCenter(find.byType(ActionChip)),
    );
    await record(0.4);
    await chip.up();
    await record(0.8);

    // 5. A reply, then a message with two detections: two chips, and the
    // older message's chip folds away.
    await take([(null, 'Leaving now')]);
    await take([
      ('@drew:x', 'Come to $_address and ring (404) 555-0199 at the gate'),
    ]);
    await record(2.4);
    expect(find.byType(ActionChip), findsNWidgets(2));
    debugDisableShadows = true;
  });
}
