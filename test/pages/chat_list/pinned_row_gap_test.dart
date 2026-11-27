// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list_fakes.dart';

/// The space between the phone's header and the pinned row: 8 below the
/// header the first preview bubble starts, standing 19 above its avatar and
/// lying over the avatar's top. A pin without a bubble sits at the same
/// height, so the row does not move when a bubble comes or goes.
void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('pinned row gap test');
  });

  tearDown(() => tearDownFakeChatList(client));

  testWidgets('bubbles start 8 below the header, avatars 27', (tester) async {
    // A Pixel 10: 1080 by 2410 at density 2.625, with its 65 high status
    // bar (170 px, measured on the phone).
    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = const Size(1080, 2410);
    tester.view.padding = const FakeViewPadding(top: 170);
    addTearDown(tester.view.reset);
    for (var i = 0; i < 4; i++) {
      addFakeChat(
        client,
        '!p$i:x',
        'Pin $i',
        partner: '@p$i:x',
        // The second pin is unread, so it shows its message in a bubble.
        notificationCount: i == 1 ? 1 : 0,
        lastMessageTime: DateTime(2026, 1, 10 - i),
      ).pin();
    }
    addFakeChat(client, '!c:x', 'Chat', lastMessageTime: DateTime(2025));
    await pumpFakeChatList(tester, client);

    const statusBar = 170 / 2.625;
    final bar = tester.getRect(find.byType(AppBar));
    final avatars = find.byWidgetPredicate(
      (widget) => widget is SelectableAvatar && widget.size == 76,
    );
    final bubble = tester.getRect(
      find
          .ancestor(
            of: find.text('hello from Pin 1'),
            matching: find.byType(Container),
          )
          .first,
    );
    expect(bar.top, 0);
    expect(bar.bottom, closeTo(statusBar + 64, 0.01));
    expect(bubble.top - bar.bottom, closeTo(8, 0.01));
    // Every avatar, with a bubble or without, 27 below the header, and
    // the bubble over the top of its own.
    for (final avatar in avatars.evaluate()) {
      expect(
        tester.getRect(find.byWidget(avatar.widget)).top - bar.bottom,
        closeTo(27, 0.01),
      );
    }
    final withBubble = tester.getRect(avatars.at(1));
    expect(bubble.bottom, greaterThan(withBubble.top));
    // The title, centred in the bar's 64 below the status bar.
    final title = tester.getRect(find.text('All chats'));
    expect(title.center.dy, closeTo(statusBar + 32, 0.01));

    await finishFakeChatList(tester, client);
  });
}
