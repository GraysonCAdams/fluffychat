// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

// Renders the chat while the Google Messages bridge is still fetching
// attachments, to PNG files under build/pending_media_states, to look at
// the pending tiles without a phone:
//
//   flutter test test/screenshots/pending_media_states_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/image_bubble.dart';
import 'package:fluffychat/pages/chat/events/pending_media_tile.dart';
import 'package:fluffychat/utils/pending_media.dart';
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
import '../utils/pending_media_fixtures.dart';

final _out = Directory('build/pending_media_states');
const _ghost = '@gmessages_15551234567:x';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;

  setUpAll(() async {
    _out.createSync(recursive: true);
    final loader = FontLoader('GoogleSansFlex');
    for (final weight in ['Regular', 'Medium']) {
      final file = File(
        'assets/fonts/google_sans_flex/GoogleSansFlex-$weight.ttf',
      );
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
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
    client = await setUpFakeChatList('pending media states');
    room = addFakeChat(client, '!sms:x', 'Parla', partner: _ghost);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() => tearDownFakeChatList(client));

  Event notice(String id, String body, Map<String, Object?> extra) => Event(
    content: {'msgtype': MessageTypes.Notice, 'body': body, ...extra},
    type: EventTypes.Message,
    eventId: id,
    senderId: _ghost,
    originServerTs: DateTime(2026, 1, 1, 0, 1),
    room: room,
  );

  Future<void> capture(WidgetTester tester, String name) async {
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byKey(const ValueKey('shot')),
    );
    await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File(
        '${_out.path}/$name.png',
      ).writeAsBytesSync(bytes!.buffer.asUint8List());
      image.dispose();
    });
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  Future<void> showChat(
    WidgetTester tester,
    Brightness brightness,
    List<Event> events,
  ) async {
    tester.view.physicalSize = const Size(412 * 2, 1400 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    room.setMessages(['Look at these'], partner: _ghost);
    room.timelineEvents = [...room.timelineEvents!, ...events];
    room.lastEvent = events.last;
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          builder: (_, _) => ChatPage(roomId: room.id),
        ),
      ],
    );
    await tester.pumpWidget(
      RepaintBoundary(
        key: const ValueKey('shot'),
        child: Provider<MatrixState>.value(
          value: _Matrix(client, prefs),
          child: MaterialApp.router(
            debugShowCheckedModeBanner: false,
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            routerConfig: router,
            builder: (context, child) => Theme(
              data: FluffyThemes.buildTheme(context, brightness),
              child: child!,
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  for (final brightness in Brightness.values) {
    testWidgets('pending media in a chat, ${brightness.name}', (tester) async {
      final portrait = previewJpeg();
      final videoPoster = previewJpeg(width: 34, height: 60);
      await showChat(tester, brightness, [
        notice(r'$p1', 'Waiting for attachment PXL_1.jpg', {
          PendingMedia.pendingKey: true,
          PendingMedia.rawDebugDataKey: rawDebugData([
            mediaContent(
              name: 'PXL_1.jpg',
              width: 3024,
              height: 4032,
              preview: portrait,
            ),
          ]),
        }),
        notice(r'$p2', 'Waiting for attachment PXL_2.jpg', {
          PendingMedia.pendingKey: true,
        }),
        notice(r'$p3', 'Waiting for attachment PXL_3.mp4', {
          PendingMedia.pendingKey: true,
          PendingMedia.rawDebugDataKey: rawDebugData([
            mediaContent(
              name: 'PXL_3.mp4',
              mimeType: 'video/mp4',
              width: 2160,
              height: 3840,
              preview: videoPoster,
            ),
          ]),
        }),
        notice(r'$p4', 'Failed to transfer attachment PXL_4.jpg', {}),
      ]);
      expect(find.byType(PendingMediaTile), findsNWidgets(4));
      await capture(tester, 'chat_${brightness.name}');
    });

    testWidgets('swap and glyph variants, ${brightness.name}', (tester) async {
      tester.view.physicalSize = const Size(412 * 2, 640 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      final preview = previewJpeg(width: 63, height: 47);
      late Uint8List photo;
      await tester.runAsync(() async {
        // The arrived photo: the preview's scene, drawn sharp and large.
        final recorder = ui.PictureRecorder();
        final canvas = Canvas(recorder);
        final codec = await ui.instantiateImageCodec(preview);
        final frame = await codec.getNextFrame();
        canvas.drawImageRect(
          frame.image,
          const Rect.fromLTWH(0, 0, 63, 47),
          const Rect.fromLTWH(0, 0, 1024, 768),
          Paint()..filterQuality = FilterQuality.none,
        );
        final image = await recorder.endRecording().toImage(1024, 768);
        final data = await image.toByteData(format: ui.ImageByteFormat.png);
        photo = data!.buffer.asUint8List();
      });
      final media = PendingMedia(
        state: PendingMediaState.pending,
        kind: PendingMediaKind.image,
        fileName: 'PXL_1.jpg',
        aspectRatio: 4 / 3,
        preview: preview,
      );
      final radius = BorderRadius.circular(20);
      Widget arrived() => ClipRRect(
        borderRadius: radius,
        child: Image.memory(
          photo,
          width: imageBubbleSize(4 / 3).width,
          height: imageBubbleSize(4 / 3).height,
          fit: BoxFit.cover,
        ),
      );
      Widget frame(Widget swap) => RepaintBoundary(
        key: const ValueKey('shot'),
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, child) => Theme(
            data: FluffyThemes.buildTheme(context, brightness),
            child: child!,
          ),
          home: Scaffold(
            body: Padding(
              padding: const EdgeInsets.all(16),
              child: Wrap(
                spacing: 16,
                runSpacing: 16,
                children: [
                  swap,
                  // The glyph left on the blurred preview, for comparison.
                  Stack(
                    alignment: Alignment.center,
                    children: [
                      PendingMediaTile(media: media, borderRadius: radius),
                      Icon(
                        Icons.image_outlined,
                        size: 32,
                        color: Colors.white.withAlpha(200),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpWidget(
        frame(
          PendingMediaSwitcher(
            pending: true,
            child: PendingMediaTile(media: media, borderRadius: radius),
          ),
        ),
      );
      await settle(tester);
      await tester.pumpWidget(
        frame(PendingMediaSwitcher(pending: false, child: arrived())),
      );
      await tester.pump();
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)),
      );
      await tester.pump(const Duration(milliseconds: 125));
      await capture(tester, 'swap_mid_${brightness.name}');
      await tester.pump(const Duration(milliseconds: 300));
      await capture(tester, 'swap_done_${brightness.name}');
    });
  }
}
