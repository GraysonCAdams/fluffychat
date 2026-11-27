// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list_fakes.dart';

/// The gesture map of a chat list row outside selection mode: a finger's
/// long press on the row peeks at the chat, a long press on the avatar
/// selects it, and a tap on the avatar opens it.
void main() {
  late FakeChatListClient client;
  late FakeChatListRoom harrison;
  late FakeChatListRoom squad;
  late GoRouter router;
  late List<MethodCall> platformCalls;

  final card = find.byKey(const ValueKey('chat-peek-card'));
  final menu = find.byKey(const ValueKey('chat-peek-menu'));

  setUp(() async {
    client = await setUpFakeChatList('chat peek test');
    harrison = addFakeChat(
      client,
      '!imsg:x',
      'Harrison Young',
      partner: '@imessage_harrison:x',
      notificationCount: 1,
      lastMessageTime: DateTime(2026, 1, 5),
    );
    squad = addFakeChat(
      client,
      '!grp:x',
      'Squad Goals',
      lastMessageTime: DateTime(2026, 1, 2),
    );
    harrison.setMessages(
      ['Are we still on for Friday?', 'Yes! 7 at the usual place', 'Perfect'],
      partner: '@imessage_harrison:x',
      end: DateTime(2026, 1, 5, 18),
    );
    squad.setMessages(['Who is in for Saturday?', 'Me!']);
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<void> pump(WidgetTester tester) async {
    platformCalls = [];
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        platformCalls.add(call);
        return null;
      },
    );
    router = await pumpFakeChatList(tester, client);
  }

  Future<void> finish(WidgetTester tester) =>
      finishFakeChatList(tester, client);

  List<String> haptics() => [
    for (final call in platformCalls)
      if (call.method.startsWith('HapticFeedback.'))
        '${call.method}:${call.arguments}',
  ];

  Future<void> peek(WidgetTester tester, String name) async {
    await tester.longPress(find.text(name));
    await tester.pumpAndSettle();
  }

  testWidgets('a long press on the row peeks, with a long press haptic', (
    tester,
  ) async {
    await pump(tester);
    await peek(tester, 'Harrison Young');
    expect(card, findsOneWidget);
    expect(menu, findsOneWidget);
    expect(find.byType(ChatListSelectionBar), findsNothing);
    expect(find.byType(SelectedChatMark), findsNothing);
    expect(router.state.uri.path, '/rooms');
    // Android's long press effect, as the platform's own long press.
    expect(haptics(), ['HapticFeedback.vibrate:null']);
    await finish(tester);
  });

  testWidgets('the card shows the recent messages and the chat', (
    tester,
  ) async {
    await pump(tester);
    await peek(tester, 'Harrison Young');
    for (final body in [
      'Are we still on for Friday?',
      'Yes! 7 at the usual place',
      'Perfect',
    ]) {
      expect(
        find.descendant(of: card, matching: find.text(body)),
        findsOneWidget,
      );
    }
    expect(
      find.descendant(of: card, matching: find.text('Harrison Young')),
      findsOneWidget,
    );
    // The newest message is at the bottom.
    expect(
      tester.getTopLeft(find.text('Perfect').last).dy,
      greaterThan(
        tester.getTopLeft(find.text('Are we still on for Friday?')).dy,
      ),
    );
    await finish(tester);
  });

  testWidgets('peeking marks nothing read and a tap beside it closes it', (
    tester,
  ) async {
    await pump(tester);
    await peek(tester, 'Harrison Young');
    await tester.tapAt(const Offset(4, 4));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(router.state.uri.path, '/rooms');
    // The timeline was read, and no read marker or unread mark moved.
    expect(harrison.calls, ['timeline']);
    await finish(tester);
  });

  testWidgets('back closes the peek', (tester) async {
    await pump(tester);
    await peek(tester, 'Harrison Young');
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(router.state.uri.path, '/rooms');
    await finish(tester);
  });

  testWidgets('a tap on the card opens the chat', (tester) async {
    await pump(tester);
    await peek(tester, 'Harrison Young');
    await tester.tap(
      find.descendant(of: card, matching: find.text('Harrison Young')),
    );
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(router.state.uri.path, '/rooms/!imsg:x');
    await finish(tester);
  });

  testWidgets('the menu acts on the chat and closes the peek', (tester) async {
    await pump(tester);
    await peek(tester, 'Squad Goals');
    for (final label in ['Pin', 'Mute chat', 'Mark as unread', 'Leave']) {
      expect(
        find.descendant(of: menu, matching: find.text(label)),
        findsOneWidget,
      );
    }
    await tester.tap(find.descendant(of: menu, matching: find.text('Pin')));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(squad.calls, ['timeline', 'favourite:true']);

    // An unread chat offers to mark it read, which only the menu does.
    await peek(tester, 'Harrison Young');
    await tester.tap(
      find.descendant(of: menu, matching: find.text('Mark as read')),
    );
    await tester.pumpAndSettle();
    expect(harrison.calls, ['timeline', 'read']);
    await finish(tester);
  });

  testWidgets('sliding the finger onto an entry and lifting picks it', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Squad Goals')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);

    final mute = find.descendant(of: menu, matching: find.text('Mute chat'));
    final pin = find.descendant(of: menu, matching: find.text('Pin'));
    await gesture.moveTo(tester.getCenter(pin));
    await tester.pump();
    await gesture.moveTo(tester.getCenter(mute));
    await tester.pump();
    // A tick for each entry reached.
    expect(haptics().where((h) => h.endsWith('selectionClick')).length, 2);
    await gesture.up();
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(squad.calls, ['timeline', 'push:mentionsOnly']);
    await finish(tester);
  });

  testWidgets('lifting the finger without sliding leaves the peek open', (
    tester,
  ) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Squad Goals')),
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await tester.pumpAndSettle();
    await gesture.up();
    await tester.pumpAndSettle();
    expect(card, findsOneWidget);
    expect(squad.calls, ['timeline']);
    await finish(tester);
  });

  testWidgets('a long press on the avatar selects, and a tap opens', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(chatRowAvatar('Squad Goals'));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(find.byType(ChatListSelectionBar), findsOneWidget);
    expect(find.byType(SelectedChatMark), findsOneWidget);
    expect(haptics(), ['HapticFeedback.vibrate:null']);

    // While selecting, a long press on a row picks it as before.
    await tester.longPress(find.text('Harrison Young'));
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(find.byType(SelectedChatMark), findsNWidgets(2));

    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();
    await tester.tap(chatRowAvatar('Squad Goals'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatListSelectionBar), findsNothing);
    expect(router.state.uri.path, '/rooms/!grp:x');
    await finish(tester);
  });

  testWidgets('a tap on the avatar while selecting picks the chat', (
    tester,
  ) async {
    await pump(tester);
    await tester.longPress(chatRowAvatar('Squad Goals'));
    await tester.pumpAndSettle();
    await tester.tap(chatRowAvatar('Harrison Young'));
    await tester.pumpAndSettle();
    expect(find.byType(SelectedChatMark), findsNWidgets(2));
    expect(router.state.uri.path, '/rooms');
    await finish(tester);
  });

  testWidgets('a mouse long press selects instead of peeking', (tester) async {
    await pump(tester);
    final gesture = await tester.startGesture(
      tester.getCenter(find.text('Squad Goals')),
      kind: PointerDeviceKind.mouse,
    );
    await tester.pump(kLongPressTimeout + const Duration(milliseconds: 50));
    await gesture.up();
    await tester.pumpAndSettle();
    expect(card, findsNothing);
    expect(find.byType(ChatListSelectionBar), findsOneWidget);
    await finish(tester);
  });

  group('dragging the card down', () {
    final handle = find.byKey(const ValueKey('chat-peek-handle'));

    List<String> ticks() =>
        haptics().where((h) => h.endsWith('lightImpact')).toList();

    testWidgets('a short drag stretches the card and springs back', (
      tester,
    ) async {
      await pump(tester);
      await peek(tester, 'Harrison Young');
      final rest = tester.getRect(card);
      final gesture = await tester.startGesture(tester.getCenter(handle));
      for (var i = 0; i < 6; i++) {
        await gesture.moveBy(const Offset(0, 10));
        await tester.pump();
      }
      expect(tester.getRect(card).height, greaterThan(rest.height));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(tester.getRect(card), rest);
      expect(card, findsOneWidget);
      expect(router.state.uri.path, '/rooms');
      expect(ticks(), isEmpty);
      await finish(tester);
    });

    testWidgets('a long drag opens the chat, with a tick at the threshold', (
      tester,
    ) async {
      await pump(tester);
      await peek(tester, 'Harrison Young');
      // Anywhere on the card, once the drag goes down.
      final gesture = await tester.startGesture(
        tester.getCenter(
          find.descendant(of: card, matching: find.text('Harrison Young')),
        ),
      );
      for (var i = 0; i < 30; i++) {
        await gesture.moveBy(const Offset(0, 20));
        await tester.pump();
      }
      expect(ticks(), hasLength(1));
      // Still a peek until the finger lets go.
      expect(router.state.uri.path, '/rooms');
      expect(harrison.calls, ['timeline']);
      await gesture.up();
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(router.state.uri.path, '/rooms/!imsg:x');
      // The peek read the timeline and marked nothing read; the chat does
      // that once it is open.
      expect(harrison.calls, ['timeline']);
      await finish(tester);
    });

    testWidgets('a fling down opens the chat however short', (tester) async {
      await pump(tester);
      await peek(tester, 'Harrison Young');
      await tester.fling(handle, const Offset(0, 60), 1500);
      await tester.pumpAndSettle();
      expect(card, findsNothing);
      expect(router.state.uri.path, '/rooms/!imsg:x');
      await finish(tester);
    });

    testWidgets('a drag up does nothing', (tester) async {
      await pump(tester);
      await peek(tester, 'Harrison Young');
      final rest = tester.getRect(card);
      await tester.drag(handle, const Offset(0, -200));
      await tester.pumpAndSettle();
      expect(tester.getRect(card), rest);
      expect(router.state.uri.path, '/rooms');
      await finish(tester);
    });
  });
}
