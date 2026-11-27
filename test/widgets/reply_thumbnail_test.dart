// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/reply_content.dart';
import 'package:fluffychat/pages/chat/reply_display.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

/// A quote of a photo, video or sticker shows a small thumbnail of it and
/// a short label, in the bubble and in the composer's reply bar.
void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;
  var serial = 0;

  setUp(() async {
    client = await setUpFakeChatList('reply thumbnails');
    room = addFakeChat(client, '!gray:x', 'Gray Adams', partner: '@gray:x');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() => tearDownFakeChatList(client));

  Event event(
    Map<String, Object?> content, {
    String type = EventTypes.Message,
    bool redacted = false,
  }) => Event(
    content: content,
    type: type,
    eventId: '\$e${serial++}',
    senderId: '@gray:x',
    originServerTs: DateTime(2026),
    room: room,
    unsigned: redacted
        ? {
            'redacted_because': {
              'type': EventTypes.Redaction,
              'sender': '@gray:x',
              'event_id': '\$redaction',
              'origin_server_ts': 0,
              'content': {},
            },
          }
        : null,
  );

  final photo = {
    'msgtype': MessageTypes.Image,
    'body': 'PXL_1.jpg',
    'filename': 'PXL_1.jpg',
    'url': 'mxc://x/photo',
    'info': {'mimetype': 'image/jpeg', 'w': 800, 'h': 600},
  };

  /// Lets the localizations load and the page build.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> quote(WidgetTester tester, Event replied) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: Center(child: ReplyContent(replied))),
      ),
    );
    await settle(tester);
  }

  Finder thumbnail() => find.descendant(
    of: find.byType(ReplyContent),
    matching: find.byType(MxcImage),
  );

  testWidgets('a quoted photo shows its thumbnail and "Photo"', (tester) async {
    await quote(tester, event(photo));
    expect(thumbnail(), findsOneWidget);
    expect(tester.getSize(thumbnail()), const Size(40, 40));
    expect(find.text('Photo'), findsOneWidget);
    expect(find.textContaining('sent a picture'), findsNothing);
  });

  testWidgets('a quoted photo with a caption shows the caption', (
    tester,
  ) async {
    await quote(tester, event({...photo, 'body': 'Sunset from the roof'}));
    expect(thumbnail(), findsOneWidget);
    expect(find.text('Sunset from the roof'), findsOneWidget);
  });

  testWidgets('a quoted video shows its poster frame and a play badge', (
    tester,
  ) async {
    await quote(
      tester,
      event({
        'msgtype': MessageTypes.Video,
        'body': 'VID.mp4',
        'filename': 'VID.mp4',
        'url': 'mxc://x/video',
        'info': {
          'duration': 12000,
          'thumbnail_url': 'mxc://x/poster',
          'thumbnail_info': {'mimetype': 'image/jpeg'},
        },
      }),
    );
    expect(thumbnail(), findsOneWidget);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
    expect(find.text('Video 0:12'), findsOneWidget);
  });

  testWidgets('a quoted video without a poster still shows the badge', (
    tester,
  ) async {
    await quote(
      tester,
      event({
        'msgtype': MessageTypes.Video,
        'body': 'VID.mp4',
        'filename': 'VID.mp4',
        'url': 'mxc://x/video',
      }),
    );
    // Nothing to load: the video itself is not fetched for a thumbnail.
    expect(thumbnail(), findsNothing);
    expect(find.byIcon(Icons.play_arrow_rounded), findsOneWidget);
  });

  testWidgets('a quoted sticker shows its image', (tester) async {
    await quote(
      tester,
      event({
        'body': 'thumbs up',
        'url': 'mxc://x/sticker',
        'info': {'mimetype': 'image/png'},
      }, type: EventTypes.Sticker),
    );
    expect(thumbnail(), findsOneWidget);
    expect(find.text('Sticker'), findsOneWidget);
  });

  testWidgets('Invisible Ink media shows no thumbnail', (tester) async {
    await quote(tester, event(withEffect(photo, MessageEffect.invisibleInk)));
    expect(thumbnail(), findsNothing);
    expect(find.text('Sent with Invisible Ink'), findsOneWidget);
  });

  testWidgets('a removed photo reads as today, without a thumbnail', (
    tester,
  ) async {
    await quote(tester, event(photo, redacted: true));
    expect(thumbnail(), findsNothing);
    expect(find.text('Photo'), findsNothing);
  });

  testWidgets('a quoted text message reads as before', (tester) async {
    await quote(
      tester,
      event({'msgtype': MessageTypes.Text, 'body': 'See you at 7'}),
    );
    expect(thumbnail(), findsNothing);
    expect(find.text('See you at 7'), findsOneWidget);
  });

  testWidgets('the composer reply bar shows the thumbnail too', (tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _Matrix(client, prefs),
        child: MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/chat',
            routes: [
              GoRoute(
                path: '/chat',
                builder: (_, _) => ChatPage(roomId: room.id),
              ),
            ],
          ),
        ),
      ),
    );
    await settle(tester);
    final chat = tester.state<ChatController>(find.byType(ChatPageWithRoom));
    chat.replyAction(replyTo: event(photo));
    for (var i = 0; i < 4; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    final bar = find.byType(ReplyDisplay);
    expect(
      find.descendant(of: bar, matching: find.byType(MxcImage)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: bar, matching: find.text('Photo')),
      findsOneWidget,
    );
  });
}
