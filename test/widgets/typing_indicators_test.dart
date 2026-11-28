// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/typing_indicators.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/typing_animation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/message_search/search_test_client.dart';

/// Stands in for the app's Matrix widget, which widgets only ask for its
/// client.
class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await createSearchTestClient();
  });

  void setTyping(Room room, List<String> userIds) =>
      room.ephemerals['m.typing'] = BasicEvent(
        type: 'm.typing',
        content: {'user_ids': userIds},
      );

  /// Shows [incoming] from [sender] in [room] with the typing row under it,
  /// the way the chat screen stacks them.
  Future<void> pump(
    WidgetTester tester, {
    required Room room,
    required String sender,
    required TypingIndicatorRow typing,
  }) async {
    // A sender missing from the room's state makes Message.build start a
    // database lookup of the member. That query finishes outside the test's
    // fake clock, so its 10 s lock-warning timer is still pending when the
    // test ends.
    if (room.getState(EventTypes.RoomMember, sender) == null) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          stateKey: sender,
          senderId: sender,
          content: {'membership': 'join'},
        ),
      );
    }
    final incoming = Event(
      content: {'msgtype': 'm.text', 'body': 'Hello there'},
      type: EventTypes.Message,
      eventId: '\$msg',
      senderId: sender,
      originServerTs: DateTime(2026, 11, 20, 10, 58),
      room: room,
    );
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(events: [incoming]),
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrix(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ListView(
              controller: scrollController,
              children: [
                Message(
                  incoming,
                  bigEmojis: const {},
                  onSelect: (_) {},
                  selected: false,
                  longPressSelect: false,
                  onInfoTab: (_) {},
                  scrollToEventId: (_) {},
                  onSwipe: () {},
                  onMention: () {},
                  onEdit: () {},
                  enterThread: null,
                  singleSelected: false,
                  hideReactionPicker: true,
                  timeline: timeline,
                ),
                typing,
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The decorated box that paints the bubble holding [text].
  Rect bubbleRect(WidgetTester tester, String text) => tester.getRect(
    find
        .ancestor(
          of: find.text(text, findRichText: true),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).borderRadius is BorderRadius &&
                w.clipBehavior == Clip.antiAlias,
          ),
        )
        .first,
  );

  Rect typingBubbleRect(WidgetTester tester) => tester.getRect(
    find
        .ancestor(
          of: find.byType(TypingAnimation),
          matching: find.byType(Material),
        )
        .first,
  );

  testWidgets('a one-to-one chat shows no avatar and lines the bubble up '
      'with the incoming ones', (tester) async {
    final room = client.getRoomById('!726s6s6q:example.com')!;
    expect(room.isDirectChat, isTrue);
    setTyping(room, ['@bob:example.com']);
    addTearDown(() => room.ephemerals.remove('m.typing'));

    await pump(
      tester,
      room: room,
      sender: '@bob:example.com',
      typing: TypingIndicatorRow(
        rooms: [room],
        oneToOne: true,
        newestFromOwn: false,
      ),
    );

    expect(
      find.descendant(
        of: find.byType(TypingIndicatorRow),
        matching: find.byType(Avatar),
      ),
      findsNothing,
    );
    final incoming = bubbleRect(tester, 'Hello there');
    final typing = typingBubbleRect(tester);
    expect(typing.left, incoming.left);
    // Two 1dp paddings, as between two bubbles of one sender's run.
    expect(typing.top - incoming.bottom, 2);
  });

  testWidgets('a group keeps the avatar, 8dp from the bubble', (tester) async {
    final room = client.rooms.firstWhere(
      (room) => !room.isSpace && !room.isDirectChat,
    );
    setTyping(room, ['@alice:example.org']);
    addTearDown(() => room.ephemerals.remove('m.typing'));

    await pump(
      tester,
      room: room,
      sender: '@alice:example.org',
      typing: TypingIndicatorRow(
        rooms: [room],
        oneToOne: false,
        newestFromOwn: false,
      ),
    );

    final avatar = tester.getRect(
      find
          .descendant(
            of: find.byType(TypingIndicatorRow),
            matching: find.byType(Avatar),
          )
          .first,
    );
    expect(typingBubbleRect(tester).left, avatar.right + 8);
  });

  testWidgets('a group lines the avatar and bubble up with the messages', (
    tester,
  ) async {
    final room = client.rooms.firstWhere(
      (room) => !room.isSpace && !room.isDirectChat,
    );
    setTyping(room, ['@alice:example.org']);
    addTearDown(() => room.ephemerals.remove('m.typing'));

    await pump(
      tester,
      room: room,
      sender: '@alice:example.org',
      typing: TypingIndicatorRow(
        rooms: [room],
        oneToOne: false,
        newestFromOwn: false,
      ),
    );

    Rect avatarIn(Type row) => tester.getRect(
      find
          .descendant(of: find.byType(row), matching: find.byType(Avatar))
          .first,
    );
    final messageAvatar = avatarIn(Message);
    final typingAvatar = avatarIn(TypingIndicatorRow);
    expect(typingAvatar.left, moreOrLessEquals(messageAvatar.left, epsilon: 1));
    expect(
      typingAvatar.width,
      moreOrLessEquals(messageAvatar.width, epsilon: 1),
    );
    expect(
      typingBubbleRect(tester).left,
      moreOrLessEquals(bubbleRect(tester, 'Hello there').left, epsilon: 1),
    );
  });

  testWidgets('a merged group continuing the sender\'s run lines the dots up '
      'with the bubbles, under the avatar that stays', (tester) async {
    // A merged contact can be one group on two networks.
    final groups = client.rooms
        .where((room) => !room.isSpace && !room.isDirectChat)
        .take(2)
        .toList();
    final room = groups.first;
    setTyping(room, ['@alice:example.org']);
    addTearDown(() => room.ephemerals.remove('m.typing'));

    await pump(
      tester,
      room: room,
      sender: '@alice:example.org',
      typing: TypingIndicatorRow(
        rooms: groups,
        oneToOne: TypingIndicatorRow.oneToOneFor(groups),
        newestFromOwn: false,
        newestSenderId: '@alice:example.org',
      ),
    );

    // The dots start where the run's bubbles do, past the avatar's column.
    expect(
      typingBubbleRect(tester).left,
      moreOrLessEquals(bubbleRect(tester, 'Hello there').left, epsilon: 1),
    );
    expect(
      find.descendant(
        of: find.byType(TypingIndicatorRow),
        matching: find.byType(Avatar),
      ),
      findsNothing,
    );
  });

  test('only direct chats read as one-to-one', () {
    final direct = client.rooms.where((room) => room.isDirectChat).toList();
    final groups = client.rooms
        .where((room) => !room.isSpace && !room.isDirectChat)
        .toList();
    expect(TypingIndicatorRow.oneToOneFor(groups.take(2).toList()), isFalse);
    if (direct.isNotEmpty) {
      expect(TypingIndicatorRow.oneToOneFor([direct.first]), isTrue);
    }
  });

  Finder typingAvatars() => find.descendant(
    of: find.byType(TypingIndicatorRow),
    matching: find.byType(Avatar),
  );

  Finder messageAvatars() =>
      find.descendant(of: find.byType(Message), matching: find.byType(Avatar));

  Room groupRoom() =>
      client.rooms.firstWhere((room) => !room.isSpace && !room.isDirectChat);

  Future<void> typeIn(
    WidgetTester tester,
    Room room,
    List<String> typers,
  ) async {
    // Typers missing from the room's state are looked up in the database,
    // whose lock warning timer outlives the test's fake clock.
    for (final typer in typers) {
      if (room.getState(EventTypes.RoomMember, typer) != null) continue;
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          stateKey: typer,
          senderId: typer,
          content: {'membership': 'join'},
        ),
      );
    }
    setTyping(room, typers);
    addTearDown(() => room.ephemerals.remove('m.typing'));
    await pump(
      tester,
      room: room,
      sender: '@alice:example.org',
      typing: TypingIndicatorRow(
        rooms: [room],
        oneToOne: false,
        newestFromOwn: false,
        newestSenderId: '@alice:example.org',
      ),
    );
  }

  testWidgets('the sender typing continues their run: the dots at the bubble '
      'column 2dp under it, their avatar staying on the message', (
    tester,
  ) async {
    await typeIn(tester, groupRoom(), ['@alice:example.org']);

    expect(messageAvatars(), findsOneWidget);
    expect(typingAvatars(), findsNothing);
    final message = bubbleRect(tester, 'Hello there');
    final dots = typingBubbleRect(tester);
    expect(dots.left, moreOrLessEquals(message.left, epsilon: 1));
    // 1dp under the bubble and 1dp above the next, as inside a run.
    expect(dots.top - message.bottom, 2);
  });

  testWidgets('someone else typing gets their own avatar, at the gap a new '
      'sender\'s message gets', (tester) async {
    await typeIn(tester, groupRoom(), ['@bob:example.org']);

    expect(messageAvatars(), findsOneWidget);
    expect(typingAvatars(), findsOneWidget);
    // A message row pads 8dp above and below where the sender changes.
    expect(
      typingBubbleRect(tester).top - bubbleRect(tester, 'Hello there').bottom,
      16,
    );
  });

  testWidgets('three typing share the avatar\'s square, three small '
      'avatars', (tester) async {
    await typeIn(tester, groupRoom(), [
      '@bob:example.org',
      '@carol:example.org',
      '@dave:example.org',
    ]);

    expect(typingAvatars(), findsNWidgets(3));
    final slot = tester.getRect(find.byKey(const ValueKey('typing-avatars')));
    expect(slot.size, const Size.square(Message.senderAvatarSize));
    for (final element in typingAvatars().evaluate()) {
      final rect = tester.getRect(find.byWidget(element.widget));
      expect(slot.contains(rect.topLeft), isTrue);
      expect(rect.right, lessThanOrEqualTo(slot.right));
      expect(rect.bottom, lessThanOrEqualTo(slot.bottom));
    }
    expect(
      typingBubbleRect(tester).left - slot.right,
      8,
      reason: 'the dots keep to the bubble column',
    );
  });

  testWidgets('five typing show two avatars and a +3', (tester) async {
    await typeIn(tester, groupRoom(), [
      '@bob:example.org',
      '@carol:example.org',
      '@dave:example.org',
      '@erin:example.org',
      '@frank:example.org',
    ]);

    expect(typingAvatars(), findsNWidgets(2));
    expect(find.text('+3'), findsOneWidget);
    final slot = tester.getRect(find.byKey(const ValueKey('typing-avatars')));
    expect(slot.size, const Size.square(Message.senderAvatarSize));
    final counter = tester.getRect(find.byKey(const ValueKey('typing-more')));
    expect(counter.right, lessThanOrEqualTo(slot.right));
    expect(counter.bottom, lessThanOrEqualTo(slot.bottom));
  });

  testWidgets('the dots go when the typing stops', (tester) async {
    final room = groupRoom();
    await typeIn(tester, room, ['@alice:example.org']);

    setTyping(room, []);
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'stopped',
        rooms: RoomsUpdate(
          join: {
            room.id: JoinedRoomUpdate(
              ephemeral: [
                BasicEvent(type: 'm.typing', content: {'user_ids': []}),
              ],
            ),
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(TypingAnimation), findsNothing);
    expect(messageAvatars(), findsOneWidget);
  });

  testWidgets('a merged contact typing in a room not sent to still shows', (
    tester,
  ) async {
    final dm = client.getRoomById('!726s6s6q:example.com')!;
    final sendVia = Room(id: '!sendvia:example.com', client: client);
    final elsewhere = Room(id: '!elsewhere:example.com', client: client);
    setTyping(elsewhere, ['@bob_imessage:example.com']);

    await pump(
      tester,
      room: dm,
      sender: '@bob:example.com',
      typing: TypingIndicatorRow(
        rooms: [sendVia, elsewhere],
        oneToOne: true,
        newestFromOwn: false,
      ),
    );

    expect(find.byType(TypingAnimation), findsOneWidget);
    expect(
      tester.getSize(find.byType(TypingIndicatorRow)).height,
      greaterThan(0),
    );
  });

  testWidgets('nobody typing leaves no space', (tester) async {
    final room = client.getRoomById('!726s6s6q:example.com')!;
    room.ephemerals.remove('m.typing');
    await pump(
      tester,
      room: room,
      sender: '@bob:example.com',
      typing: TypingIndicatorRow(
        rooms: [room],
        oneToOne: true,
        newestFromOwn: false,
      ),
    );
    expect(find.byType(TypingAnimation), findsNothing);
    expect(tester.getSize(find.byType(TypingIndicatorRow)).height, 0);
  });
}
