// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list_fakes.dart';

/// The space between the phone's header and the pinned row: the header is
/// Material's small top app bar, 64 below the status bar with the title
/// centred in it, then the 30 band for the preview bubbles over the pins,
/// then the pins.
void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('pinned row gap test');
  });

  tearDown(() => tearDownFakeChatList(client));

  testWidgets('the pinned row sits 37 below a 64 high header', (tester) async {
    // A Pixel 10: 1080 by 2410 at density 2.625, with a 52 high status bar.
    tester.view.devicePixelRatio = 2.625;
    tester.view.physicalSize = const Size(1080, 2410);
    tester.view.padding = const FakeViewPadding(top: 137);
    addTearDown(tester.view.reset);
    for (var i = 0; i < 4; i++) {
      addFakeChat(
        client,
        '!p$i:x',
        'Pin $i',
        partner: '@p$i:x',
        lastMessageTime: DateTime(2026, 1, 10 - i),
      ).pin();
    }
    addFakeChat(client, '!c:x', 'Chat', lastMessageTime: DateTime(2025));
    await pumpFakeChatList(tester, client);

    const statusBar = 137 / 2.625;
    final bar = tester.getRect(find.byType(AppBar));
    final pin = tester.getRect(
      find
          .byWidgetPredicate(
            (widget) => widget is SelectableAvatar && widget.size == 76,
          )
          .first,
    );
    expect(bar.top, 0);
    expect(bar.bottom, closeTo(statusBar + 64, 0.01));
    expect(pin.top - bar.bottom, closeTo(37, 0.01));
    // The title, centred in the bar's 64 below the status bar, ends 18 above
    // the bubble band, which starts where the bar ends.
    final title = tester.getRect(find.text('All chats'));
    expect(title.center.dy, closeTo(statusBar + 32, 0.01));
    expect(bar.bottom - title.bottom, closeTo(18, 0.01));

    await finishFakeChatList(tester, client);
  });
}
