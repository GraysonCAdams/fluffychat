// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/pages/chat_list/title_bar_search.dart';
import 'package:fluffychat/utils/windows_shell_ffi.dart';
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

        // The bar spans the window, 48 high, and the app starts below it.
        expect(
          tester.getRect(find.byType(DragToMoveArea)),
          Rect.fromLTWH(0, 0, width, 48),
        );
        expect(tester.getTopLeft(find.byType(ChatList)), const Offset(0, 48));

        // A 24 icon 16 in, the name 12 after it.
        final icon = tester.getRect(
          find.byWidgetPredicate(
            (widget) =>
                widget is Image &&
                widget.width == 24 &&
                widget.image is AssetImage &&
                (widget.image as AssetImage).assetName ==
                    'assets/seam/seam_app_icon.png',
          ),
        );
        expect(icon, const Rect.fromLTWH(16, 12, 24, 24));
        expect(
          find.ancestor(
            of: find.byWidgetPredicate((w) => w is Image && w.width == 24),
            matching: find.byType(ClipRSuperellipse),
          ),
          findsOneWidget,
        );
        final title = tester.getRect(find.text('Seam'));
        expect(title.left, 16 + 24 + 12);

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

  testWidgets('the list starts with the chips and has no header', (
    tester,
  ) async {
    await pumpWindow(tester, 1280);
    expect(find.byType(ChatListHeader), findsNothing);

    final chips = find.byType(FilterChip);
    final first = tester.getRect(chips.at(0));
    final second = tester.getRect(chips.at(1));
    // A 48 row right under the bar: 8 above the chips, 16 in from the edge
    // of the list, which starts right after the 80 rail.
    expect(first.top, 48 + 8);
    expect(first.height, 32);
    expect(first.left, 80 + 16);
    expect(second.left - first.right, 8);
    expect(second.top, first.top);
    final label = tester.widget<DefaultTextStyle>(
      find
          .ancestor(
            of: find.text('Unread'),
            matching: find.byType(DefaultTextStyle),
          )
          .first,
    );
    // Centred in the chip, to the pixel: a 20 high label fits the 32. The
    // test font sets the label a pixel low within its line.
    final unread = find.ancestor(
      of: find.text('Unread'),
      matching: find.byType(FilterChip),
    );
    expect(
      tester.getCenter(find.text('Unread')).dy,
      closeTo(tester.getCenter(unread).dy, 1),
    );
    expect(label.style.fontSize, 14);
    expect(label.style.fontWeight, FontWeight.w500);
    // The chats follow the chip row.
    expect(
      tester.getTopLeft(find.text('Squad Goals')).dy,
      greaterThan(48 + 48),
    );
    await finish(tester);
  });

  testWidgets('selecting a chat keeps the chats where they are', (
    tester,
  ) async {
    await pumpWindow(tester, 1280);
    final before = tester.getTopLeft(find.text('Squad Goals')).dy;
    await tester.longPress(find.text('Squad Goals'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatListSelectionBar), findsOneWidget);
    expect(find.byType(FilterChip), findsNothing);
    expect(tester.getTopLeft(find.text('Squad Goals')).dy, before);
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
