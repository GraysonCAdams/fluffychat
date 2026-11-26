// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('phone search test');
    addFakeChat(client, '!grp:x', 'Squad Goals');
    addFakeChat(
      client,
      '!dm:x',
      'Harrison Young',
      partner: '@harrison:x',
      lastMessageTime: DateTime(2025),
    );
  });

  tearDown(() => tearDownFakeChatList(client));

  /// The chat list on a phone, with search opened and [text] typed.
  Future<ChatListController> openSearch(
    WidgetTester tester,
    String text,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await pumpFakeChatList(tester, client);
    await tester.tap(
      find.descendant(
        of: find.byType(ChatListHeader),
        matching: find.byTooltip('Search'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
    final list = tester.state<ChatListController>(find.byType(ChatList));
    expect(list.isSearchMode, isTrue);
    expect(find.text('Harrison Young'), findsNothing);
    return list;
  }

  testWidgets('clearing the text keeps the field open and focused', (
    tester,
  ) async {
    final list = await openSearch(tester, 'squad');

    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();
    expect(list.isSearchMode, isTrue);
    expect(list.searchFocusNode.hasFocus, isTrue);
    expect(find.byType(TextField), findsOneWidget);
    expect(find.byTooltip('Cancel'), findsOneWidget);
    // With nothing typed every chat is listed again.
    expect(find.text('Harrison Young'), findsOneWidget);
    expect(find.text('Squad Goals'), findsOneWidget);

    await finishFakeChatList(tester, client);
  });

  testWidgets('the close button ends the search', (tester) async {
    final list = await openSearch(tester, 'squad');
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(list.isSearchMode, isFalse);
    expect(list.searchFocusNode.hasFocus, isFalse);
    expect(find.text('Harrison Young'), findsOneWidget);

    await finishFakeChatList(tester, client);
  });

  testWidgets('back ends the search', (tester) async {
    final list = await openSearch(tester, 'squad');
    await tester.enterText(find.byType(TextField), '');
    await tester.pumpAndSettle();

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(list.isSearchMode, isFalse);
    expect(list.searchController.text, isEmpty);

    await finishFakeChatList(tester, client);
  });
}
