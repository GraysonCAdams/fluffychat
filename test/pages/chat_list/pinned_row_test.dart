// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:flutter_test/flutter_test.dart';

import 'chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;
  late Map<String, FakeChatListRoom> rooms;

  /// A one-to-one chat named [name] whose newest message is [day] days
  /// into 2026, so a higher [day] lists first.
  FakeChatListRoom chat(String name, int day, {int unread = 0}) {
    final id = '!${name.toLowerCase()}:x';
    return rooms[id] = addFakeChat(
      client,
      id,
      name,
      partner: '@${name.toLowerCase()}:x',
      notificationCount: unread,
      lastMessageTime: DateTime(2026, 1, day),
    );
  }

  setUp(() async {
    client = await setUpFakeChatList('pinned row test');
    rooms = {};
  });

  tearDown(() => tearDownFakeChatList(client));

  /// The avatars of the pinned row, which are larger than the list's.
  Finder pinnedAvatars() => find.byWidgetPredicate(
    (widget) => widget is SelectableAvatar && widget.size == 76,
  );

  testWidgets('the first pinned avatar lines up with the list avatars', (
    tester,
  ) async {
    chat('Ada', 3).pin();
    chat('Bea', 2);
    await pumpFakeChatList(tester, client);

    final listAvatar = find.descendant(
      of: find.byType(ChatListItem),
      matching: find.byType(SelectableAvatar),
    );
    expect(pinnedAvatars(), findsOneWidget);
    expect(listAvatar, findsOneWidget);
    expect(tester.getTopLeft(listAvatar).dx, 16);
    expect(
      tester.getTopLeft(pinnedAvatars()).dx,
      tester.getTopLeft(listAvatar).dx,
    );
    await finishFakeChatList(tester, client);
  });
}
