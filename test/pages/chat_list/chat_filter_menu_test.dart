// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_filter_menu.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('chat filter menu test');
    addFakeChat(
      client,
      '!harrison:x',
      'Harrison Young',
      partner: '@imessage_harrison:x',
      notificationCount: 1,
      lastMessageTime: DateTime(2026, 1, 5),
    );
    addFakeChat(
      client,
      '!squad:x',
      'Squad Goals',
      lastMessageTime: DateTime(2026, 1, 4),
    );
    addFakeChat(
      client,
      '!drew:x',
      'Drew Park',
      partner: '@drew:x',
      lastMessageTime: DateTime(2026, 1, 3),
    );
    addFakeSpace(client, '!imsg:x', 'iMessage', ['!harrison:x']);
    addFakeSpace(client, '!wa:x', 'WhatsApp', ['!drew:x']);
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await pumpFakeChatList(tester, client);
  }

  Finder title() => find.byType(ChatFilterButton);

  String titleText(WidgetTester tester) => tester
      .widget<Text>(find.descendant(of: title(), matching: find.byType(Text)))
      .data!;

  Future<void> open(WidgetTester tester) async {
    await tester.tap(title());
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String label) async {
    await tester.tap(
      find.descendant(
        of: find.byType(PopupMenuItem<String>),
        matching: find.text(label),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The rows of the menu that carry the check.
  List<String> checked(WidgetTester tester) => [
    for (final item in find.byType(PopupMenuItem<String>).evaluate())
      if (find
          .descendant(
            of: find.byWidget(item.widget),
            matching: find.byIcon(Icons.check),
          )
          .evaluate()
          .isNotEmpty)
        tester
            .widgetList<Text>(
              find.descendant(
                of: find.byWidget(item.widget),
                matching: find.byType(Text),
              ),
            )
            // After the network's avatar, which may show initials.
            .last
            .data!,
  ];

  testWidgets('the title is the filter dropdown, with no chip row', (
    tester,
  ) async {
    await pump(tester);
    expect(find.byType(FilterChip), findsNothing);
    expect(find.text('Chats'), findsNothing);
    expect(titleText(tester), 'All chats');
    expect(find.byIcon(Icons.arrow_drop_down), findsOneWidget);
    await finishFakeChatList(tester, client);
  });

  testWidgets('the account avatar beside the title is 32 round', (
    tester,
  ) async {
    await pump(tester);
    // In a 48 tap target.
    final button = find.byKey(const Key('accounts_and_settings_buttons'));
    expect(
      tester.getSize(
        find.descendant(of: button, matching: find.byType(Avatar)),
      ),
      const Size(32, 32),
    );
    await finishFakeChatList(tester, client);
  });

  testWidgets('tapping the title opens the menu', (tester) async {
    await pump(tester);
    await open(tester);
    for (final label in [
      'All chats',
      'Unread',
      'Groups',
      'People',
      'Networks',
      'iMessage',
    ]) {
      expect(
        find.descendant(
          of: find.byType(PopupMenuItem<String>),
          matching: find.text(label),
        ),
        findsOneWidget,
        reason: label,
      );
    }
    // One before the networks, one before the actions.
    expect(find.byType(PopupMenuDivider), findsNWidgets(2));
    expect(checked(tester), ['All chats']);
    // Material menu rows, 48 high.
    expect(
      tester
          .getSize(find.widgetWithText(PopupMenuItem<String>, 'Unread'))
          .height,
      48,
    );
    await finishFakeChatList(tester, client);
  });

  testWidgets('picking Unread filters the list and names it in the title', (
    tester,
  ) async {
    await pump(tester);
    await open(tester);
    await pick(tester, 'Unread');
    expect(titleText(tester), 'Unread');
    expect(find.text('Harrison Young'), findsOneWidget);
    expect(find.text('Squad Goals'), findsNothing);
    expect(
      tester.state<ChatListController>(find.byType(ChatList)).activeFilter,
      ActiveFilter.unread,
    );

    await open(tester);
    expect(checked(tester), ['Unread']);
    // Picked again, it clears.
    await pick(tester, 'Unread');
    expect(titleText(tester), 'All chats');
    expect(find.text('Squad Goals'), findsOneWidget);
    await finishFakeChatList(tester, client);
  });

  testWidgets('picking a network filters to it, and combines with a kind', (
    tester,
  ) async {
    await pump(tester);
    await open(tester);
    await pick(tester, 'iMessage');
    expect(titleText(tester), 'iMessage');
    expect(find.text('Harrison Young'), findsOneWidget);
    expect(find.text('Drew Park'), findsNothing);
    expect(
      tester.state<ChatListController>(find.byType(ChatList)).sourceSpaceId,
      '!imsg:x',
    );

    await open(tester);
    await pick(tester, 'People');
    expect(titleText(tester), 'People · iMessage');
    await open(tester);
    expect(checked(tester), ['People', 'iMessage']);

    // All chats clears both.
    await pick(tester, 'All chats');
    expect(titleText(tester), 'All chats');
    expect(find.text('Drew Park'), findsOneWidget);
    await finishFakeChatList(tester, client);
  });

  testWidgets('tags are listed and filter', (tester) async {
    client.getRoomById('!squad:x')!.roomAccountData['m.tag'] = BasicEvent(
      type: 'm.tag',
      content: {
        'tags': {'u.work': {}},
      },
    );
    await pump(tester);
    await open(tester);
    expect(find.text('Tags'), findsOneWidget);
    await pick(tester, 'work');
    expect(titleText(tester), 'work');
    expect(find.text('Squad Goals'), findsOneWidget);
    expect(find.text('Drew Park'), findsNothing);
    await finishFakeChatList(tester, client);
  });

  testWidgets('a screen reader hears a button with the filter', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    expect(
      tester.getSemantics(title()),
      isSemantics(
        label: 'Filter chats, All chats selected',
        isButton: true,
        hasTapAction: true,
        isFocusable: true,
      ),
    );
    semantics.dispose();
    await finishFakeChatList(tester, client);
  });

  testWidgets('the keyboard opens the menu and moves through it', (
    tester,
  ) async {
    await pump(tester);
    Focus.of(
      tester.element(
        find.descendant(of: title(), matching: find.byType(Row)).first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsWidgets);

    // The focused row: it holds Unread and no other row's label.
    bool onUnread() {
      final focused = FocusManager.instance.primaryFocus?.context;
      if (focused == null) return false;
      bool holds(String label) => find
          .descendant(
            of: find.byWidget(focused.widget),
            matching: find.text(label),
          )
          .evaluate()
          .isNotEmpty;
      return holds('Unread') && !holds('Groups');
    }

    for (var i = 0; i < 4 && !onUnread(); i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
    }
    expect(onUnread(), isTrue);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(titleText(tester), 'Unread');
    await finishFakeChatList(tester, client);
  });

  testWidgets('search hides the title, which comes back after', (tester) async {
    await pump(tester);
    await tester.tap(find.byTooltip('Search'));
    await tester.pumpAndSettle();
    expect(title().hitTestable(), findsNothing);
    await tester.tap(find.byTooltip('Cancel'));
    await tester.pumpAndSettle();
    expect(title().hitTestable(), findsOneWidget);
    await finishFakeChatList(tester, client);
  });

  ChatListController list(WidgetTester tester) =>
      tester.state<ChatListController>(find.byType(ChatList));

  Future<void> enterSpace(WidgetTester tester, String id) async {
    // Opening a space loads it from the database first.
    await tester.runAsync(() => list(tester).setActiveSpace(id));
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester, String label) => tester
      .widget<PopupMenuItem<String>>(
        find.widgetWithText(PopupMenuItem<String>, label),
      )
      .enabled;

  testWidgets('inside a space the title is its name, with the same menu', (
    tester,
  ) async {
    await pump(tester);
    await enterSpace(tester, '!imsg:x');
    expect(titleText(tester), 'iMessage');
    // No header of the space's own: no back arrow, no filter button.
    expect(find.byIcon(Icons.arrow_back), findsNothing);
    expect(find.byIcon(Icons.filter_list), findsNothing);
    expect(find.text('Harrison Young'), findsOneWidget);
    expect(find.text('Drew Park'), findsNothing);

    await open(tester);
    expect(checked(tester), ['iMessage']);
    await pick(tester, 'Unread');
    expect(titleText(tester), 'Unread · iMessage');
    expect(list(tester).activeSpaceId, '!imsg:x');

    // All chats goes back to every chat.
    await open(tester);
    await pick(tester, 'All chats');
    expect(list(tester).activeSpaceId, isNull);
    expect(titleText(tester), 'All chats');
    expect(find.text('Drew Park'), findsOneWidget);
    await finishFakeChatList(tester, client);
  });

  testWidgets('inside a space the menu switches to another network', (
    tester,
  ) async {
    await pump(tester);
    await enterSpace(tester, '!imsg:x');
    await open(tester);
    await pick(tester, 'WhatsApp');
    await tester.pumpAndSettle();
    expect(list(tester).activeSpaceId, '!wa:x');
    expect(titleText(tester), 'WhatsApp');
    await finishFakeChatList(tester, client);
  });

  testWidgets('Mark all as read sits in the title menu', (tester) async {
    await pump(tester);
    await open(tester);
    expect(find.text('Mark all as read'), findsOneWidget);
    expect(enabled(tester, 'Mark all as read'), isTrue);
    await pick(tester, 'Mark all as read');
    expect((client.getRoomById('!harrison:x')! as FakeChatListRoom).calls, [
      'read',
    ]);
    await finishFakeChatList(tester, client);
  });

  testWidgets('inside a space Mark all as read marks only its chats', (
    tester,
  ) async {
    (client.getRoomById('!drew:x')! as FakeChatListRoom).notificationCount = 1;
    await pump(tester);
    await enterSpace(tester, '!wa:x');
    await open(tester);
    await pick(tester, 'Mark all as read');
    expect((client.getRoomById('!drew:x')! as FakeChatListRoom).calls, [
      'read',
    ]);
    expect(
      (client.getRoomById('!harrison:x')! as FakeChatListRoom).calls,
      isEmpty,
    );
    await finishFakeChatList(tester, client);
  });

  testWidgets('Mark all as read is disabled with nothing unread', (
    tester,
  ) async {
    await pump(tester);
    await enterSpace(tester, '!wa:x');
    await open(tester);
    expect(find.text('Mark all as read'), findsOneWidget);
    expect(enabled(tester, 'Mark all as read'), isFalse);
    await finishFakeChatList(tester, client);
  });

  testWidgets('tapping the title again closes the menu and turns the arrow '
      'back', (tester) async {
    await pump(tester);
    double turns() => tester
        .widget<RotationTransition>(
          find.descendant(
            of: title(),
            matching: find.byType(RotationTransition),
          ),
        )
        .turns
        .value;
    await open(tester);
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    expect(turns(), 0.5);
    await tester.tap(title(), warnIfMissed: false);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsNothing);
    expect(turns(), 0);
    await finishFakeChatList(tester, client);
  });

  testWidgets('with reduced motion the arrow turns at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    await pump(tester);
    await tester.tap(title());
    await tester.pump();
    await tester.pump();
    expect(
      tester
          .widget<RotationTransition>(
            find.descendant(
              of: title(),
              matching: find.byType(RotationTransition),
            ),
          )
          .turns
          .value,
      0.5,
    );
    await tester.pumpAndSettle();
    await finishFakeChatList(tester, client);
  });
}
