// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_swipe.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/merged_contacts/fake_rooms.dart' show setMergedContacts;
import 'chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;
  late Map<String, FakeChatListRoom> rooms;
  late List<String> haptics;

  setUp(() async {
    client = await setUpFakeChatList('chat list swipe test');
    // The settings store outlives each test, so start from the defaults.
    for (final setting in [
      AppSettings.chatListSwipe,
      AppSettings.chatListSwipeRight,
      AppSettings.chatListSwipeLeft,
    ]) {
      await AppSettings.store.remove(setting.key);
    }
    rooms = {
      for (final (id, name, time) in [
        ('!harrison:x', 'Harrison Young', 5),
        ('!squad:x', 'Squad Goals', 4),
        ('!sam:x', 'Sam Lee', 3),
      ])
        id: addFakeChat(
          client,
          id,
          name,
          partner: '@p$time:x',
          lastMessageTime: DateTime(2026, 1, time),
        ),
    };
    haptics = [];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'HapticFeedback.vibrate') {
            haptics.add('${call.arguments}');
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    swipeActionsChanged.value++;
    tearDownFakeChatList(client);
  });

  Future<void> pump(WidgetTester tester) => pumpFakeChatList(tester, client);
  Future<void> finish(WidgetTester tester) =>
      finishFakeChatList(tester, client);

  Future<void> swipe(
    WidgetTester tester,
    String name,
    double dx, {
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    await tester.drag(find.text(name), Offset(dx, 0), kind: kind);
    await tester.pumpAndSettle();
  }

  ChatListController controller(WidgetTester tester) =>
      tester.state<ChatListController>(find.byType(ChatList));

  /// The colour of the background a swiped row shows, if any.
  Color? swipeBackground(WidgetTester tester, String name) {
    final row = find.ancestor(
      of: find.text(name),
      matching: find.byType(ChatListSwipe),
    );
    final boxes = tester.widgetList<DecoratedBox>(
      find.descendant(of: row, matching: find.byType(DecoratedBox)),
    );
    return boxes
        .map((box) => (box.decoration as BoxDecoration?)?.color)
        .whereType<Color>()
        .firstOrNull;
  }

  test('the threshold is 30% of the row, at least 96', () {
    expect(ChatListSwipe.thresholdFor(800), 240);
    expect(ChatListSwipe.thresholdFor(200), 96);
  });

  testWidgets('a right swipe past the threshold marks the chat unread', (
    tester,
  ) async {
    await pump(tester);
    // The list is 800 wide, so the threshold is 240: 200 is short of it.
    await swipe(tester, 'Harrison Young', 200);
    expect(rooms['!harrison:x']!.calls, isEmpty);
    await swipe(tester, 'Harrison Young', 300);
    expect(rooms['!harrison:x']!.calls, ['unread:true']);
    expect(rooms['!squad:x']!.calls, isEmpty);
    await finish(tester);
  });

  testWidgets('an unread chat swiped right is marked read', (tester) async {
    rooms['!squad:x']!.notificationCount = 2;
    await pump(tester);
    await swipe(tester, 'Squad Goals', 300);
    expect(rooms['!squad:x']!.calls, ['read']);
    await finish(tester);
  });

  testWidgets('a left swipe makes the chat low priority, with undo', (
    tester,
  ) async {
    await pump(tester);
    await swipe(tester, 'Sam Lee', -300);
    expect(rooms['!sam:x']!.calls, ['lowPriority:true']);
    expect(find.text('Sam Lee moved to low priority'), findsOneWidget);
    await tester.tap(find.text('Undo'));
    await tester.pumpAndSettle();
    expect(rooms['!sam:x']!.calls, ['lowPriority:true', 'lowPriority:false']);
    await finish(tester);
  });

  testWidgets('the background is neutral below the threshold and takes '
      'the action colours past it, with a haptic each way', (tester) async {
    await pump(tester);
    final scheme = Theme.of(
      tester.element(find.byType(ChatListSwipe).first),
    ).colorScheme;
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Harrison Young')),
    );
    await gesture.moveBy(const Offset(40, 0));
    await gesture.moveBy(const Offset(110, 0));
    await tester.pump();
    expect(
      swipeBackground(tester, 'Harrison Young'),
      scheme.surfaceContainerHighest,
    );
    expect(haptics, isEmpty);

    await gesture.moveBy(const Offset(150, 0));
    await tester.pump();
    expect(swipeBackground(tester, 'Harrison Young'), scheme.primaryContainer);
    expect(haptics, ['HapticFeedbackType.lightImpact']);

    // Back under the threshold: neutral again, another tick, and letting
    // go does nothing.
    await gesture.moveBy(const Offset(-150, 0));
    await tester.pump();
    expect(
      swipeBackground(tester, 'Harrison Young'),
      scheme.surfaceContainerHighest,
    );
    expect(haptics, hasLength(2));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(rooms['!harrison:x']!.calls, isEmpty);
    // The row is back in place.
    final frame = find.ancestor(
      of: find.text('Harrison Young'),
      matching: find.byType(SwipeRowFrame),
    );
    expect(tester.widget<SwipeRowFrame>(frame).offset, 0);
    await finish(tester);
  });

  testWidgets('a mouse drag does nothing', (tester) async {
    await pump(tester);
    await swipe(tester, 'Harrison Young', 300, kind: PointerDeviceKind.mouse);
    await swipe(tester, 'Sam Lee', -300, kind: PointerDeviceKind.mouse);
    expect(rooms['!harrison:x']!.calls, isEmpty);
    expect(rooms['!sam:x']!.calls, isEmpty);
    await finish(tester);
  });

  testWidgets('a swipe from the back gesture edge is left alone', (
    tester,
  ) async {
    tester.view.systemGestureInsets = FakeViewPadding(
      left: 30 * tester.view.devicePixelRatio,
      right: 30 * tester.view.devicePixelRatio,
    );
    addTearDown(tester.view.resetSystemGestureInsets);
    await pump(tester);
    final y = tester.getCenter(find.text('Harrison Young')).dy;
    await tester.dragFrom(Offset(10, y), const Offset(400, 0));
    await tester.pumpAndSettle();
    final samY = tester.getCenter(find.text('Sam Lee')).dy;
    await tester.dragFrom(Offset(790, samY), const Offset(-400, 0));
    await tester.pumpAndSettle();
    expect(rooms['!harrison:x']!.calls, isEmpty);
    expect(rooms['!sam:x']!.calls, isEmpty);

    // Starting inside the row still swipes.
    await tester.dragFrom(Offset(60, y), const Offset(400, 0));
    await tester.pumpAndSettle();
    expect(rooms['!harrison:x']!.calls, ['unread:true']);
    await finish(tester);
  });

  testWidgets('rows do not swipe while chats are selected', (tester) async {
    await pump(tester);
    await tester.longPress(find.text('Squad Goals'));
    await tester.pumpAndSettle();
    await swipe(tester, 'Harrison Young', 300);
    await swipe(tester, 'Sam Lee', -300);
    expect(rooms['!harrison:x']!.calls, isEmpty);
    expect(rooms['!sam:x']!.calls, isEmpty);
    await finish(tester);
  });

  testWidgets('the switch turns swiping off', (tester) async {
    await AppSettings.chatListSwipe.setItem(false);
    await pump(tester);
    await swipe(tester, 'Harrison Young', 300);
    expect(rooms['!harrison:x']!.calls, isEmpty);
    await finish(tester);
  });

  testWidgets('invites and spaces do not swipe', (tester) async {
    final invite = addFakeChat(
      client,
      '!invite:x',
      'Invited Chat',
      membership: Membership.invite,
    );
    final space = addFakeSpace(client, '!space:x', 'A Space', []);
    await pump(tester);
    final list = controller(tester);
    expect(chatSwipeActions(list, invite), (right: null, left: null));
    expect(chatSwipeActions(list, space), (right: null, left: null));
    expect(chatSwipeActions(list, rooms['!sam:x']!).right, isNotNull);
    await finish(tester);
  });

  testWidgets('each direction runs the action picked for it', (tester) async {
    await AppSettings.chatListSwipeRight.setItem('pin');
    await AppSettings.chatListSwipeLeft.setItem('mute');
    await pump(tester);
    await swipe(tester, 'Harrison Young', 300);
    await swipe(tester, 'Sam Lee', -300);
    expect(rooms['!harrison:x']!.calls, ['favourite:true']);
    expect(rooms['!sam:x']!.calls, ['push:mentionsOnly']);
    await finish(tester);
  });

  testWidgets('None keeps the row still that way', (tester) async {
    await AppSettings.chatListSwipeLeft.setItem('none');
    await pump(tester);
    final start = tester.getTopLeft(find.text('Sam Lee'));
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Sam Lee')),
    );
    await gesture.moveBy(const Offset(-40, 0));
    await gesture.moveBy(const Offset(-260, 0));
    await tester.pump();
    expect(tester.getTopLeft(find.text('Sam Lee')), start);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(rooms['!sam:x']!.calls, isEmpty);
    await finish(tester);
  });

  testWidgets('leave asks first, and the row springs back on cancel', (
    tester,
  ) async {
    await AppSettings.chatListSwipeLeft.setItem('leave');
    await pump(tester);
    final start = tester.getTopLeft(find.text('Sam Lee'));
    await swipe(tester, 'Sam Lee', -300);
    expect(find.text('Are you sure?'), findsOneWidget);
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(rooms['!sam:x']!.calls, isEmpty);
    expect(tester.getTopLeft(find.text('Sam Lee')), start);

    await swipe(tester, 'Sam Lee', -300);
    await tester.tap(find.text('Leave').last);
    await tester.pumpAndSettle();
    expect(rooms['!sam:x']!.calls, ['leave']);
    await finish(tester);
  });

  testWidgets('a merged conversation acts on all of its rooms', (tester) async {
    setMergedContacts(client, {
      'c_1': {
        'rooms': ['!harrison:x', '!squad:x'],
        'send_via': '!harrison:x',
        'updated': 1,
      },
    });
    await pump(tester);
    expect(find.text('Squad Goals'), findsNothing);
    await swipe(tester, 'Harrison Young', -300);
    expect(rooms['!harrison:x']!.calls, ['lowPriority:true']);
    expect(rooms['!squad:x']!.calls, ['lowPriority:true']);
    await finish(tester);
  });

  testWidgets('the actions are screen reader custom actions', (tester) async {
    final semantics = tester.ensureSemantics();
    await pump(tester);
    final node = tester.getSemantics(find.text('Harrison Young'));
    final ids = node.getSemanticsData().customSemanticsActionIds ?? [];
    int id(String label) => CustomSemanticsAction.getIdentifier(
      CustomSemanticsAction(label: label),
    );
    expect(ids, containsAll([id('Mark as unread'), id('Low priority')]));

    node.owner!.performAction(
      node.id,
      SemanticsAction.customAction,
      id('Low priority'),
    );
    await tester.pumpAndSettle();
    expect(rooms['!harrison:x']!.calls, ['lowPriority:true']);
    semantics.dispose();
    await finish(tester);
  });
}
