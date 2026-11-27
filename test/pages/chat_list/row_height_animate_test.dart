// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'chat_list_fakes.dart';

/// A chat list row that changes height on screen, as when its preview goes
/// from one line to two, grows smoothly and the rows below slide with it.
void main() {
  late FakeChatListClient client;
  late Map<int, FakeChatListRoom> rooms;

  setUp(() async {
    client = await setUpFakeChatList('row height animate test');
    rooms = {};
    for (var i = 0; i < 60; i++) {
      final room = rooms[i] = addFakeChat(
        client,
        '!c$i:x',
        'Chat $i',
        lastMessageTime: DateTime(2026, 1, 1).subtract(Duration(hours: i)),
      );
      // Long enough to take two lines once the row allows them.
      room.lastEvent = Event(
        content: {
          'msgtype': 'm.text',
          'body':
              'A long message about the weekend plans that goes on well '
              'past one line of the preview, and then some more words',
        },
        type: EventTypes.Message,
        eventId: '\$c$i-last',
        senderId: '@someone:x',
        originServerTs: DateTime(2026, 1, 1).subtract(Duration(hours: i)),
        room: room,
      );
    }
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<void> pumpPhone(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await pumpFakeChatList(tester, client);
  }

  Finder row(int i) => find.ancestor(
    of: find.text('Chat $i'),
    matching: find.byType(ChatListItem),
  );

  /// Makes chat 1 unread, which lets its preview take two lines, as a sync
  /// reports it.
  void makeUnread() {
    rooms[1]!.notificationCount = 1;
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'next',
        rooms: RoomsUpdate(join: {rooms[1]!.id: JoinedRoomUpdate()}),
      ),
    );
  }

  testWidgets('a row that grows on screen animates, the rows below slide', (
    tester,
  ) async {
    await pumpPhone(tester);
    final before = tester.getRect(row(1)).height;
    final belowBefore = tester.getRect(row(2)).top;
    final above = tester.getRect(row(0));

    makeUnread();
    // The sync reaches the list on the next frame, which lays the row out
    // anew and starts its change.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 100));
    final during = tester.getRect(row(1)).height;
    final belowDuring = tester.getRect(row(2)).top;

    await tester.pumpAndSettle();
    final after = tester.getRect(row(1)).height;
    final belowAfter = tester.getRect(row(2)).top;
    expect(after, greaterThan(before));
    expect(during, inExclusiveRange(before, after));
    expect(belowDuring, inExclusiveRange(belowBefore, belowAfter));
    // The row above stays put.
    expect(tester.getRect(row(0)), above);

    await tester.pump(const Duration(seconds: 2));
    await finishFakeChatList(tester, client);
  });

  testWidgets('a row scrolling in is laid out at once', (tester) async {
    await pumpPhone(tester);
    rooms[40]!.notificationCount = 1;
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -2400));
    await tester.pump();
    final first = tester.getRect(row(40));
    await tester.pumpAndSettle();
    expect(tester.getRect(row(40)).height, first.height);

    await finishFakeChatList(tester, client);
  });

  testWidgets('with animations off the row changes at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpPhone(tester);
    final before = tester.getRect(row(1)).height;

    makeUnread();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final at = tester.getRect(row(1)).height;
    await tester.pumpAndSettle();
    expect(at, greaterThan(before));
    expect(tester.getRect(row(1)).height, at);

    await tester.pump(const Duration(seconds: 2));
    await finishFakeChatList(tester, client);
  });
}
