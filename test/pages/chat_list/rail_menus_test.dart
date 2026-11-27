// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/navi_rail_item.dart';
import 'package:fluffychat/pages/settings_chat/hidden_rail_spaces_tile.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;
  late Map<String, FakeChatListRoom> rooms;
  late GoRouter router;

  setUp(() async {
    client = await setUpFakeChatList('rail menus test');
    await AppSettings.store.remove(AppSettings.railHiddenSpaces.key);
    rooms = {
      for (final (id, name, unread) in [
        ('!imsg_a:x', 'Harrison Young', 2),
        ('!imsg_b:x', 'Maya Chen', 0),
        ('!xbox_a:x', 'Gamer Tag', 0),
        ('!other:x', 'Squad Goals', 1),
      ])
        id: addFakeChat(
          client,
          id,
          name,
          partner: '@p_${id.substring(1, 7)}:x',
          notificationCount: unread,
        ),
    };
    addFakeSpace(client, '!imsg:x', 'iMessage', ['!imsg_a:x', '!imsg_b:x']);
    addFakeSpace(client, '!xbox:x', 'Xbox', ['!xbox_a:x']);
  });

  tearDown(() => tearDownFakeChatList(client));

  /// A desktop window, wide enough for the rail.
  Future<void> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 800);
    addTearDown(tester.view.reset);
    router = await pumpFakeChatList(tester, client);
  }

  Finder tile(String tooltip) => find.ancestor(
    of: find.byTooltip(tooltip),
    matching: find.byType(NaviRailItem),
  );

  Future<void> rightClick(WidgetTester tester, Finder finder) async {
    await tester.tap(
      finder,
      buttons: kSecondaryButton,
      kind: PointerDeviceKind.mouse,
    );
    await tester.pumpAndSettle();
  }

  Finder item(String label) => find.descendant(
    of: find.byWidgetPredicate((w) => w is PopupMenuItem),
    matching: find.text(label),
  );

  bool enabled(WidgetTester tester, String label) => tester
      .widget<PopupMenuItem>(
        find.ancestor(
          of: find.text(label),
          matching: find.byWidgetPredicate((w) => w is PopupMenuItem),
        ),
      )
      .enabled;

  String location() =>
      router.routerDelegate.currentConfiguration.uri.toString();

  testWidgets('the All chats tile menu', (tester) async {
    await pump(tester);
    await rightClick(tester, tile('Chats'));
    for (final label in [
      'All chats',
      'Mark all as read',
      'Snooze notifications',
      'Seam',
      'Settings',
      'Notification settings',
      'Appearance',
      'Archive',
    ]) {
      expect(item(label), findsOneWidget, reason: label);
    }
    expect(find.byType(PopupMenuDivider), findsOneWidget);
    expect(enabled(tester, 'All chats'), isFalse, reason: 'a label');
    expect(enabled(tester, 'Mark all as read'), isTrue);

    await tester.tap(item('Mark all as read'));
    await tester.pumpAndSettle();
    expect(rooms['!imsg_a:x']!.calls, ['read']);
    expect(rooms['!other:x']!.calls, ['read']);
    expect(rooms['!imsg_b:x']!.calls, isEmpty);
    await finishFakeChatList(tester, client);
  });

  testWidgets('the All chats tile menu opens the Seam pages', (tester) async {
    await pump(tester);
    await rightClick(tester, tile('Chats'));
    await tester.tap(item('Archive'));
    await tester.pumpAndSettle();
    expect(location(), '/rooms/archive');
    await finishFakeChatList(tester, client);
  });

  testWidgets('a long press on a network opens its menu', (tester) async {
    await pump(tester);
    await tester.longPress(tile('iMessage'));
    await tester.pumpAndSettle();
    for (final label in [
      'Mark all as read',
      'Mute all chats',
      'Network settings',
      'Hide from rail',
    ]) {
      expect(item(label), findsOneWidget, reason: label);
    }
    // Its name heads the menu.
    expect(
      find.descendant(
        of: find.byWidgetPredicate((w) => w is PopupMenuItem),
        matching: find.text('iMessage'),
      ),
      findsOneWidget,
    );
    await tester.tap(item('Mark all as read'));
    await tester.pumpAndSettle();
    expect(rooms['!imsg_a:x']!.calls, ['read']);
    expect(rooms['!other:x']!.calls, isEmpty, reason: 'not in the space');
    await finishFakeChatList(tester, client);
  });

  testWidgets('Mark all as read is shown disabled with nothing unread', (
    tester,
  ) async {
    await pump(tester);
    await rightClick(tester, tile('Xbox'));
    expect(item('Mark all as read'), findsOneWidget);
    expect(enabled(tester, 'Mark all as read'), isFalse);
    await finishFakeChatList(tester, client);
  });

  testWidgets('Mute all chats mutes the network\'s chats only', (tester) async {
    await pump(tester);
    await rightClick(tester, tile('iMessage'));
    await tester.tap(item('Mute all chats'));
    await tester.pumpAndSettle();
    expect(rooms['!imsg_a:x']!.calls, ['push:mentionsOnly']);
    expect(rooms['!imsg_b:x']!.calls, ['push:mentionsOnly']);
    expect(rooms['!other:x']!.calls, isEmpty);
    await finishFakeChatList(tester, client);
  });

  testWidgets('Network settings opens the space\'s details', (tester) async {
    await pump(tester);
    await rightClick(tester, tile('iMessage'));
    await tester.tap(item('Network settings'));
    await tester.pumpAndSettle();
    // Pushed over the chat list.
    expect(find.text('details of !imsg:x'), findsOneWidget);
    await finishFakeChatList(tester, client);
  });

  testWidgets('Hide from rail takes the tile off and keeps it off', (
    tester,
  ) async {
    await pump(tester);
    await rightClick(tester, tile('iMessage'));
    await tester.tap(item('Hide from rail'));
    await tester.pumpAndSettle();
    expect(tile('iMessage'), findsNothing);
    expect(tile('Xbox'), findsOneWidget);
    expect(AppSettings.railHiddenSpaces.value, ['!imsg:x']);
    await finishFakeChatList(tester, client);
  });

  testWidgets('chat settings list the hidden networks and show them again', (
    tester,
  ) async {
    await AppSettings.railHiddenSpaces.setItem(['!imsg:x']);
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: const MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(body: HiddenRailSpacesTile()),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Hidden from the rail'), findsOneWidget);
    expect(find.text('iMessage'), findsOneWidget);
    await tester.tap(find.text('Hidden from the rail'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(TextButton, 'Show'));
    await tester.pumpAndSettle();
    expect(AppSettings.railHiddenSpaces.value, isEmpty);
    // With nothing hidden the row is gone.
    expect(find.text('Hidden from the rail'), findsNothing);
  });
}
