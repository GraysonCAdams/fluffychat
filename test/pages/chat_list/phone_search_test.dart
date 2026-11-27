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

  testWidgets('the field keeps its focus and keyboard while it opens', (
    tester,
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
    // Partway through the opening animation, the title and the field are
    // both on screen.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final list = tester.state<ChatListController>(find.byType(ChatList));
    final opening = tester.state<EditableTextState>(find.byType(EditableText));
    expect(list.searchFocusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await tester.pumpAndSettle();
    // The same field, still focused, with the keyboard still up.
    expect(list.searchFocusNode.hasFocus, isTrue);
    expect(FocusManager.instance.primaryFocus, same(list.searchFocusNode));
    expect(
      tester.testTextInput.log.map((call) => call.method),
      isNot(contains('TextInput.hide')),
    );
    expect(tester.testTextInput.isVisible, isTrue);
    expect(
      tester.state<EditableTextState>(find.byType(EditableText)),
      same(opening),
    );

    await finishFakeChatList(tester, client);
  });

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
    // With nothing typed the recent people show again, in place of the
    // chats.
    expect(find.text('Recent'), findsOneWidget);
    expect(find.text('Harrison'), findsOneWidget);
    expect(find.text('Squad Goals'), findsNothing);

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
