// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('group messages test');
  });

  tearDown(() => tearDownFakeChatList(client));

  final sentAt = DateTime(2026, 11, 20, 10, 58);

  void addMember(Room room, String id, String name) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': name},
      senderId: id,
      stateKey: id,
    ),
  );

  Room group() {
    final room = addFakeChat(client, '!group:x', 'Drew, Harrison');
    addMember(room, '@drew:x', 'Drew Andersen');
    addMember(room, '@harrison:x', 'Harrison Young');
    addMember(room, client.userID!, 'Gray');
    return room;
  }

  Room direct() =>
      addFakeChat(client, '!anne:x', 'Anne Chodzko', partner: '@anne:x');

  Event text(Room room, String body, String senderId, int minute) => Event(
    content: {'msgtype': 'm.text', 'body': body},
    type: EventTypes.Message,
    eventId: '\$$body',
    senderId: senderId,
    originServerTs: sentAt.add(Duration(minutes: minute)),
    status: EventStatus.synced,
    room: room,
  );

  /// Shows [events], given newest first as the timeline holds them, top to
  /// bottom from the oldest, wired up as the chat screen does: each message
  /// knows the older one above it and the newer one below, and the user's
  /// newest message shows its delivery state.
  Future<void> pumpTimeline(
    WidgetTester tester,
    Room room,
    List<Event> events,
  ) async {
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(events: events),
    );
    final newestOwn = events.firstWhereOrNull(
      (e) => e.senderId == client.userID,
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ListView(
              controller: scrollController,
              children: [
                for (var i = events.length - 1; i >= 0; i--)
                  Message(
                    events[i],
                    nextEvent: i + 1 < events.length ? events[i + 1] : null,
                    previousEvent: i > 0 ? events[i - 1] : null,
                    bigEmojis: const {},
                    onSelect: (_) {},
                    showDeliveryStatus: identical(events[i], newestOwn),
                    onInfoTab: (_) {},
                    scrollToEventId: (_) {},
                    onSwipe: () {},
                    onMention: () {},
                    onEdit: () {},
                    enterThread: null,
                    singleSelected: false,
                    hideReactionPicker: true,
                    timeline: timeline,
                    scrollController: scrollController,
                    colors: const [Colors.blue, Colors.blue],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Checks that the text [body] covers [expected], to the tenth of a
  /// pixel the measurement was printed with.
  void expectRect(WidgetTester tester, String body, Rect expected) {
    final actual = tester.getRect(find.text(body));
    for (final (a, e) in [
      (actual.left, expected.left),
      (actual.top, expected.top),
      (actual.right, expected.right),
      (actual.bottom, expected.bottom),
    ]) {
      expect(a, closeTo(e, 0.06), reason: '$body: $actual');
    }
  }

  testWidgets('a run in a group: grey name above, avatar by the last bubble', (
    tester,
  ) async {
    final room = group();
    await pumpTimeline(tester, room, [
      text(room, 'three', '@drew:x', 3),
      text(room, 'two', '@drew:x', 2),
      text(room, 'one', '@drew:x', 1),
    ]);

    // The name once, small and grey, above the first bubble.
    final name = find.text('Drew Andersen');
    expect(name, findsOneWidget);
    final style = tester.widget<Text>(name).style!;
    final context = tester.element(name);
    expect(style.fontSize, 12);
    expect(style.color, Theme.of(context).colorScheme.onSurfaceVariant);
    expect(
      tester.getBottomLeft(name).dy,
      lessThanOrEqualTo(tester.getTopLeft(find.text('one')).dy),
    );

    // One avatar, level with the last bubble and left of it.
    final avatar = find.byType(Avatar);
    expect(avatar, findsOneWidget);
    final avatarRect = tester.getRect(avatar);
    final three = tester.getRect(find.text('three'));
    expect(
      avatarRect.center.dy,
      greaterThan(tester.getRect(find.text('two')).bottom),
    );
    expect(avatarRect.bottom, greaterThanOrEqualTo(three.bottom));
    expect(avatarRect.top, lessThanOrEqualTo(three.top));
    expect(avatarRect.right, lessThan(three.left));
    // Every bubble of the run starts at the same indent, 8dp past the
    // avatar, and the name starts there too.
    for (final body in ['one', 'two']) {
      expect(tester.getTopLeft(find.text(body)).dx, three.left);
    }
    expect(tester.getTopLeft(name).dx, lessThan(three.left));
    expect(tester.getTopLeft(name).dx, greaterThan(avatarRect.right));
  });

  testWidgets('a direct chat has no names or avatars and keeps its layout', (
    tester,
  ) async {
    final room = direct();
    await pumpTimeline(tester, room, [
      text(room, 'mine', client.userID!, 4),
      text(room, 'three', '@anne:x', 3),
      text(room, 'two', '@anne:x', 2),
      text(room, 'one', '@anne:x', 1),
    ]);

    expect(find.byType(Avatar), findsNothing);
    expect(find.text('Anne Chodzko'), findsNothing);
    // Measured before group runs got their own layout, which must not
    // reach direct chats.
    expectRect(tester, 'one', const Rect.fromLTRB(44.0, 16.0, 92.8, 40.0));
    expectRect(tester, 'two', const Rect.fromLTRB(44.0, 58.0, 92.8, 82.0));
    expectRect(tester, 'three', const Rect.fromLTRB(44.0, 100.0, 125.3, 124.0));
    expectRect(tester, 'mine', const Rect.fromLTRB(691.0, 156.0, 756.0, 180.0));
    expect(find.text('Seen by'), findsNothing);
  });

  /// Marks [event] as read by each of [userIds], as their receipts do.
  void readUpTo(Room room, Event event, List<String> userIds) {
    room.receiptState = LatestReceiptState(
      global: LatestReceiptStateForTimeline(
        ownPrivate: null,
        ownPublic: null,
        latestOwnReceipt: null,
        otherUsers: {
          for (final id in userIds)
            id: LatestReceiptStateData(event.eventId, 0),
        },
      ),
    );
  }

  testWidgets('a group shows Seen by under the user\'s last message only', (
    tester,
  ) async {
    final room = group();
    final newest = text(room, 'seven pm?', client.userID!, 3);
    final older = text(room, 'booking a table', client.userID!, 2);
    readUpTo(room, newest, ['@drew:x', '@harrison:x']);
    await pumpTimeline(tester, room, [
      newest,
      older,
      text(room, 'saturday', '@drew:x', 1),
    ]);

    final seenBy = find.text('Seen by');
    expect(seenBy, findsOneWidget);
    // Under the newest message, not between the two.
    expect(
      tester.getTopLeft(seenBy).dy,
      greaterThan(tester.getBottomLeft(find.text('seven pm?')).dy),
    );
    // With a face for each reader after it.
    final faces = find.byWidgetPredicate(
      (widget) => widget is Avatar && widget.size == 16,
    );
    expect(faces, findsNWidgets(2));
    for (final face in tester.widgetList<Avatar>(faces)) {
      expect(
        tester.getTopLeft(find.byWidget(face)).dx,
        greaterThan(tester.getTopRight(seenBy).dx),
      );
    }
  });

  testWidgets('a direct chat has no Seen by label', (tester) async {
    final room = direct();
    final mine = text(room, 'mine', client.userID!, 2);
    readUpTo(room, mine, ['@anne:x']);
    await pumpTimeline(tester, room, [mine, text(room, 'hi', '@anne:x', 1)]);
    expect(find.text('Seen by'), findsNothing);
  });
}
