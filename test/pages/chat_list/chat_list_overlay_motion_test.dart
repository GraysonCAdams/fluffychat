// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/scroll_to_top_button.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list_fakes.dart';

/// The back to top button and the unread chip float over the chat list and
/// come and go as it scrolls: each fades in and grows from 80% when it
/// appears, and fades and shrinks when it goes, unless animations are off.
void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('chat list overlay motion test');
    // Forty chats, newest first; the oldest five are unread, so the unread
    // chip shows while the top of the list is in view.
    for (var i = 0; i < 40; i++) {
      addFakeChat(
        client,
        '!c$i:x',
        'Chat $i',
        notificationCount: i >= 35 ? 1 : 0,
        lastMessageTime: DateTime(2026, 1, 1).subtract(Duration(hours: i)),
      );
    }
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<ScrollController> pump(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await pumpFakeChatList(tester, client);
    return tester
        .state<ChatListController>(find.byType(ChatList))
        .scrollController;
  }

  /// How opaque and how large [control] is drawn, from the fade and scale
  /// around it (scale 1 when it has none).
  ({double opacity, double scale}) shown(WidgetTester tester, Finder control) {
    final fade = tester.widget<FadeTransition>(
      find.ancestor(of: control, matching: find.byType(FadeTransition)).first,
    );
    final scales = find.ancestor(
      of: control,
      matching: find.byType(ScaleTransition),
    );
    return (
      opacity: fade.opacity.value,
      scale: scales.evaluate().isEmpty
          ? 1
          : tester.widget<ScaleTransition>(scales.first).scale.value,
    );
  }

  Finder button() => find.byIcon(Icons.arrow_upward);
  Finder chip() => find.byType(ActionChip);

  void expectMidway(({double opacity, double scale}) state) {
    expect(state.opacity, inExclusiveRange(0, 1));
    expect(state.scale, inExclusiveRange(0.8, 1));
  }

  testWidgets('back to top fades and grows in, and fades and shrinks out', (
    tester,
  ) async {
    final scroll = await pump(tester);
    expect(shown(tester, button()).opacity, 0);

    scroll.jumpTo(1300);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expectMidway(shown(tester, button()));
    // The button keeps its size while it moves, so nothing jumps.
    final size = tester.getSize(find.byType(ScrollToTopButton));
    await tester.pump(const Duration(milliseconds: 200));
    expect(shown(tester, button()), (opacity: 1.0, scale: 1.0));
    expect(tester.getSize(find.byType(ScrollToTopButton)), size);
    expect(button().hitTestable(), findsOneWidget);

    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expectMidway(shown(tester, button()));
    await tester.pump(const Duration(milliseconds: 150));
    expect(shown(tester, button()).opacity, 0);
    expect(button().hitTestable(), findsNothing);
    await finishFakeChatList(tester, client);
  });

  testWidgets('the unread chip fades and shrinks out, and back in', (
    tester,
  ) async {
    final scroll = await pump(tester);
    expect(shown(tester, chip()).opacity, 1);

    // At the bottom every unread chat is in view.
    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expectMidway(shown(tester, chip()));
    // The count stays on it as it goes.
    expect(find.text('5 unread'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 150));
    expect(chip().hitTestable(), findsNothing);
    expect(
      find.text('5 unread').evaluate().isEmpty ||
          shown(tester, chip()).opacity == 0,
      isTrue,
    );

    scroll.jumpTo(0);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    expectMidway(shown(tester, chip()));
    await tester.pump(const Duration(milliseconds: 200));
    expect(shown(tester, chip()), (opacity: 1.0, scale: 1.0));
    await finishFakeChatList(tester, client);
  });

  testWidgets('with animations off both show and hide at once', (tester) async {
    tester.platformDispatcher.accessibilityFeaturesTestValue =
        const FakeAccessibilityFeatures(disableAnimations: true);
    addTearDown(tester.platformDispatcher.clearAccessibilityFeaturesTestValue);
    final scroll = await pump(tester);

    scroll.jumpTo(scroll.position.maxScrollExtent);
    await tester.pump();
    expect(shown(tester, button()).opacity, 1);
    expect(chip().hitTestable(), findsNothing);

    scroll.jumpTo(0);
    await tester.pump();
    expect(shown(tester, button()).opacity, 0);
    expect(shown(tester, chip()), (opacity: 1.0, scale: 1.0));
    await finishFakeChatList(tester, client);
  });
}
