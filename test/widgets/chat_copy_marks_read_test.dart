// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';
import '../utils/merged_contacts/fake_rooms.dart' show setMergedContacts;

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

/// Copying a message in the chat screen marks its room read up to that
/// message, also in the views that hold read receipts back on their own:
/// a chat opened at a message (a search result or a notification), the
/// window in the background, and a merged contact's chat.
void main() {
  late FakeChatListClient client;
  String? clipboard;

  setUp(() async {
    client = await setUpFakeChatList('chat copy marks read');
    clipboard = null;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
    messenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
      if (call.method == 'Clipboard.setData') {
        clipboard = (call.arguments as Map)['text'] as String?;
      }
      return null;
    });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
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

  /// An unread chat whose newest message, from the bank, is a code.
  FakeChatListRoom bankChat(String id, {int unread = 1}) {
    final room = addFakeChat(
      client,
      id,
      'Bank',
      partner: '@bank:x',
      notificationCount: unread,
    );
    room.setMessages([
      'Your statement is ready',
      'Thanks',
      'Your verification code is 282295',
    ], partner: '@bank:x');
    return room;
  }

  Future<ChatController> open(WidgetTester tester, ChatPage page) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [GoRoute(path: '/chat', builder: (_, _) => page)],
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
    return tester.state<ChatController>(find.byType(ChatPageWithRoom));
  }

  Future<void> copy(
    WidgetTester tester,
    ChatController chat,
    Event event,
  ) async {
    chat.selectOnly(event);
    await tester.pump();
    chat.copyEventsAction();
    await settle(tester);
  }

  testWidgets('a chat opened at an older message stays unread until the '
      'code is copied', (tester) async {
    final room = bankChat('!bank:x');
    final chat = await open(
      tester,
      ChatPage(roomId: room.id, eventId: room.timelineEvents!.first.eventId),
    );
    expect(room.readMarkers, isEmpty);

    final code = room.timelineEvents!.last;
    await copy(tester, chat, code);
    expect(clipboard, 'Your verification code is 282295');
    expect(room.readMarkers, [code.eventId]);
  });

  testWidgets('copying a message older than the read marker of an unread '
      'chat does not move the marker back', (tester) async {
    final room = bankChat('!bank:x');
    // Read up to the user's own reply; the code after it is unread.
    final reply = room.timelineEvents![1];
    final receipt = LatestReceiptStateData(
      reply.eventId,
      reply.originServerTs.add(const Duration(seconds: 1)).millisecondsSinceEpoch,
    );
    room.receiptState = LatestReceiptState(
      global: LatestReceiptStateForTimeline(
        ownPrivate: null,
        ownPublic: receipt,
        latestOwnReceipt: receipt,
        otherUsers: {},
      ),
    );
    final chat = await open(
      tester,
      ChatPage(roomId: room.id, eventId: room.timelineEvents!.first.eventId),
    );

    await copy(tester, chat, room.timelineEvents!.first);
    expect(room.readMarkers, isEmpty);
  });

  testWidgets('copying while the window is in the background marks the '
      'chat read', (tester) async {
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    addTearDown(
      () => tester.binding.handleAppLifecycleStateChanged(
        AppLifecycleState.resumed,
      ),
    );
    final room = bankChat('!bank:x');
    final chat = await open(tester, ChatPage(roomId: room.id));
    expect(room.readMarkers, isEmpty);

    final code = room.timelineEvents!.last;
    await copy(tester, chat, code);
    expect(room.readMarkers, [code.eventId]);
  });

  testWidgets('copying an older message of a read chat leaves the read '
      'marker where it is', (tester) async {
    final room = bankChat('!bank:x', unread: 0);
    // Read on another device: the user's receipt is on the newest message.
    final newest = room.timelineEvents!.last;
    final receipt = LatestReceiptStateData(
      newest.eventId,
      newest.originServerTs.add(const Duration(minutes: 1)).millisecondsSinceEpoch,
    );
    room.receiptState = LatestReceiptState(
      global: LatestReceiptStateForTimeline(
        ownPrivate: null,
        ownPublic: receipt,
        latestOwnReceipt: receipt,
        otherUsers: {},
      ),
    );
    final chat = await open(tester, ChatPage(roomId: room.id));
    room.readMarkers.clear();

    await copy(tester, chat, room.timelineEvents!.first);
    expect(clipboard, 'Your statement is ready');
    expect(room.readMarkers, isEmpty);
  });

  testWidgets('in a merged contact opened at a message, copying marks only '
      'the room the message is in', (tester) async {
    final imessage = bankChat('!bank-im:x');
    final sms = addFakeChat(
      client,
      '!bank-sms:x',
      'Bank',
      partner: '@bank:x',
      notificationCount: 1,
    );
    sms.setMessages([
      'Welcome to alerts',
    ], end: DateTime(2025, 12, 31, 23, 59));
    setMergedContacts(client, {
      'c_bank': {
        'rooms': [imessage.id, sms.id],
        'send_via': imessage.id,
        'updated': 1,
      },
    });
    final first = imessage.timelineEvents!.first;
    final chat = await open(
      tester,
      ChatPage(
        roomId: imessage.id,
        contactId: 'c_bank',
        eventId: first.eventId,
        eventRoomId: imessage.id,
      ),
    );
    expect(imessage.readMarkers, isEmpty);
    expect(sms.readMarkers, isEmpty);

    final code = imessage.timelineEvents!.last;
    await copy(tester, chat, code);
    expect(imessage.readMarkers, [code.eventId]);
    expect(sms.readMarkers, isEmpty);
  });
}
