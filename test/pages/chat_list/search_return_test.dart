// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_filter_menu.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/pages/chat_list/search_scope.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list_fakes.dart';

/// The phone's search field stays at the top while results scroll, and a
/// chat opened from the results comes back to the normal chat list.
void main() {
  late FakeChatListClient client;

  /// The status bar's height.
  const statusBar = 48.0;

  setUp(() async {
    client = await setUpFakeChatList('search return test');
    for (var i = 0; i < 60; i++) {
      addFakeChat(
        client,
        '!c$i:x',
        'Chat $i',
        lastMessageTime: DateTime(2026, 1, 1).subtract(Duration(hours: i)),
      );
    }
  });

  tearDown(() => tearDownFakeChatList(client));

  final pill = find.byKey(const ValueKey('chat_list_search_pill'));

  ChatListController list(WidgetTester tester) =>
      tester.state<ChatListController>(find.byType(ChatList));

  Future<void> pumpList(WidgetTester tester, {double width = 400}) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    tester.view.padding = const FakeViewPadding(top: statusBar);
    addTearDown(tester.view.reset);
    await pumpFakeChatList(tester, client);
  }

  /// Opens the phone's search, types [text] and scrolls the results [by]
  /// down.
  Future<void> searchAndScroll(
    WidgetTester tester,
    String text, {
    double by = 0,
  }) async {
    await tester.tap(
      find.descendant(
        of: find.byType(ChatListHeader),
        matching: find.byTooltip('Search'),
      ),
    );
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    if (by > 0) {
      await tester.drag(find.byType(CustomScrollView), Offset(0, -by));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('while searching the field stays under the status bar, on '
      'an opaque bar that covers it', (tester) async {
    await pumpList(tester);
    await searchAndScroll(tester, 'chat', by: 2000);
    expect(list(tester).scrollController.offset, greaterThan(1500));

    // The bar is 72 high below the status bar, the field 48 high in it.
    final field = tester.getRect(pill);
    expect(field.top, statusBar + (72 - 48) / 2);
    expect(pill.hitTestable(), findsOneWidget);
    final bar = find
        .descendant(
          of: find.byType(ChatListHeader),
          matching: find.byType(Material),
        )
        .first;
    expect(tester.getRect(bar).top, 0);
    expect(tester.getRect(bar).bottom, statusBar + 72);
    final colors = Theme.of(tester.element(bar)).colorScheme;
    final color = tester.widget<Material>(bar).color!;
    expect(color, colors.surfaceContainer);
    expect(color.a, 1.0);

    await finishFakeChatList(tester, client);
  });

  testWidgets('back from a chat opened in the results lands on the normal '
      'list at that chat, with search closed', (tester) async {
    await pumpList(tester);
    await searchAndScroll(tester, 'chat', by: 2000);
    final row = find.text('Chat 40');
    await tester.scrollUntilVisible(
      row,
      200,
      scrollable: find
          .descendant(
            of: find.byType(CustomScrollView),
            matching: find.byType(Scrollable),
          )
          .first,
    );
    await tester.pumpAndSettle();
    await tester.tap(row);
    await tester.pumpAndSettle();
    expect(find.text('opened !c40:x'), findsOneWidget);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    final controller = list(tester);
    expect(controller.isSearchMode, isFalse);
    expect(controller.searchController.text, isEmpty);
    expect(controller.searchScope, SearchScope.all);
    expect(find.byType(TextField), findsNothing);
    expect(find.byIcon(Icons.close_outlined), findsNothing);
    expect(
      find.byType(ClientChooserButton, skipOffstage: false),
      findsOneWidget,
    );
    expect(controller.searchFocusNode.hasFocus, isFalse);
    expect(tester.testTextInput.isVisible, isFalse);
    // The header floats as on any scrolled list: away with the list, or
    // whole below the status bar, never under it.
    final title = tester.getRect(
      find.byType(ChatFilterButton, skipOffstage: false),
    );
    expect(title.bottom <= 0 || title.top >= statusBar, isTrue);
    // The chat sits on screen where it is in the list, below the header.
    expect(row.hitTestable(), findsOneWidget);
    final rowRect = tester.getRect(row);
    expect(rowRect.top, greaterThan(statusBar + 72));
    expect(rowRect.bottom, lessThan(800));
    expect(controller.scrollController.offset, greaterThan(0));

    await finishFakeChatList(tester, client);
  });

  testWidgets('beside the chat, in a wide window, search stays open', (
    tester,
  ) async {
    await pumpList(tester, width: 1200);
    await tester.enterText(find.byType(TextField), 'chat 4');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Chat 4'));
    await tester.pumpAndSettle();
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(list(tester).isSearchMode, isTrue);
    expect(list(tester).searchController.text, 'chat 4');

    await finishFakeChatList(tester, client);
  });
}
