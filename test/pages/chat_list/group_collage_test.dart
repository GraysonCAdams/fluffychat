// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/render_pixels.dart';
import 'chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('group collage test');
  });

  tearDown(() => tearDownFakeChatList(client));

  /// Adds the joined members [names] to [room], with user IDs made from
  /// their first names.
  void addMembers(Room room, List<String> names) {
    for (final name in names) {
      final id = '@${name.split(' ').first.toLowerCase()}:x';
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          content: {'membership': 'join', 'displayname': name},
          senderId: id,
          stateKey: id,
        ),
      );
    }
  }

  /// The faces in the list row of the chat named [name].
  List<Avatar> faces(WidgetTester tester, String name) => tester
      .widgetList<Avatar>(
        find.descendant(
          of: find.descendant(
            of: find.widgetWithText(ChatListItem, name),
            matching: find.byType(GroupAvatar),
          ),
          matching: find.byType(Avatar),
        ),
      )
      .toList();

  testWidgets('a group of three shows the two others overlapping', (
    tester,
  ) async {
    final room = addFakeChat(client, '!trio:x', 'Trio');
    addMembers(room, ['Drew Andersen']);
    // The user is a member too, and is left out of the collage.
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'displayname': 'Me'},
        senderId: client.userID!,
        stateKey: client.userID,
      ),
    );
    await pumpFakeChatList(tester, client);

    final shown = faces(tester, 'Trio');
    expect(shown.map((a) => a.name), ['Trio', 'Drew Andersen']);
    // Two thirds of the row's avatar less a 2dp gap all round, the second
    // down and to the right.
    expect(shown.first.size, closeTo(Avatar.defaultSize * 2 / 3 - 4, 0.01));
    final first = tester.getTopLeft(find.byWidget(shown[0]));
    final second = tester.getTopLeft(find.byWidget(shown[1]));
    expect(second.dx - first.dx, closeTo(Avatar.defaultSize / 3, 0.01));
    expect(second.dy - first.dy, closeTo(Avatar.defaultSize / 3, 0.01));

    await finishFakeChatList(tester, client);
  });

  testWidgets('the gap between two faces shows what lies behind them', (
    tester,
  ) async {
    final room = addFakeChat(client, '!duo:x', 'Duo');
    addMembers(room, ['Drew Andersen']);
    // A hovered or highlighted row: lighter than the surface.
    const behind = Color(0xFF2A2A2A);
    final (pixels, width) = await renderPixels(
      tester,
      GroupAvatar(room: room, name: 'Duo'),
      background: behind,
      size: const Size.square(Avatar.defaultSize),
    );
    // The faces' centres are a third and two thirds of the way across. The
    // second is cut 2dp wide out of the first: halfway across that gap, on
    // the line between the centres, lies 15dp from the second centre.
    const third = Avatar.defaultSize / 3;
    const along = 15 / 1.4142135;
    for (final offset in [0.0, 0.5]) {
      final x = ((2 * third - along + offset) * 2).floor();
      final i = (x * width + x) * 4;
      expect(
        [pixels[i], pixels[i + 1], pixels[i + 2]],
        [0x2A, 0x2A, 0x2A],
        reason: 'pixel ($x, $x)',
      );
    }
  });

  testWidgets('a larger group shows three members in a cluster', (
    tester,
  ) async {
    final room = addFakeChat(client, '!family:x', 'Family');
    addMembers(room, ['Pat Doe', 'Alex Doe', 'Sam Doe']);
    await pumpFakeChatList(tester, client);

    final shown = faces(tester, 'Family');
    expect(shown, hasLength(3));
    // The newest message's sender comes first, on top.
    expect(shown.first.name, 'Family');
    final top = tester.getTopLeft(find.byWidget(shown[0]));
    final left = tester.getTopLeft(find.byWidget(shown[1]));
    final right = tester.getTopLeft(find.byWidget(shown[2]));
    expect(left.dy, greaterThan(top.dy));
    expect(right.dy, left.dy);
    expect(left.dx, lessThan(top.dx));
    expect(right.dx, greaterThan(top.dx));

    await finishFakeChatList(tester, client);
  });

  /// A Google Messages group as Synapse and the bridge leave it: named by
  /// the bridge, so the sync carries no heroes; loaded partial, so no
  /// members are in memory; and the newest message is the user's own. The
  /// members are the user, the bridge bot and two ghosts. Each test takes
  /// its own [id], as the in-memory database outlives a test.
  FakeChatListRoom addBridgedGroup(String id) {
    const name = 'Drew Andersen, Harrison Young';
    final room = addFakeChat(client, id, name);
    room.states[EventTypes.RoomMember]?.clear();
    addFakeBridge(room, bot: '@gmessagesbot:x', network: 'Google Messages');
    room.summary
      ..mHeroes = null
      ..mJoinedMemberCount = 4
      ..mInvitedMemberCount = 0;
    room.lastEvent = Event(
      content: {'msgtype': 'm.text', 'body': 'see you there'},
      type: EventTypes.Message,
      eventId: '\$$id-last',
      senderId: client.userID!,
      originServerTs: DateTime(2026),
      room: room,
    );
    return room;
  }

  /// The joined members of the bridged group, as the server lists them.
  List<MatrixEvent> bridgedMembers() => [
    for (final (id, name) in [
      ('@me:x', 'Me'),
      ('@gmessagesbot:x', 'Google Messages bridge bot'),
      ('@gmessages_4.46:x', 'Drew Andersen'),
      ('@gmessages_4.19:x', 'Harrison Young'),
    ])
      MatrixEvent(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'displayname': name},
        senderId: id,
        stateKey: id,
        eventId: '\$member-$id',
        originServerTs: DateTime(2026),
      ),
  ];

  /// Lets the database and the fake server answer, then draws the result.
  /// Loading takes several database calls in turn, each finishing in real
  /// time and continuing on a pump.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    await tester.pumpAndSettle();
  }

  testWidgets('a bridged group shows the members kept in the database', (
    tester,
  ) async {
    final room = addBridgedGroup('!gm-database:x');
    await tester.runAsync(() async {
      for (final member in bridgedMembers()) {
        await client.database.storeEventUpdate(
          room.id,
          Event.fromMatrixEvent(member, room),
          EventUpdateType.state,
          client,
        );
      }
    });
    await pumpFakeChatList(tester, client);
    await settle(tester);

    final shown = faces(tester, 'Drew Andersen, Harrison Young');
    expect(shown.map((a) => a.name).toSet(), {
      'Drew Andersen',
      'Harrison Young',
    });
    // The database had the whole list, so the server was not asked.
    expect(client.memberRequests, isEmpty);

    await finishFakeChatList(tester, client);
  });

  testWidgets('a bridged group asks the server once for members it lacks', (
    tester,
  ) async {
    final room = addBridgedGroup('!gm-server:x');
    client.serverMembers[room.id] = bridgedMembers();
    await pumpFakeChatList(tester, client);
    await settle(tester);

    final shown = faces(tester, 'Drew Andersen, Harrison Young');
    expect(shown.map((a) => a.name).toSet(), {
      'Drew Andersen',
      'Harrison Young',
    });
    expect(client.memberRequests, [room.id]);

    // The list is kept, so the list built again asks nothing more.
    await finishFakeChatList(tester, client);
    await pumpFakeChatList(tester, client);
    await settle(tester);
    expect(faces(tester, 'Drew Andersen, Harrison Young'), hasLength(2));
    expect(client.memberRequests, [room.id]);

    await finishFakeChatList(tester, client);
  });

  testWidgets('a group with a picture and a direct chat show one avatar', (
    tester,
  ) async {
    final room = addFakeChat(client, '!squad:x', 'Squad Goals');
    addMembers(room, ['Pat Doe', 'Alex Doe']);
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomAvatar,
        content: {'url': 'mxc://x/squad'},
        senderId: '@pat:x',
        stateKey: '',
      ),
    );
    addFakeChat(client, '!anne:x', 'Anne Chodzko', partner: '@anne:x');
    await pumpFakeChatList(tester, client);

    expect(find.byType(GroupAvatar), findsNothing);
    final squad = tester.widget<Avatar>(
      find.descendant(
        of: find.widgetWithText(ChatListItem, 'Squad Goals'),
        matching: find.byType(Avatar),
      ),
    );
    expect(squad.mxContent, Uri.parse('mxc://x/squad'));
    expect(
      find.descendant(
        of: find.widgetWithText(ChatListItem, 'Anne Chodzko'),
        matching: find.byType(Avatar),
      ),
      findsOneWidget,
    );

    await finishFakeChatList(tester, client);
  });
}
