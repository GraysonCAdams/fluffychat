// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_filter_menu.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/pages/chat_list/search_scope.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list_fakes.dart';

/// The phone's search header: the field that slides out of the search
/// icon, the account button that turns into a close button, and the Search
/// in menu at the field's start.
void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('search slide test');
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

  Future<void> pumpPhone(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await pumpFakeChatList(tester, client);
  }

  Finder inHeader(Finder finder) =>
      find.descendant(of: find.byType(ChatListHeader), matching: finder);

  final pill = find.byKey(const ValueKey('chat_list_search_pill'));
  final searchIcon = inHeader(find.byIcon(Icons.search_outlined));
  final closeIcon = inHeader(find.byIcon(Icons.close_outlined));

  ChatListController list(WidgetTester tester) =>
      tester.state<ChatListController>(find.byType(ChatList));

  /// The opacity the nearest Opacity above [finder] gives it.
  double opacityOf(WidgetTester tester, Finder finder) => tester
      .widget<Opacity>(
        find.ancestor(of: finder, matching: find.byType(Opacity)).first,
      )
      .opacity;

  /// Opens the search and lets its first server search run.
  Future<void> openSearch(WidgetTester tester) async {
    await tester.tap(inHeader(find.byTooltip('Search')));
    await tester.pumpAndSettle();
    await tester.pump(const Duration(milliseconds: 600));
  }

  /// Types [text] and lets the search for it run.
  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  /// Picks [label] in the Search in menu, opened from the field's start.
  Future<void> pickScope(WidgetTester tester, String label) async {
    await tester.tap(find.byType(SearchScopeButton));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, label));
    await tester.pumpAndSettle();
  }

  testWidgets('the field grows out of the search icon, which stays put', (
    tester,
  ) async {
    await pumpPhone(tester);
    final icon = tester.getRect(searchIcon);
    // The end of the search button, whose 48 is centred on the icon.
    final buttonEnd = icon.center.dx + 24;
    final account = tester.getRect(find.byType(ClientChooserButton));
    final titleStart = tester.getRect(find.byType(ChatFilterButton)).left;

    await tester.tap(inHeader(find.byTooltip('Search')));
    await tester.pump();
    // A sixth of the way in: the field has grown leftwards from behind the
    // icon, the title is fading and drifting towards the start, and the
    // account button is on its way out.
    await tester.pump(const Duration(milliseconds: 60));
    final opening = tester.getRect(pill);
    expect(opening.right, buttonEnd);
    expect(opening.left, inExclusiveRange(titleStart, icon.left));
    expect(tester.getRect(searchIcon), icon);
    expect(
      opacityOf(tester, find.byType(ChatFilterButton)),
      inExclusiveRange(0, 1),
    );
    final drift = tester.getRect(find.byType(ChatFilterButton)).left;
    expect(drift, inExclusiveRange(titleStart - 12, titleStart));
    expect(
      opacityOf(tester, find.byType(ClientChooserButton)),
      inExclusiveRange(0, 1),
    );
    expect(list(tester).searchFocusNode.hasFocus, isTrue);

    // The title is gone 30% of the way in, 12 towards the start.
    await tester.pump(const Duration(milliseconds: 60));
    expect(opacityOf(tester, find.byType(ChatFilterButton)), closeTo(0, 1e-6));
    expect(
      tester.getRect(find.byType(ChatFilterButton)).left,
      closeTo(titleStart - 12, 0.01),
    );

    // Done after 400 ms: the field spans the bar from its start to the end
    // of the icon, and the close button sits where the account button was.
    await tester.pump(const Duration(milliseconds: 280));
    expect(inHeader(find.byType(ChatFilterButton)), findsNothing);
    expect(find.byType(ClientChooserButton), findsNothing);
    final open = tester.getRect(pill);
    expect(open.left, titleStart);
    expect(open.right, buttonEnd);
    expect(tester.getRect(searchIcon), icon);
    expect(tester.getCenter(closeIcon), account.center);
    expect(opacityOf(tester, closeIcon), 1);
    // The icon is the end of the field now, not a button.
    expect(inHeader(find.byTooltip('Search')), findsNothing);
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
      'Search chats, people, messages',
    );
    expect(list(tester).searchFocusNode.hasFocus, isTrue);
    expect(tester.testTextInput.isVisible, isTrue);

    await finishFakeChatList(tester, client);
  });

  testWidgets('the close button runs it all back in 250 ms', (tester) async {
    await pumpPhone(tester);
    final account = tester.getRect(find.byType(ClientChooserButton));
    await openSearch(tester);
    final open = tester.getRect(pill);

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(list(tester).isSearchMode, isFalse);
    await tester.pump(const Duration(milliseconds: 125));
    final closing = tester.getRect(pill);
    expect(closing.left, greaterThan(open.left));
    expect(closing.right, open.right);
    expect(opacityOf(tester, closeIcon), inExclusiveRange(0, 1));
    // The account button comes back in the second half.
    expect(opacityOf(tester, find.byType(ClientChooserButton)), 0);
    await tester.pump(const Duration(milliseconds: 65));
    expect(
      opacityOf(tester, find.byType(ClientChooserButton)),
      inExclusiveRange(0, 1),
    );
    expect(
      opacityOf(tester, find.byType(ChatFilterButton)),
      inExclusiveRange(0, 1),
    );

    await tester.pump(const Duration(milliseconds: 60));
    expect(pill, findsNothing);
    expect(closeIcon, findsNothing);
    expect(find.byType(TextField), findsNothing);
    expect(tester.getRect(find.byType(ClientChooserButton)), account);
    expect(opacityOf(tester, find.byType(ClientChooserButton)), 1);
    expect(opacityOf(tester, find.byType(ChatFilterButton)), 1);
    expect(inHeader(find.byTooltip('Search')).hitTestable(), findsOneWidget);

    await finishFakeChatList(tester, client);
  });

  testWidgets('back closes the search the same way', (tester) async {
    await pumpPhone(tester);
    await openSearch(tester);

    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(list(tester).isSearchMode, isFalse);
    expect(pill, findsNothing);
    expect(closeIcon, findsNothing);
    expect(find.byType(ClientChooserButton).hitTestable(), findsOneWidget);
    expect(find.byType(ChatFilterButton).hitTestable(), findsOneWidget);

    await finishFakeChatList(tester, client);
  });

  testWidgets('with animations off it opens and closes at once', (
    tester,
  ) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pumpPhone(tester);
    final titleStart = tester.getRect(find.byType(ChatFilterButton)).left;

    await tester.tap(inHeader(find.byTooltip('Search')));
    await tester.pump();
    expect(tester.getRect(pill).left, titleStart);
    // Lets the first server search run.
    await tester.pump(const Duration(milliseconds: 600));
    expect(inHeader(find.byType(ChatFilterButton)), findsNothing);
    expect(opacityOf(tester, closeIcon), 1);

    await pickScope(tester, 'People');
    // The chip is simply there, without growing out of the button.
    expect(find.byKey(SearchScopeButton.chipKey), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(SearchScopeButton),
        matching: find.byType(AnimatedSize),
      ),
      findsNothing,
    );

    await tester.tap(find.byTooltip('Cancel'));
    await tester.pump();
    expect(pill, findsNothing);
    expect(opacityOf(tester, find.byType(ChatFilterButton)), 1);

    await finishFakeChatList(tester, client);
  });

  testWidgets('before anything is typed the recent people show', (
    tester,
  ) async {
    await pumpPhone(tester);
    await openSearch(tester);

    expect(find.text('Recent'), findsOneWidget);
    // First names, and only people.
    expect(find.text('Harrison'), findsOneWidget);
    expect(find.text('Squad Goals'), findsNothing);
    expect(find.byType(ChatListItem), findsNothing);

    await finishFakeChatList(tester, client);
  });

  testWidgets('Search in narrows the results, and a chip shows the scope', (
    tester,
  ) async {
    addFakeChat(client, '!harbor:x', 'Harbor Club');
    await pumpPhone(tester);
    await openSearch(tester);
    await type(tester, 'har');
    expect(find.text('Harrison Young'), findsOneWidget);
    expect(find.text('Harbor Club'), findsOneWidget);
    expect(find.byKey(SearchScopeButton.chipKey), findsNothing);

    await tester.tap(find.byTooltip('Search in'));
    await tester.pumpAndSettle();
    for (final label in [
      'All',
      'Chats',
      'People',
      'Messages',
      'Media',
      'Links',
    ]) {
      expect(find.widgetWithText(PopupMenuItem<String>, label), findsOneWidget);
    }
    // Everything is searched until a scope is picked.
    expect(
      find.descendant(
        of: find.widgetWithText(PopupMenuItem<String>, 'All'),
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );
    await tester.tap(find.widgetWithText(PopupMenuItem<String>, 'People'));
    await tester.pumpAndSettle();

    expect(list(tester).searchScope, SearchScope.people);
    final chip = find.byKey(SearchScopeButton.chipKey);
    expect(
      find.descendant(of: chip, matching: find.text('People')),
      findsOneWidget,
    );
    final semantics = tester.ensureSemantics();
    expect(find.bySemanticsLabel('Search in: People'), findsOneWidget);
    semantics.dispose();
    expect(
      tester.widget<TextField>(find.byType(TextField)).decoration!.hintText,
      'Search people',
    );
    expect(find.text('Harrison Young'), findsOneWidget);
    expect(find.text('Harbor Club'), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SearchTitle),
        matching: find.text('People'),
      ),
      findsOneWidget,
    );
    // The keyboard stays with the field through the menu.
    expect(list(tester).searchFocusNode.hasFocus, isTrue);

    await pickScope(tester, 'Messages');
    expect(find.byType(ChatListItem), findsNothing);
    expect(
      find.descendant(
        of: find.byType(SearchTitle),
        matching: find.text('Messages'),
      ),
      findsOneWidget,
    );

    // The next search starts out searching everything again.
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    await openSearch(tester);
    expect(list(tester).searchScope, SearchScope.all);
    expect(find.byKey(SearchScopeButton.chipKey), findsNothing);

    await finishFakeChatList(tester, client);
  });

  testWidgets('the typed text is marked in the names found', (tester) async {
    await pumpPhone(tester);
    await openSearch(tester);
    await type(tester, 'har');

    final name = tester.widget<Text>(
      find.descendant(
        of: find.byType(ChatListItem),
        matching: find.text('Harrison Young'),
      ),
    );
    final spans = (name.textSpan! as TextSpan).children!.cast<TextSpan>();
    final theme = Theme.of(tester.element(find.byType(ChatListItem)));
    expect(spans.map((span) => span.text), ['Har', 'rison Young']);
    expect(spans.first.style?.color, theme.colorScheme.primary);
    expect(spans.first.style?.fontWeight, FontWeight.bold);
    expect(spans.last.style, isNull);

    await finishFakeChatList(tester, client);
  });

  group('state layers sit centred on their icons', () {
    /// The ink of the button [button] holds.
    InkWell inkOf(WidgetTester tester, Finder button) => tester.widget<InkWell>(
      find.descendant(of: button, matching: find.byType(InkWell)).first,
    );

    Rect inkRect(WidgetTester tester, Finder button) => tester.getRect(
      find.descendant(of: button, matching: find.byType(InkWell)).first,
    );

    testWidgets('the Search in button: a 40 circle, concentric with the '
        "field's end", (tester) async {
      await pumpPhone(tester);
      await openSearch(tester);
      final button = find.byType(SearchScopeButton);
      final icon = tester.getCenter(
        find.descendant(of: button, matching: find.byIcon(Icons.filter_list)),
      );
      final ink = inkRect(tester, button);
      expect(ink.size, const Size(40, 40));
      expect(ink.center, icon);
      expect(
        inkOf(tester, button).customBorder,
        anyOf(isA<CircleBorder>(), isA<StadiumBorder>()),
      );
      // The field's round end is centred half its height in from its start,
      // and so is the state layer.
      final field = tester.getRect(pill);
      expect(icon.dx - field.left, field.height / 2);
      expect(icon.dy, field.center.dy);

      await finishFakeChatList(tester, client);
    });

    testWidgets('the close button: a 40 circle on the cross', (tester) async {
      await pumpPhone(tester);
      await openSearch(tester);
      final button = find.ancestor(
        of: closeIcon,
        matching: find.byType(IconButton),
      );
      final ink = inkRect(tester, button);
      expect(ink.size, const Size(40, 40));
      expect(ink.center, tester.getCenter(closeIcon));
      expect(
        inkOf(tester, button).customBorder,
        anyOf(isA<CircleBorder>(), isA<StadiumBorder>()),
      );

      await finishFakeChatList(tester, client);
    });

    testWidgets("the chip: a stadium, concentric with the field's end", (
      tester,
    ) async {
      await pumpPhone(tester);
      await openSearch(tester);
      await pickScope(tester, 'People');
      final chip = find.byKey(SearchScopeButton.chipKey);
      expect(inkOf(tester, chip).customBorder, isA<StadiumBorder>());
      final ink = inkRect(tester, chip);
      final field = tester.getRect(pill);
      expect(ink.height, 32);
      expect(ink.center.dy, field.center.dy);
      // Its round start is centred where the field's is.
      expect(ink.left + ink.height / 2 - field.left, field.height / 2);

      await finishFakeChatList(tester, client);
    });
  });
}
