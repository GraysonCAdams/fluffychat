// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/status_mark.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
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
    client = await setUpFakeChatList('read status test');
  });

  tearDown(() => tearDownFakeChatList(client));

  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day);
  final sentAt = today.add(const Duration(hours: 1));
  // 1:33 PM today, unless that is still to come, then a minute ago.
  final readToday =
      today.add(const Duration(hours: 13, minutes: 33)).isAfter(now)
      ? now.subtract(const Duration(minutes: 1))
      : today.add(const Duration(hours: 13, minutes: 33));
  final readYesterday = today.subtract(
    const Duration(hours: 2, minutes: 58),
  ); // 9:02 PM yesterday

  void addMember(Room room, String id, String name) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': name},
      senderId: id,
      stateKey: id,
    ),
  );

  Room groupRoom() {
    final room = addFakeChat(client, '!group:x', 'Drew, Harrison');
    addMember(room, '@drew:x', 'Drew Andersen');
    addMember(room, '@harrison:x', 'Harrison Young');
    addMember(room, client.userID!, 'Gray');
    return room;
  }

  Room direct([String id = '!anne:x']) =>
      addFakeChat(client, id, 'Anne Chodzko', partner: '@anne:x');

  Event text(Room room, String body, String senderId, int minute) => Event(
    content: {'msgtype': 'm.text', 'body': body},
    type: EventTypes.Message,
    eventId: '\$$body',
    senderId: senderId,
    originServerTs: sentAt.add(Duration(minutes: minute)),
    status: EventStatus.synced,
    room: room,
  );

  /// Gives each of [readers] an m.read receipt on [event] at its time.
  void readUpTo(Room room, Event event, Map<String, DateTime> readers) {
    room.receiptState = LatestReceiptState(
      global: LatestReceiptStateForTimeline(
        ownPrivate: null,
        ownPublic: null,
        latestOwnReceipt: null,
        otherUsers: {
          for (final MapEntry(key: id, value: time) in readers.entries)
            id: LatestReceiptStateData(
              event.eventId,
              time.millisecondsSinceEpoch,
            ),
        },
      ),
    );
  }

  /// Shows [events], newest first as the timeline holds them, with the
  /// user's newest message showing its status, as the chat screen does.
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

  final faces = find.byWidgetPredicate(
    (widget) => widget is Avatar && widget.size == 16,
  );
  Finder markIn(StatusMarkState state) => find.byWidgetPredicate(
    (widget) => widget is StatusMark && widget.state == state,
  );
  final sentMark = markIn(StatusMarkState.sent);
  final readMark = markIn(StatusMarkState.read);

  String timeOfDay(DateTime time) {
    final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
    final minute = time.minute.toString().padLeft(2, '0');
    return '$hour:$minute ${time.hour < 12 ? 'AM' : 'PM'}';
  }

  group('a direct chat', () {
    testWidgets('shows one sent mark and no face before it is read', (
      tester,
    ) async {
      final room = direct();
      await pumpTimeline(tester, room, [
        text(room, 'still around?', client.userID!, 2),
        text(room, 'hi', '@anne:x', 1),
      ]);
      expect(sentMark, findsOneWidget);
      expect(readMark, findsNothing);
      expect(faces, findsNothing);
      expect(find.byTooltip('Sent'), findsOneWidget);
    });

    testWidgets('turns the mark into a read mark, with no face', (
      tester,
    ) async {
      final room = direct();
      final mine = text(room, 'still around?', client.userID!, 2);
      readUpTo(room, mine, {'@anne:x': readToday});
      await pumpTimeline(tester, room, [mine, text(room, 'hi', '@anne:x', 1)]);

      expect(readMark, findsOneWidget);
      expect(sentMark, findsNothing);
      expect(faces, findsNothing);
      expect(find.byType(Avatar), findsNothing);
      // Read is told by shape, in the status line's own colour.
      final mark = tester.widget<StatusMark>(readMark);
      final context = tester.element(readMark);
      expect(mark.color, Theme.of(context).colorScheme.onSurfaceVariant);
      // On the line right under the bubble.
      expect(
        tester.getTopLeft(readMark).dy,
        greaterThanOrEqualTo(
          tester.getBottomLeft(find.text('still around?')).dy,
        ),
      );
      expect(
        tester.getTopLeft(readMark).dy -
            tester.getBottomLeft(find.text('still around?')).dy,
        lessThan(24),
      );
    });

    testWidgets('a tap on the read mark says when it was read', (tester) async {
      final room = direct();
      final mine = text(room, 'still around?', client.userID!, 2);
      readUpTo(room, mine, {'@anne:x': readToday});
      await pumpTimeline(tester, room, [mine]);

      final label = 'Read ${timeOfDay(readToday)}';
      expect(find.text(label), findsNothing);
      await tester.tap(readMark);
      await tester.pumpAndSettle();
      expect(find.text(label), findsOneWidget);
    });

    testWidgets('a read from yesterday says yesterday', (tester) async {
      final room = direct();
      final mine = text(room, 'still around?', client.userID!, -600);
      readUpTo(room, mine, {'@anne:x': readYesterday});
      await pumpTimeline(tester, room, [mine]);

      await tester.tap(readMark);
      await tester.pumpAndSettle();
      expect(
        find.text('Read yesterday ${timeOfDay(readYesterday)}'),
        findsOneWidget,
      );
    });
  });

  group('a group', () {
    testWidgets('puts the readers\' faces left of the mark, on its line', (
      tester,
    ) async {
      final room = groupRoom();
      final newest = text(room, 'seven pm?', client.userID!, 3);
      final older = text(room, 'booking a table', client.userID!, 2);
      readUpTo(room, newest, {
        '@drew:x': readToday,
        '@harrison:x': readYesterday,
      });
      await pumpTimeline(tester, room, [
        newest,
        older,
        text(room, 'saturday', '@drew:x', 1),
      ]);

      expect(find.text('Seen by'), findsNothing);
      expect(faces, findsNWidgets(2));
      expect(sentMark, findsOneWidget);
      final mark = tester.getRect(sentMark);
      for (final face in tester.widgetList<Avatar>(faces)) {
        final rect = tester.getRect(find.byWidget(face));
        expect(rect.right, lessThanOrEqualTo(mark.left));
        expect(rect.center.dy, closeTo(mark.center.dy, 1));
      }
      // Under the newest message, not between the two.
      expect(
        mark.top,
        greaterThan(tester.getBottomLeft(find.text('seven pm?')).dy),
      );
    });

    testWidgets('a tap on the faces lists who read it and when', (
      tester,
    ) async {
      final room = groupRoom();
      final newest = text(room, 'seven pm?', client.userID!, 3);
      readUpTo(room, newest, {
        '@drew:x': readToday,
        '@harrison:x': readYesterday,
      });
      await pumpTimeline(tester, room, [newest]);

      await tester.tap(faces.first);
      await tester.pumpAndSettle();
      expect(find.text('Drew Andersen'), findsOneWidget);
      expect(find.text('Read ${timeOfDay(readToday)}'), findsOneWidget);
      expect(find.text('Harrison Young'), findsOneWidget);
      expect(
        find.text('Read yesterday ${timeOfDay(readYesterday)}'),
        findsOneWidget,
      );
      // Newest read first.
      expect(
        tester.getTopLeft(find.text('Drew Andersen')).dy,
        lessThan(tester.getTopLeft(find.text('Harrison Young')).dy),
      );
    });

    testWidgets('with no readers shows only the sent mark', (tester) async {
      final room = groupRoom();
      await pumpTimeline(tester, room, [
        text(room, 'seven pm?', client.userID!, 3),
      ]);
      expect(sentMark, findsOneWidget);
      expect(faces, findsNothing);
    });
  });

  group('readReceiptsOf', () {
    test('counts only receipts in the message\'s own room', () {
      final imessage = direct('!imessage:x');
      final gmessages = direct('!gmessages:x');
      final mine = text(imessage, 'mine', client.userID!, 1);
      final later = text(gmessages, 'later', client.userID!, 2);
      // Anne read the later message on the other network only.
      readUpTo(gmessages, later, {'@anne:x': readToday});
      final timeline = Timeline(
        room: imessage,
        chunk: TimelineChunk(events: [later, mine]),
      );
      expect(imessage.readReceiptsOf(mine, timeline), isEmpty);
      expect(gmessages.readReceiptsOf(later, timeline), hasLength(1));
    });

    test('leaves out the bridge bot', () {
      final room = direct();
      room.setState(
        StrippedStateEvent(
          type: 'm.bridge',
          content: {'bridgebot': '@gmessagesbot:x'},
          senderId: '@gmessagesbot:x',
          stateKey: 'gmessages',
        ),
      );
      final mine = text(room, 'mine', client.userID!, 1);
      readUpTo(room, mine, {'@gmessagesbot:x': readToday});
      final timeline = Timeline(
        room: room,
        chunk: TimelineChunk(events: [mine]),
      );
      expect(room.readReceiptsOf(mine, timeline), isEmpty);
    });

    test('keeps each reader once, with their receipt time', () {
      final room = groupRoom();
      final mine = text(room, 'mine', client.userID!, 1);
      final later = text(room, 'later', '@drew:x', 2);
      readUpTo(room, later, {'@harrison:x': readToday, '@drew:x': readToday});
      final timeline = Timeline(
        room: room,
        chunk: TimelineChunk(events: [later, mine]),
      );
      final receipts = room.readReceiptsOf(mine, timeline);
      expect(
        receipts.map((r) => r.user.id),
        unorderedEquals(['@harrison:x', '@drew:x']),
      );
      expect(
        receipts.first.time.millisecondsSinceEpoch,
        readToday.millisecondsSinceEpoch,
      );
      // The sender of a message is never its reader.
      expect(room.readReceiptsOf(later, timeline).map((r) => r.user.id), [
        '@harrison:x',
      ]);
    });
  });
}
