// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/image_bubble.dart';
import 'package:fluffychat/pages/chat/events/pending_media_tile.dart';
import 'package:fluffychat/utils/pending_media.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';
import '../utils/pending_media_fixtures.dart';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;
  const ghost = '@gmessages_15551234567:x';
  var rooms = 0;

  setUp(() async {
    client = await setUpFakeChatList('pending media chat');
    // A chat of its own per test: with one ID for all, the second test's
    // tile stayed off screen.
    room = addFakeChat(client, '!sms${++rooms}:x', 'Parla', partner: ghost);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Settles until [finder] finds something on screen, for a timeline that
  /// catches up at its own pace, then a little longer for the message's
  /// entrance to finish.
  Future<void> settleUntil(WidgetTester tester, Finder finder) async {
    for (var i = 0; i < 40 && finder.evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    await tester.pump(const Duration(milliseconds: 500));
  }

  Future<void> receive(WidgetTester tester, List<MatrixEvent> events) async {
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'b${events.first.eventId}',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                timeline: TimelineUpdate(events: events),
              ),
            },
          ),
        ),
      ),
    );
  }

  final start = DateTime.now().subtract(const Duration(minutes: 5));

  MatrixEvent placeholder(String id, String name, {bool flag = true}) =>
      MatrixEvent(
        type: EventTypes.Message,
        content: {
          'msgtype': MessageTypes.Notice,
          'body': 'Waiting for attachment $name',
          PendingMedia.pendingKey: ?(flag ? true : null),
          PendingMedia.rawDebugDataKey: rawDebugData([
            mediaContent(
              name: name,
              width: 4032,
              height: 3024,
              preview: previewJpeg(width: 63, height: 47),
            ),
          ]),
        },
        senderId: ghost,
        eventId: id,
        originServerTs: start,
      );

  MatrixEvent edit(String id, String target, Map<String, Object?> media) =>
      MatrixEvent(
        type: EventTypes.Message,
        content: {
          ...media,
          'com.beeper.dont_render_edited': true,
          'm.new_content': media,
          'm.relates_to': {'event_id': target, 'rel_type': 'm.replace'},
        },
        senderId: ghost,
        eventId: id,
        originServerTs: start.add(const Duration(seconds: 10)),
      );

  Future<void> openChat(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
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
      Provider<MatrixState>.value(
        value: _Matrix(client, prefs),
        child: MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);
  }

  testWidgets('a placeholder is a tile until its edit swaps the photo in', (
    tester,
  ) async {
    await openChat(tester);
    await receive(tester, [placeholder(r'$p1', 'PXL_1.jpg')]);
    await settleUntil(tester, find.byType(PendingMediaTile));
    expect(find.byType(PendingMediaTile), findsOneWidget);
    expect(
      find.text('Waiting for attachment PXL_1.jpg', findRichText: true),
      findsNothing,
    );
    // The hint gives the photo's landscape shape from the start.
    expect(
      tester
          .getSize(
            find.descendant(
              of: find.byType(PendingMediaTile),
              matching: find.byType(Material),
            ),
          )
          .width,
      256,
    );

    await receive(tester, [
      edit(r'$e1', r'$p1', {
        'msgtype': MessageTypes.Image,
        'body': 'PXL_1.jpg',
        'info': {'mimetype': 'image/jpeg', 'w': 4032, 'h': 3024},
        'url': 'mxc://x/one',
      }),
    ]);
    // Mid swap: the tile fades out over the photo fading in.
    for (
      var i = 0;
      i < 100 && find.byType(ImageBubble).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.byType(PendingMediaTile), findsOneWidget);
    expect(find.byType(ImageBubble), findsOneWidget);
    expect(find.byType(PendingMediaSwitcher), findsOneWidget);

    await settle(tester);
    expect(find.byType(PendingMediaTile), findsNothing);
    expect(find.byType(ImageBubble), findsOneWidget);
    expect(find.text('(edited)'), findsNothing);
  });

  testWidgets('a placeholder whose transfer fails shows the failed tile', (
    tester,
  ) async {
    await openChat(tester);
    await receive(tester, [placeholder(r'$p1', 'clip.mp4', flag: false)]);
    await settleUntil(tester, find.byType(PendingMediaTile));
    expect(find.byType(PendingMediaTile), findsOneWidget);

    await receive(tester, [
      edit(r'$e1', r'$p1', {
        'msgtype': MessageTypes.Notice,
        'body': 'Failed to transfer attachment clip.mp4',
      }),
    ]);
    await settleUntil(tester, find.text("Video didn't arrive"));
    expect(find.byType(PendingMediaTile), findsOneWidget);
    expect(find.text("Video didn't arrive"), findsOneWidget);
  });

  testWidgets('an ordinary notice from another sender stays text', (
    tester,
  ) async {
    await openChat(tester);
    await receive(tester, [
      MatrixEvent(
        type: EventTypes.Message,
        content: {
          'msgtype': MessageTypes.Notice,
          'body': 'Waiting for attachment PXL_1.jpg',
        },
        senderId: '@whatsappbot:x',
        eventId: r'$n1',
        originServerTs: start,
      ),
    ]);
    await settleUntil(
      tester,
      find.text('Waiting for attachment PXL_1.jpg', findRichText: true),
    );
    expect(find.byType(PendingMediaTile), findsNothing);
    expect(
      find.text('Waiting for attachment PXL_1.jpg', findRichText: true),
      findsOneWidget,
    );
  });
}
