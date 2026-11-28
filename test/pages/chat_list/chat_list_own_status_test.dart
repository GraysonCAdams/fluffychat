// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/status_mark.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/own_message_status.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_list_fakes.dart';

const _me = '@me:x';
const _bot = '@gmessagesbot:x';
// Now, as the SDK marks a message still sending after a minute as failed.
final _sentAt = DateTime.now();

void main() {
  late FakeChatListClient client;
  var rooms = 0;

  setUp(() async {
    client = await setUpFakeChatList('own status test');
  });

  tearDown(() => tearDownFakeChatList(client));

  void member(Room room, String id) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': id},
      senderId: id,
      stateKey: id,
    ),
  );

  /// A chat whose newest message is "On my way" from [sender]: a direct
  /// chat with Khai, or a group with [others] in it. Its bridge bot is in
  /// it too when [bridged] is set.
  Room chat({
    String sender = _me,
    EventStatus status = EventStatus.synced,
    List<String> others = const ['@khai:x'],
    bool bridged = false,
  }) {
    final id = '!r${rooms++}:x';
    final room = others.length == 1
        ? addFakeChat(client, id, 'Khai Atwi', partner: others.single)
        : addFakeChat(client, id, 'Squad');
    for (final user in [_me, ...others, if (bridged) _bot]) {
      member(room, user);
    }
    if (bridged) {
      room.setState(
        StrippedStateEvent(
          type: 'm.bridge',
          content: {
            'bridgebot': _bot,
            'protocol': {'id': 'gmessages', 'displayname': 'Google Messages'},
          },
          senderId: _bot,
          stateKey: 'gm/$id',
        ),
      );
    }
    room.summary.mJoinedMemberCount = 1 + others.length + (bridged ? 1 : 0);
    room.lastEvent = Event(
      content: {'msgtype': MessageTypes.Text, 'body': 'On my way'},
      type: EventTypes.Message,
      eventId: '\$$id-last',
      senderId: sender,
      originServerTs: _sentAt,
      room: room,
      status: status,
    );
    return room;
  }

  /// [user] has read up to [eventId] (the newest message when null) at
  /// [at].
  void read(Room room, String user, {String? eventId, DateTime? at}) =>
      room.receiptState.global.otherUsers[user] = LatestReceiptStateData(
        eventId ?? room.lastEvent!.eventId,
        (at ?? _sentAt.add(const Duration(minutes: 1))).millisecondsSinceEpoch,
      );

  Future<void> show(WidgetTester tester, Room room) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ListView(children: [ChatListItem(room, onTap: () {})]),
          ),
        ),
      ),
    );
    // A message still sending animates, so the tree never settles.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
  }

  /// The row's semantics, which merge into one label, include [label] as a
  /// line of their own.
  Finder spoken(String label) =>
      find.bySemanticsLabel(RegExp('(^|\\n)${RegExp.escape(label)}(\\n|\$)'));

  /// The state the row's status mark shows, or null without one.
  StatusMarkState? markState(WidgetTester tester) {
    final marks = find.byType(StatusMark);
    if (marks.evaluate().isEmpty) return null;
    return tester.widget<StatusMark>(marks).state;
  }

  testWidgets('a message on its way shows a clock', (tester) async {
    final semantics = tester.ensureSemantics();
    await show(tester, chat(status: EventStatus.sending));
    expect(markState(tester), StatusMarkState.sending);
    // The clock takes the place of a spinner.
    expect(
      tester.widget<StatusMark>(find.byType(StatusMark)).sending,
      StatusMarkSending.clock,
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(spoken('Sending'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a sent message nobody has read shows one outlined check', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await show(tester, chat());
    expect(markState(tester), StatusMarkState.sent);
    expect(spoken('Sent'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a message the other side read shows two filled checks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final room = chat(bridged: true);
    read(room, '@khai:x');
    await show(tester, room);
    expect(markState(tester), StatusMarkState.read);
    expect(spoken('Read'), findsOneWidget);
    // Read is told by shape, in the preview text's own colour.
    final mark = tester.widget<StatusMark>(find.byType(StatusMark));
    expect(
      mark.color,
      isNot(
        Theme.of(tester.element(find.byType(StatusMark))).colorScheme.primary,
      ),
    );
    expect(
      mark.color,
      DefaultTextStyle.of(
        tester.element(find.byType(OwnMessageStatusIcon)),
      ).style.color,
    );
    semantics.dispose();
  });

  testWidgets('the bridge bot reading it does not count', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = chat(bridged: true);
    read(room, _bot);
    await show(tester, room);
    expect(spoken('Sent'), findsOneWidget);
    expect(markState(tester), StatusMarkState.sent);
    semantics.dispose();
  });

  testWidgets('a receipt on an earlier message is not a read', (tester) async {
    final semantics = tester.ensureSemantics();
    final room = chat();
    read(
      room,
      '@khai:x',
      eventId: r'$earlier',
      at: _sentAt.subtract(const Duration(minutes: 5)),
    );
    await show(tester, room);
    expect(spoken('Sent'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a group some have read shows two outlined checks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final room = chat(others: ['@a:x', '@b:x', '@c:x'], bridged: true);
    read(room, '@a:x');
    read(room, '@b:x');
    await show(tester, room);
    expect(markState(tester), StatusMarkState.readBySome);
    expect(spoken('Read by 2 of 3'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a group everyone has read shows two filled checks', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final room = chat(others: ['@a:x', '@b:x', '@c:x']);
    for (final user in ['@a:x', '@b:x', '@c:x']) {
      read(room, user);
    }
    await show(tester, room);
    expect(markState(tester), StatusMarkState.read);
    expect(spoken('Read'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('a message that failed shows the error icon in red', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    await show(tester, chat(status: EventStatus.error));
    final icon = tester.widget<Icon>(find.byIcon(Icons.error_outline));
    expect(
      icon.color,
      Theme.of(
        tester.element(find.byIcon(Icons.error_outline)),
      ).colorScheme.error,
    );
    expect(spoken('Failed to send'), findsOneWidget);
    semantics.dispose();
  });

  testWidgets('someone else\'s message shows no status', (tester) async {
    await show(tester, chat(sender: '@khai:x'));
    expect(find.byType(StatusMark), findsNothing);
  });

  testWidgets('a read receipt that arrives turns the check filled', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    final room = chat();
    await show(tester, room);
    expect(spoken('Sent'), findsOneWidget);

    // As the SDK does for a receipt in a sync: it updates the room's
    // receipt state, then reports the sync.
    read(room, '@khai:x');
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'next',
        rooms: RoomsUpdate(
          join: {
            room.id: JoinedRoomUpdate(
              ephemeral: [BasicEvent(type: 'm.receipt', content: {})],
            ),
          },
        ),
      ),
    );
    await tester.pump();
    expect(spoken('Read'), findsOneWidget);
    expect(markState(tester), StatusMarkState.read);
    // Lets the timers the sync started run out.
    await tester.pump(const Duration(seconds: 2));
    semantics.dispose();
  });
}
