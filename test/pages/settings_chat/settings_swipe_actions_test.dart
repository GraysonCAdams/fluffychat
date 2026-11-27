// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_swipe.dart';
import 'package:fluffychat/pages/settings_chat/settings_swipe_actions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    for (final setting in [
      AppSettings.chatListSwipe,
      AppSettings.chatListSwipeRight,
      AppSettings.chatListSwipeLeft,
    ]) {
      await AppSettings.store.remove(setting.key);
    }
  });

  Future<void> pump(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      const MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: SettingsSwipeActions(),
      ),
    );
    await tester.pumpAndSettle();
  }

  ListTile direction(WidgetTester tester, String title) => tester.widget(
    find.ancestor(of: find.text(title).last, matching: find.byType(ListTile)),
  );

  testWidgets('defaults: on, right marks read, left is low priority', (
    tester,
  ) async {
    await pump(tester);
    expect(AppSettings.chatListSwipe.value, isTrue);
    expect(ChatSwipeAction.right, ChatSwipeAction.markRead);
    expect(ChatSwipeAction.left, ChatSwipeAction.lowPriority);
    expect(find.text('Mark as read or unread'), findsWidgets);
    // The preview shows each direction past its threshold.
    expect(find.byType(SwipeRowFrame), findsNWidgets(2));
  });

  testWidgets('a direction picker lists every action and stores the pick', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Swipe left').last);
    await tester.pumpAndSettle();
    for (final label in [
      'Mark as read or unread',
      'Pin or unpin',
      'Mute or unmute',
      'Leave',
      'None',
    ]) {
      expect(find.text(label), findsWidgets, reason: label);
    }
    expect(find.text('Asks first. Others see that you left'), findsOneWidget);
    // The current action carries the check.
    expect(
      find.descendant(
        of: find.widgetWithText(ListTile, 'Low priority').last,
        matching: find.byIcon(Icons.check),
      ),
      findsOneWidget,
    );

    await tester.tap(find.text('Pin or unpin'));
    await tester.pumpAndSettle();
    expect(AppSettings.chatListSwipeLeft.value, 'pin');
    expect(
      (direction(tester, 'Swipe left').subtitle as Text).data,
      'Pin or unpin',
    );
    expect(
      swipeActionsSummary(L10n.of(tester.element(find.byType(Scaffold)))),
      'Right: Mark as read or unread. Left: Pin or unpin',
    );
  });

  testWidgets('the switch turns swiping off and disables the pickers', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Swipe on chats'));
    await tester.pumpAndSettle();
    expect(AppSettings.chatListSwipe.value, isFalse);
    expect(direction(tester, 'Swipe right').enabled, isFalse);
    expect(direction(tester, 'Swipe left').enabled, isFalse);
    expect(find.byType(SwipeRowFrame), findsNothing);
    expect(
      swipeActionsSummary(L10n.of(tester.element(find.byType(Scaffold)))),
      'Off',
    );
  });

  test('an unknown stored action reads as none', () {
    expect(ChatSwipeAction.named('archive'), ChatSwipeAction.none);
  });
}
