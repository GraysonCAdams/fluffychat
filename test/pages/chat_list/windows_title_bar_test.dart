// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:math' as math;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_filter_menu.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/pages/chat_list/navi_rail_item.dart';
import 'package:fluffychat/pages/chat_list/start_chat_fab.dart';
import 'package:fluffychat/pages/chat_list/title_bar_search.dart';
import 'package:fluffychat/utils/windows_shell_ffi.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:window_manager/window_manager.dart';

import 'chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;
  late GoRouter router;

  setUp(() async {
    client = await setUpFakeChatList('windows title bar test');
    addFakeChat(client, '!grp:x', 'Squad Goals');
    addFakeChat(
      client,
      '!dm:x',
      'Harrison Young',
      partner: '@harrison:x',
      lastMessageTime: DateTime(2025),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          const MethodChannel('window_manager'),
          (call) async => call.method == 'isMaximized' ? false : null,
        );
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('window_manager'), null);
    tearDownFakeChatList(client);
  });

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// The app as Windows shows it in a window [width] wide: the title bar
  /// above the router, with the chat list at `/rooms` and a settings page
  /// that covers it.
  Future<void> pumpWindow(WidgetTester tester, double width) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = Size(width, 800);
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => const ChatList(activeChat: null),
          routes: [
            GoRoute(
              path: 'settings',
              builder: (context, state) =>
                  const Scaffold(body: Text('settings page')),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp.router(
          theme: ThemeData(
            appBarTheme: const AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle.dark,
            ),
            // The Material label line height, which the app font fills; the
            // test font alone would leave chip labels 14 high.
            textTheme: const TextTheme(
              labelLarge: TextStyle(
                fontSize: 14,
                height: 20 / 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
          builder: (context, child) => WindowsChrome(
            showChatList: () => router.go('/rooms'),
            child: child!,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await finishFakeChatList(tester, client);
  }

  Finder searchField() => find.descendant(
    of: find.byType(TitleBarSearchField),
    matching: find.byType(TextField),
  );

  ChatListController list(WidgetTester tester) =>
      tester.state<ChatListController>(find.byType(ChatList));

  TitleBarSearch search(WidgetTester tester) => list(tester).titleBarSearch!;

  Future<void> pressCtrlK(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyK);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  group('layout', () {
    for (final width in [640.0, 1280.0]) {
      testWidgets('in a window $width wide', (tester) async {
        await pumpWindow(tester, width);

        // The app takes the whole window. In column mode (1280) the rail
        // runs up beside the bar, which starts after it; a narrow window has
        // no rail, and the bar spans it.
        final left = width >= 1280 ? 80.0 : 0.0;
        expect(
          tester.getRect(find.byType(DragToMoveArea)),
          Rect.fromLTWH(left, 0, width - left, 48),
        );
        expect(tester.getTopLeft(find.byType(ChatList)), Offset.zero);

        // No app tile and no app name: the list's title, "Chats", heads the
        // list column 16 in.
        // (The rail's first tile shows the app tile, left of the bar.)
        final appTiles = find.byWidgetPredicate(
          (widget) =>
              widget is Image &&
              widget.image is AssetImage &&
              (widget.image as AssetImage).assetName ==
                  'assets/seam/seam_app_icon.png',
        );
        expect(
          appTiles.evaluate().where(
            (element) =>
                tester.getRect(find.byWidget(element.widget)).left >= left,
          ),
          isEmpty,
        );
        expect(find.text('Seam'), findsNothing);
        expect(find.text('All chats'), findsNothing);
        final title = tester.getRect(
          find.descendant(
            of: find.byType(ChatFilterButton),
            matching: find.text('Chats'),
          ),
        );
        expect(title.left, left + 16);
        expect(title.center.dy, closeTo(24, 1));

        // Window buttons: three 46 wide, full height, at the right edge.
        final glyphs = find.byWidgetPredicate(
          (widget) =>
              widget is CustomPaint &&
              widget.painter.runtimeType.toString() == '_CaptionGlyphPainter',
        );
        expect(glyphs, findsNWidgets(3));
        for (var i = 0; i < 3; i++) {
          expect(
            tester.getCenter(glyphs.at(i)),
            Offset(width - 46 * (3 - i) + 23, 24),
          );
        }

        // The avatar: 32 round, 8 left of the 138 of window buttons.
        final avatar = tester.getRect(
          find.byKey(const Key('accounts_and_settings_buttons')),
        );
        expect(avatar, Rect.fromLTWH(width - 146 - 32, 8, 32, 32));

        // Search: 32 high, centred on the window, clear of both.
        final field = tester.getRect(find.byType(TitleBarSearchField));
        expect(field.height, 32);
        expect(field.top, 8);
        expect(field.center.dx, width / 2);
        expect(field.width, width >= 1180 ? 520 : 252);
        expect(field.left, greaterThan(title.right + 16));
        expect(field.right, lessThanOrEqualTo(avatar.left - 16));
        expect(
          find.text('Ctrl+K'),
          width >= 1180 ? findsOneWidget : findsNothing,
        );
        await finish(tester);
      });
    }

    test('the search field never reaches the title or the avatar', () {
      for (var width = 300.0; width <= 2560; width += 10) {
        final field = WindowsChrome.searchWidth(width);
        if (field == 0) continue;
        final left = (width - field) / 2;
        expect(left, greaterThan(80), reason: 'at $width');
        expect(left + field, lessThanOrEqualTo(width - 146 - 32 - 16));
      }
    });
  });

  testWidgets('the rail runs from the top, clickable beside the bar', (
    tester,
  ) async {
    await pumpWindow(tester, 1280);
    final tile = find.byType(NaviRailItem).first;
    final rect = tester.getRect(tile);
    expect(rect.top, lessThan(24));
    expect(rect.center.dy, lessThan(48));
    // A click there reaches the tile, not the window's drag area.
    expect(tile.hitTestable(), findsOneWidget);
    expect(tester.getRect(find.byType(DragToMoveArea)).left, 80);
    await finish(tester);
  });

  testWidgets('the title lines up with the first pinned avatar', (
    tester,
  ) async {
    // More pins than the row holds, so it starts at the list's edge rather
    // than centring them; the list here runs the window's width.
    for (var i = 0; i < 12; i++) {
      addFakeChat(
        client,
        '!pin$i:x',
        'Pin $i',
        partner: '@pin$i:x',
      ).pin(i.toDouble());
    }
    await pumpWindow(tester, 1280);
    final avatars = find.byWidgetPredicate(
      (widget) => widget is Avatar && widget.size == 76,
    );
    expect(avatars, findsWidgets);
    final firstAvatar = avatars
        .evaluate()
        .map((element) => tester.getRect(find.byWidget(element.widget)).left)
        .reduce(math.min);
    final title = tester.getRect(
      find.descendant(
        of: find.byType(ChatFilterButton),
        matching: find.text('Chats'),
      ),
    );
    expect(title.left, 96);
    expect(firstAvatar, 96);
    // The pinned row starts right under the band.
    expect(
      avatars
          .evaluate()
          .map((e) => tester.getRect(find.byWidget(e.widget)).top)
          .reduce(math.min),
      lessThan(48 + 60),
    );
    await finish(tester);
  });

  testWidgets('the list has no header and the chats start under the bar', (
    tester,
  ) async {
    await pumpWindow(tester, 1280);
    expect(find.byType(ChatListHeader), findsNothing);
    expect(find.byType(FilterChip), findsNothing);
    // Only the 48 of title bar above the first chat's row.
    expect(tester.getTopLeft(find.text('Squad Goals')).dy, lessThan(48 + 48));
    // The list starts right after the 80 rail, with no divider between.
    expect(tester.getTopLeft(find.byType(ChatListItem).first).dx, 80);
    await finish(tester);
  });

  testWidgets('the title bar dropdown filters the chat list', (tester) async {
    await pumpWindow(tester, 1280);
    final dropdown = find.byType(ChatFilterButton);
    expect(dropdown, findsOneWidget);
    // In the title bar, not in the list.
    expect(
      find.ancestor(of: dropdown, matching: find.byType(ChatList)),
      findsNothing,
    );
    await tester.tap(dropdown);
    await tester.pumpAndSettle();
    // The menu hangs from the bar.
    final unread = find.descendant(
      of: find.byType(PopupMenuItem<String>),
      matching: find.text('Groups'),
    );
    expect(unread, findsOneWidget);
    expect(tester.getRect(unread).top, greaterThan(48));
    await tester.tap(unread);
    await tester.pumpAndSettle();
    expect(list(tester).activeFilter, ActiveFilter.groups);
    expect(find.text('Harrison Young'), findsNothing);
    expect(
      find.descendant(of: dropdown, matching: find.text('Groups')),
      findsOneWidget,
    );

    // The keyboard reaches it too: Space opens the menu.
    Focus.of(
      tester.element(
        find.descendant(of: dropdown, matching: find.byType(Row)).first,
      ),
    ).requestFocus();
    await tester.pump();
    await tester.sendKeyEvent(LogicalKeyboardKey.space);
    await tester.pumpAndSettle();
    expect(find.byType(PopupMenuItem<String>), findsWidgets);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    await finish(tester);
  });

  testWidgets('selecting floats a toolbar over the list, which stays put', (
    tester,
  ) async {
    await pumpWindow(tester, 1280);
    final before = tester.getTopLeft(find.text('Squad Goals')).dy;
    expect(find.byType(StartChatFab), findsOneWidget);
    await tester.longPress(find.text('Squad Goals'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatListSelectionBar), findsNothing);
    final toolbar = find.byType(ChatListSelectionToolbar);
    expect(toolbar, findsOneWidget);
    expect(tester.getTopLeft(find.text('Squad Goals')).dy, before);
    // In New chat's place: 64 high, 16 above the bottom, in the middle of
    // the list, which runs from the 80 rail to the window's edge.
    final rect = tester.getRect(toolbar);
    expect(rect.height, closeTo(64, 0.01));
    expect(rect.bottom, closeTo(800 - 16, 0.01));
    expect(rect.center.dx, closeTo((80 + 1280) / 2, 1));
    expect(find.byType(StartChatFab), findsNothing);
    expect(
      find.descendant(of: toolbar, matching: find.byTooltip('Clear selection')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: toolbar, matching: find.text('1')),
      findsOneWidget,
    );
    expect(
      find.descendant(of: toolbar, matching: find.byTooltip('Leave')),
      findsOneWidget,
    );

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();
    expect(toolbar, findsNothing);
    expect(find.byType(StartChatFab), findsOneWidget);
    await finish(tester);
  });

  testWidgets('typing in the title bar searches the chat list', (tester) async {
    await pumpWindow(tester, 1280);
    await tester.enterText(searchField(), 'squad');
    await tester.pumpAndSettle();

    expect(list(tester).isSearchMode, isTrue);
    expect(list(tester).searchController.text, 'squad');
    expect(find.text('Harrison Young'), findsNothing);
    expect(find.text('Squad Goals'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('Ctrl+K puts the cursor in the field', (tester) async {
    await pumpWindow(tester, 1280);
    expect(search(tester).focusNode.hasFocus, isFalse);
    await pressCtrlK(tester);
    expect(search(tester).focusNode.hasFocus, isTrue);
    await finish(tester);
  });

  testWidgets('Escape ends the search', (tester) async {
    await pumpWindow(tester, 1280);
    await tester.enterText(searchField(), 'squad');
    await tester.pumpAndSettle();
    expect(find.text('Harrison Young'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(list(tester).isSearchMode, isFalse);
    expect(search(tester).textController.text, isEmpty);
    expect(search(tester).focusNode.hasFocus, isFalse);
    expect(find.text('Harrison Young'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('the clear button ends the search', (tester) async {
    await pumpWindow(tester, 1280);
    await tester.enterText(searchField(), 'squad');
    await tester.pumpAndSettle();
    expect(find.text('Ctrl+K'), findsNothing);

    await tester.tap(
      find.descendant(
        of: find.byType(TitleBarSearchField),
        matching: find.byTooltip('Cancel'),
      ),
    );
    await tester.pumpAndSettle();
    expect(list(tester).isSearchMode, isFalse);
    expect(search(tester).textController.text, isEmpty);
    expect(find.text('Harrison Young'), findsOneWidget);
    expect(find.text('Ctrl+K'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('clearing the text keeps the search open and focused', (
    tester,
  ) async {
    await pumpWindow(tester, 1280);
    await tester.enterText(searchField(), 'squad');
    await tester.pumpAndSettle();
    expect(find.text('Harrison Young'), findsNothing);

    await tester.enterText(searchField(), '');
    await tester.pumpAndSettle();
    expect(list(tester).isSearchMode, isTrue);
    expect(search(tester).focusNode.hasFocus, isTrue);
    expect(find.text('Harrison Young'), findsOneWidget);
    // The clear button stays to end the search, in place of the hint.
    expect(
      find.descendant(
        of: find.byType(TitleBarSearchField),
        matching: find.byTooltip('Cancel'),
      ),
      findsOneWidget,
    );
    expect(find.text('Ctrl+K'), findsNothing);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(list(tester).isSearchMode, isFalse);
    expect(search(tester).focusNode.hasFocus, isFalse);
    expect(find.text('Ctrl+K'), findsOneWidget);
    await finish(tester);
  });

  testWidgets('searching from another page goes back to the chat list', (
    tester,
  ) async {
    await pumpWindow(tester, 640);
    router.go('/rooms/settings');
    await tester.pumpAndSettle();
    expect(find.text('settings page'), findsOneWidget);

    await pressCtrlK(tester);
    expect(location(), '/rooms');
    expect(find.text('settings page'), findsNothing);
    expect(search(tester).focusNode.hasFocus, isTrue);
    await finish(tester);
  });

  testWidgets('the avatar opens the account menu below the bar', (
    tester,
  ) async {
    await pumpWindow(tester, 1280);
    // The test font draws every letter as wide as it is tall, so the longer
    // menu entries overflow the menu's width; that is not tested here.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      onError?.call(details);
    };
    try {
      await tester.tap(find.byKey(const Key('accounts_and_settings_buttons')));
      await tester.pumpAndSettle();
      final settings = find.text('Settings');
      expect(settings, findsOneWidget);
      expect(tester.getTopLeft(settings).dy, greaterThan(48));

      await tester.tap(settings);
      await tester.pumpAndSettle();
      expect(location(), '/rooms/settings');
    } finally {
      FlutterError.onError = onError;
    }
    await finish(tester);
  });
}
