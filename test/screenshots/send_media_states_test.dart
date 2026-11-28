// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

// Renders the chat while a photo and a video this device sends are on their
// way, to PNG files under build/send_media_states, to look at the sending
// states without a phone:
//
//   flutter test test/screenshots/send_media_states_test.dart
//
// Each message is a local echo as Room.sendFileEvent makes one, with its
// picture primed the way sendAttachments primes it (primeLocalMediaPreview).

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/image_bubble.dart';
import 'package:fluffychat/pages/chat/events/media_sending_indicator.dart';
import 'package:fluffychat/utils/local_media_preview.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

final _out = Directory('build/send_media_states');

/// A landscape test photo with hard edges, so any blur would show.
Future<Uint8List> _photo(int width, int height) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  final w = width.toDouble();
  final h = height.toDouble();
  canvas.drawRect(
    Rect.fromLTWH(0, 0, w, h),
    Paint()
      ..shader = ui.Gradient.linear(Offset.zero, Offset(0, h), [
        const Color(0xFF1E88E5),
        const Color(0xFFFFCC80),
      ]),
  );
  canvas.drawCircle(
    Offset(w * 0.72, h * 0.3),
    h * 0.12,
    Paint()..color = const Color(0xFFFFF176),
  );
  final hills = Path()
    ..moveTo(0, h * 0.75)
    ..lineTo(w * 0.3, h * 0.45)
    ..lineTo(w * 0.55, h * 0.7)
    ..lineTo(w * 0.8, h * 0.5)
    ..lineTo(w, h * 0.72)
    ..lineTo(w, h)
    ..lineTo(0, h)
    ..close();
  canvas.drawPath(hills, Paint()..color = const Color(0xFF2E7D32));
  // A checkerboard strip: one-pixel-sharp edges.
  final cell = (w / 24).roundToDouble();
  for (var x = 0; x * cell < w; x++) {
    for (var y = 0; y < 2; y++) {
      if ((x + y).isEven) {
        canvas.drawRect(
          Rect.fromLTWH(x * cell, h - (y + 1) * cell, cell, cell),
          Paint()..color = const Color(0xFF212121),
        );
      }
    }
  }
  final image = await recorder.endRecording().toImage(width, height);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;
  late Uint8List photo;
  late Uint8List poster;

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
    // The icon font ships with the Flutter SDK, beside the test engine.
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
    client = await setUpFakeChatList('send media states');
    room = addFakeChat(client, '!self:x', 'Gray Adams', partner: '@gray:x');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() {
    MxcImage.clearCache(room.id);
    tearDownFakeChatList(client);
  });

  Event echo(
    String txid,
    Map<String, Object?> content,
    EventStatus status,
    DateTime at,
  ) => Event(
    content: content,
    type: EventTypes.Message,
    eventId: txid,
    senderId: '@me:x',
    originServerTs: at,
    status: status,
    unsigned: {'transaction_id': txid},
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

  /// Shows the chat with [events] after it, once the previous page is
  /// gone, since a chat page empties its room's image cache when it is
  /// disposed; [prime] then primes the pictures, as sendAttachments does.
  Future<void> show(
    WidgetTester tester,
    Brightness brightness,
    List<Event> events, {
    required void Function() prime,
  }) async {
    await tester.pumpWidget(const SizedBox());
    prime();
    tester.view.physicalSize = const Size(412 * 2, 760 * 2);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    room.setMessages(['Here are the pictures from today']);
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
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  for (final brightness in Brightness.values) {
    testWidgets('photo and video while sending, ${brightness.name}', (
      tester,
    ) async {
      await tester.runAsync(() async {
        photo = await _photo(1600, 1200);
        poster = await _photo(540, 960);
      });
      final now = DateTime.now();
      final image = MatrixImageFile(
        bytes: photo,
        name: 'PXL_20261127.jpg',
        mimeType: 'image/png',
        width: 1600,
        height: 1200,
      );
      final video = MatrixVideoFile(
        bytes: Uint8List(8),
        name: 'PXL_20261127.mp4',
        mimeType: 'video/mp4',
        width: 1080,
        height: 1920,
        duration: 8000,
      );
      void primePhoto() =>
          primeLocalMediaPreview(room: room, txid: 'txn-photo', file: image);
      void primeVideo() => primeLocalMediaPreview(
        room: room,
        txid: 'txn-video',
        file: video,
        thumbnail: MatrixImageFile(bytes: poster, name: 'poster.png'),
      );
      Map<String, Object?> content(MatrixFile file) => {
        'msgtype': file.msgType,
        'body': file.name,
        'filename': file.name,
        'info': file.info,
      };

      // The moment of sending: sharp at once, before the ring's delay.
      await show(tester, brightness, [
        echo('txn-photo', content(image), EventStatus.sending, now),
      ], prime: primePhoto);
      expect(find.byType(ImageBubble), findsOneWidget);
      await capture(tester, 'photo_sending_0ms_${brightness.name}');

      // Uploading: the ring has scaled in.
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byType(MediaSendingIndicator), findsOneWidget);
      await capture(tester, 'photo_uploading_${brightness.name}');

      // Sent: the ring is gone and the bubble is unchanged.
      await show(tester, brightness, [
        echo('txn-photo', content(image), EventStatus.sent, now),
      ], prime: primePhoto);
      await tester.pump(const Duration(milliseconds: 600));
      await capture(tester, 'photo_sent_${brightness.name}');

      // A video, uploading: its poster frame from the file.
      await show(tester, brightness, [
        echo('txn-video', content(video), EventStatus.sending, now),
      ], prime: primeVideo);
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump(const Duration(milliseconds: 300));
      await capture(tester, 'video_uploading_${brightness.name}');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
