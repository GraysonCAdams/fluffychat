// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/scroll_to_top_button.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/pages/chat_list/start_chat_fab.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'chat_list_fakes.dart';

/// A fake client whose server answers searches from fixed results, and
/// counts them.
class _DirectoryClient extends FakeChatListClient {
  _DirectoryClient(super.clientName, {required super.database});

  int directorySearches = 0;
  int roomSearches = 0;

  @override
  Future<SearchUserDirectoryResponse> searchUserDirectory(
    String searchTerm, {
    int? limit,
  }) async {
    directorySearches++;
    return SearchUserDirectoryResponse(
      limited: false,
      results: [Profile(userId: '@zoe:matrix.org', displayName: 'Zoe Moss')],
    );
  }

  @override
  Future<QueryPublicRoomsResponse> queryPublicRooms({
    String? server,
    PublicRoomQueryFilter? filter,
    bool? includeAllNetworks,
    int? limit,
    String? since,
    String? thirdPartyInstanceId,
  }) async {
    roomSearches++;
    return QueryPublicRoomsResponse(chunk: []);
  }
}

void main() {
  late _DirectoryClient client;

  setUp(() async {
    client = await setUpFakeChatList(
      'chat list polish test',
      create: (name, database) => _DirectoryClient(name, database: database),
    );
    client.homeserver = Uri.parse('https://x');
  });

  tearDown(() => tearDownFakeChatList(client));

  /// A phone 400 by 800, which shows the floating header.
  void phone(WidgetTester tester) {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
  }

  /// Forty chats, newest first; the oldest five are unread, so the unread
  /// chip shows while the top of the list is in view.
  void addChats() {
    for (var i = 0; i < 40; i++) {
      addFakeChat(
        client,
        '!c$i:x',
        'Chat $i',
        notificationCount: i >= 35 ? 1 : 0,
        lastMessageTime: DateTime(2026, 1, 1).subtract(Duration(hours: i)),
      );
    }
  }

  ChatListController list(WidgetTester tester) =>
      tester.state<ChatListController>(find.byType(ChatList));

  double buttonHeight(WidgetTester tester) =>
      tester.getSize(find.byType(ScrollToTopButton)).height;

  group('back to top', () {
    testWidgets('shows once scrolled down a screen and goes back up', (
      tester,
    ) async {
      phone(tester);
      addChats();
      await pumpFakeChatList(tester, client);
      final scroll = list(tester).scrollController;

      // At the top there is nothing to go back up to.
      expect(buttonHeight(tester), 0);

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(0));
      expect(buttonHeight(tester), 0, reason: 'less than a screen down');

      await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
      await tester.pumpAndSettle();
      expect(scroll.offset, greaterThan(800));
      expect(buttonHeight(tester), greaterThan(40));

      // Near the top and clear of New chat and the unread chip below.
      final button = tester.getRect(find.byType(ScrollToTopButton));
      expect(
        find.descendant(
          of: find.byType(ScrollToTopButton),
          matching: find.byIcon(Icons.arrow_upward),
        ),
        findsOneWidget,
      );
      final arrow = tester.getRect(find.byIcon(Icons.arrow_upward));
      final fab = tester.getRect(find.byType(StartChatFab));
      expect(arrow.overlaps(fab), isFalse);
      expect(button.overlaps(fab), isFalse);
      final chip = find.byType(ActionChip);
      expect(chip, findsOneWidget);
      expect(arrow.overlaps(tester.getRect(chip)), isFalse);
      expect(arrow.top, lessThan(200));

      await tester.tap(find.byIcon(Icons.arrow_upward));
      await tester.pumpAndSettle();
      expect(scroll.offset, 0);
      expect(buttonHeight(tester), 0);

      await finishFakeChatList(tester, client);
    });
  });

  testWidgets('back to top follows the header as it floats in and out', (
    tester,
  ) async {
    phone(tester);
    // A status bar 24 high.
    tester.view.padding = const FakeViewPadding(top: 24);
    addChats();
    await pumpFakeChatList(tester, client);
    double buttonTop() => tester.getRect(find.byType(ScrollToTopButton)).top;

    // Far enough down for the header to float away: the button rises to 8
    // below the status bar (4 of it is the room for the button's shadow).
    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1300));
    await tester.pumpAndSettle();
    expect(buttonHeight(tester), greaterThan(40));
    expect(find.byType(AppBar).hitTestable(), findsNothing);
    expect(buttonTop(), 24 + 4);

    // Scrolling back up a little floats part of the header in, and the
    // button stays 8 below its bottom edge, frame by frame.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    var checked = 0;
    for (var i = 0; i < 15; i++) {
      await gesture.moveBy(const Offset(0, 5));
      await tester.pump(const Duration(milliseconds: 16));
      // The first move goes to the drag's slop, before the header moves.
      if (find.byType(AppBar).evaluate().isEmpty) continue;
      final barBottom = tester.getRect(find.byType(AppBar)).bottom;
      if (barBottom <= 24) continue;
      expect(buttonTop(), barBottom + 4);
      checked++;
    }
    expect(checked, greaterThan(5));
    // All the way in: 8 below the 72 high bar under the status bar.
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(tester.getRect(find.byType(AppBar)).bottom, 24 + 72);
    expect(buttonTop(), 24 + 72 + 4);

    await finishFakeChatList(tester, client);
  });

  testWidgets('the header that floats back in hides the rows below it', (
    tester,
  ) async {
    phone(tester);
    addChats();
    await pumpFakeChatList(tester, client);
    final header = find.byType(ChatListHeader);

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -1200));
    await tester.pumpAndSettle();
    expect(
      find.text('Chats').hitTestable(),
      findsNothing,
      reason: 'scrolled away',
    );

    // A short scroll back up, in small steps as a finger moves, brings the
    // header back over the list.
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(CustomScrollView)),
    );
    for (var i = 0; i < 15; i++) {
      await gesture.moveBy(const Offset(0, 10));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
    expect(list(tester).scrollController.offset, greaterThan(800));
    expect(tester.getRect(find.text('Chats')).top, greaterThanOrEqualTo(0));

    final bar = tester.widget<Material>(
      find.descendant(of: header, matching: find.byType(Material)).first,
    );
    final colors = Theme.of(tester.element(header)).colorScheme;
    expect(bar.color!.a, 1.0);
    expect(bar.color, colors.surfaceContainer);

    await finishFakeChatList(tester, client);
  });

  group('search', () {
    testWidgets('the field opens out of the search button', (tester) async {
      phone(tester);
      addChats();
      await pumpFakeChatList(tester, client);
      final reveal = find.byKey(const ValueKey('chat_list_search_reveal'));
      expect(reveal, findsNothing);

      await tester.tap(find.byTooltip('Search'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 60));
      final opening = tester.getSize(reveal).width;
      final fade = tester.widget<SliverFadeTransition>(
        find.byType(SliverFadeTransition),
      );
      expect(fade.opacity.value, inExclusiveRange(0, 1));

      await tester.pumpAndSettle();
      final open = tester.getSize(reveal).width;
      expect(opening, inExclusiveRange(0, open));
      expect(find.text('Chats'), findsOneWidget, reason: 'the section');
      expect(fade.opacity.value, 1);
      expect(
        tester.widget<TextField>(find.byType(TextField)).focusNode!.hasFocus,
        isTrue,
      );

      await finishFakeChatList(tester, client);
    });

    testWidgets('results are Material list rows under plain headings', (
      tester,
    ) async {
      phone(tester);
      addFakeChat(client, '!kim:x', 'Kim', partner: '@kim:matrix.org');
      await pumpFakeChatList(tester, client);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zo');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(find.text('Zoe Moss'), findsOneWidget);
      final body = find.byType(CustomScrollView);
      expect(
        find.descendant(of: body, matching: find.byType(Divider)),
        findsNothing,
      );
      for (final title in tester.widgetList<SearchTitle>(
        find.byType(SearchTitle),
      )) {
        // No ruled container around a heading.
        expect(
          find.descendant(
            of: find.byWidget(title),
            matching: find.byType(Material),
          ),
          findsNothing,
        );
      }
      final heading = tester.widget<Text>(
        find.descendant(
          of: find.byType(SearchTitle).first,
          matching: find.byType(Text),
        ),
      );
      final theme = Theme.of(tester.element(body));
      expect(heading.style?.fontSize, theme.textTheme.titleSmall?.fontSize);
      final row = tester.widget<ListTile>(
        find.ancestor(
          of: find.text('Zoe Moss'),
          matching: find.byType(ListTile),
        ),
      );
      expect(row.contentPadding, const EdgeInsets.symmetric(horizontal: 16));

      await finishFakeChatList(tester, client);
    });

    testWidgets('messenger mode searches only chats and messages', (
      tester,
    ) async {
      phone(tester);
      final room = addFakeChat(client, '!a:x', 'Drew', partner: '@ghost:x');
      addFakeBridge(room);
      await pumpFakeChatList(tester, client);
      // One-to-one chats are named for the people in them.
      expect(find.widgetWithText(FilterChip, 'People'), findsOneWidget);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zo');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(client.directorySearches, 0);
      expect(client.roomSearches, 0);
      expect(find.text('People'), findsNothing);
      expect(find.text('Zoe Moss'), findsNothing);
      // No server to switch to.
      expect(find.byIcon(Icons.edit_outlined), findsNothing);

      await finishFakeChatList(tester, client);
    });

    testWidgets('with Matrix contacts the directory and server come back', (
      tester,
    ) async {
      phone(tester);
      addFakeChat(client, '!kim:x', 'Kim', partner: '@kim:matrix.org');
      await pumpFakeChatList(tester, client);

      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zo');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      expect(client.directorySearches, greaterThan(0));
      expect(find.text('People'), findsOneWidget);
      expect(find.text('Zoe Moss'), findsOneWidget);
      expect(find.byIcon(Icons.edit_outlined), findsOneWidget);

      await finishFakeChatList(tester, client);
    });

    testWidgets('People sits right under the chats found', (tester) async {
      phone(tester);
      addFakeChat(client, '!zola:x', 'Zola', partner: '@zola:matrix.org');
      await pumpFakeChatList(tester, client);
      await tester.tap(find.byTooltip('Search'));
      await tester.pumpAndSettle();
      await tester.enterText(find.byType(TextField), 'zo');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();

      final lastChat = tester.getRect(find.byType(ChatListItem).last);
      final people = tester.getRect(
        find.ancestor(
          of: find.text('People'),
          matching: find.byType(SearchTitle),
        ),
      );
      // No room is kept for the New chat button, which search hides.
      expect(find.byType(StartChatFab), findsNothing);
      expect(people.top - lastChat.bottom, lessThan(1));

      await finishFakeChatList(tester, client);
    });
  });

  testWidgets('the last chat scrolls clear of the New chat button', (
    tester,
  ) async {
    phone(tester);
    addChats();
    await pumpFakeChatList(tester, client);
    final position = tester
        .state<ScrollableState>(
          find
              .descendant(
                of: find.byType(CustomScrollView),
                matching: find.byType(Scrollable),
              )
              .first,
        )
        .position;
    // The list measures rows as they are built, so its end moves while
    // it is scrolled there.
    for (var i = 0; i < 5; i++) {
      position.jumpTo(position.maxScrollExtent);
      await tester.pumpAndSettle();
    }

    final lastChat = tester.getRect(
      find.ancestor(of: find.text('Chat 39'), matching: find.byType(ChatListItem)),
    );
    final fab = tester.getRect(find.byType(StartChatFab));
    expect(lastChat.bottom, lessThanOrEqualTo(fab.top));

    await finishFakeChatList(tester, client);
  });
}
