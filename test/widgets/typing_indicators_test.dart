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
                  scrollController: scrollController,
                  colors: const [Colors.blue, Colors.blue],
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
    expect(typingAvatar.width, moreOrLessEquals(messageAvatar.width, epsilon: 1));
    expect(
      typingBubbleRect(tester).left,
      moreOrLessEquals(bubbleRect(tester, 'Hello there').left, epsilon: 1),
    );
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
