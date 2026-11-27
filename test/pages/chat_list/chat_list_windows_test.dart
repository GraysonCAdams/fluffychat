// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/chat_windows/chat_windows.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/fake_chat_windows.dart';
import '../../utils/merged_contacts/fake_rooms.dart' show setMergedContacts;
import 'chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;
  late FakeChatWindowBackend backend;
  late GoRouter router;

  setUp(() async {
    client = await setUpFakeChatList('chat list windows test');
    addFakeChat(client, '!grp:x', 'Squad Goals');
    addFakeChat(
      client,
      '!dm:x',
      'Harrison Young',
      partner: '@harrison:x',
      lastMessageTime: DateTime(2025),
    );
    backend = installFakeChatWindows();
  });

  tearDown(() {
    removeFakeChatWindows();
    tearDownFakeChatList(client);
  });

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  /// The chat list with the opened chat beside it, as in the column
  /// layout, so a second click lands on the list again.
  Future<void> pumpChatList(WidgetTester tester) async {
    final prefs = await SharedPreferences.getInstance();
    router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        ShellRoute(
          builder: (context, state, child) => Row(
            children: [
              SizedBox(
                width: 400,
                child: ChatList(activeChat: state.pathParameters['roomid']),
              ),
              Expanded(child: child),
            ],
          ),
          routes: [
            GoRoute(
              path: '/rooms',
              builder: (context, state) => const SizedBox(),
              routes: [
                GoRoute(
                  path: ':roomid',
                  builder: (context, state) =>
                      Text('opened ${state.pathParameters['roomid']}'),
                ),
              ],
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
          ),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> finish(WidgetTester tester) =>
      finishFakeChatList(tester, client);

  Future<void> openMore(WidgetTester tester, String name) async {
    await tester.longPress(chatRowAvatar(name));
    await tester.pumpAndSettle();
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
  }

  group('double click', () {
    testWidgets('a single click opens the chat at once, here', (tester) async {
      await pumpChatList(tester);
      await tester.tap(find.text('Squad Goals'));
      await tester.pump();
      expect(location(), '/rooms/!grp:x');

      await tester.pump(kDoubleTapTimeout);
      await tester.pumpAndSettle();
      expect(backend.windows, isEmpty);
      await finish(tester);
    });

    testWidgets('opens the chat in a window and the main window goes back', (
      tester,
    ) async {
      await pumpChatList(tester);
      await tester.tap(find.text('Squad Goals'));
      await tester.pump();
      await tester.tap(find.text('Squad Goals'));
      await tester.pumpAndSettle();

      expect(backend.windows, hasLength(1));
      expect(backend.windows.single.title, 'Squad Goals');
      expect(
        ChatWindows.instance.isOpen(const ChatWindowTarget.room('!grp:x')),
        isTrue,
      );
      expect(location(), '/rooms');
      await finish(tester);
    });

    testWidgets('returns the main window to the chat it showed before', (
      tester,
    ) async {
      await pumpChatList(tester);
      await tester.tap(find.text('Harrison Young'));
      await tester.pumpAndSettle();
      expect(location(), '/rooms/!dm:x');

      await tester.tap(find.text('Squad Goals'));
      await tester.pump();
      await tester.tap(find.text('Squad Goals'));
      await tester.pumpAndSettle();
      expect(backend.windows.single.title, 'Squad Goals');
      expect(location(), '/rooms/!dm:x');
      await finish(tester);
    });

    testWidgets('two clicks too far apart are two single clicks', (
      tester,
    ) async {
      await pumpChatList(tester);
      await tester.tap(find.text('Squad Goals'));
      await tester.pump(kDoubleTapTimeout + const Duration(milliseconds: 50));
      await tester.tap(find.text('Squad Goals'));
      await tester.pumpAndSettle();
      expect(backend.windows, isEmpty);
      expect(location(), '/rooms/!grp:x');
      await finish(tester);
    });

    testWidgets('clicks on two different chats are two single clicks', (
      tester,
    ) async {
      await pumpChatList(tester);
      await tester.tap(find.text('Squad Goals'));
      await tester.pump();
      await tester.tap(find.text('Harrison Young'));
      await tester.pumpAndSettle();
      expect(backend.windows, isEmpty);
      expect(location(), '/rooms/!dm:x');
      await finish(tester);
    });

    testWidgets('does nothing special without chat windows', (tester) async {
      removeFakeChatWindows();
      await pumpChatList(tester);
      await tester.tap(find.text('Squad Goals'));
      await tester.pump();
      await tester.tap(find.text('Squad Goals'));
      await tester.pumpAndSettle();
      expect(backend.windows, isEmpty);
      expect(location(), '/rooms/!grp:x');
      await finish(tester);
    });
  });

  testWidgets('a click on a chat that has a window focuses the window', (
    tester,
  ) async {
    await pumpChatList(tester);
    ChatWindows.instance.open(
      const ChatWindowTarget.room('!grp:x'),
      title: 'Squad Goals',
    );
    await tester.tap(find.text('Squad Goals'));
    await tester.pumpAndSettle();
    expect(backend.windows.single.focusCount, 1);
    expect(location(), '/rooms');

    // Once the window is closed the chat opens here again.
    backend.windows.single.onCloseRequested();
    await tester.tap(find.text('Squad Goals'));
    await tester.pumpAndSettle();
    expect(location(), '/rooms/!grp:x');
    expect(backend.windows, hasLength(1));
    await finish(tester);
  });

  group('the selection menu', () {
    testWidgets('opens the selected chat in a new window', (tester) async {
      await pumpChatList(tester);
      await openMore(tester, 'Squad Goals');
      await tester.tap(find.text('Open in new window'));
      await tester.pumpAndSettle();

      expect(backend.windows.single.title, 'Squad Goals');
      expect(
        ChatWindows.instance.windows.keys.single,
        const ChatWindowTarget.room('!grp:x'),
      );
      // The selection ends and the main window stays where it was.
      expect(find.byTooltip('Clear selection'), findsNothing);
      expect(location(), '/rooms');
      await finish(tester);
    });

    testWidgets('opens a merged contact as the contact', (tester) async {
      addFakeChat(client, '!dm2:x', 'Harrison SMS', partner: '@sms:x');
      setMergedContacts(client, {
        'c1': {
          'name': 'Harrison',
          'rooms': ['!dm:x', '!dm2:x'],
          'send_via': '!dm:x',
          'updated': 1,
        },
      });
      await pumpChatList(tester);
      await openMore(tester, 'Harrison');
      await tester.tap(find.text('Open in new window'));
      await tester.pumpAndSettle();

      expect(backend.windows.single.title, 'Harrison');
      expect(
        ChatWindows.instance.windows.keys.single,
        const ChatWindowTarget.contact('c1'),
      );
      await finish(tester);
    });

    testWidgets('leaves the entry out for several chats', (tester) async {
      await pumpChatList(tester);
      await tester.longPress(chatRowAvatar('Squad Goals'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Harrison Young'));
      await tester.pumpAndSettle();
      await tester.tap(find.byTooltip('More'));
      await tester.pumpAndSettle();
      expect(find.text('Open in new window'), findsNothing);
      await finish(tester);
    });

    testWidgets('leaves the entry out without chat windows', (tester) async {
      removeFakeChatWindows();
      await pumpChatList(tester);
      await openMore(tester, 'Squad Goals');
      expect(find.text('Open in new window'), findsNothing);
      await finish(tester);
    });
  });
}
