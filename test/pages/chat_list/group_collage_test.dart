// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

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
    // Two thirds of the row's avatar, the second down and to the right.
    expect(shown.first.size, closeTo(Avatar.defaultSize * 2 / 3, 0.01));
    final first = tester.getTopLeft(find.byWidget(shown[0]));
    final second = tester.getTopLeft(find.byWidget(shown[1]));
    expect(second.dx - first.dx, closeTo(Avatar.defaultSize / 3, 0.01));
    expect(second.dy - first.dy, closeTo(Avatar.defaultSize / 3, 0.01));

    await finishFakeChatList(tester, client);
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
