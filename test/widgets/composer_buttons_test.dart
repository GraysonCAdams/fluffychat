// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('the attach and emoji icons sit 16dp apart, 40dp targets', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ComposerLeadingButtons(
              textMessageOnly: false,
              attachmentPanelOpen: false,
              onAttach: () {},
              showEmojiButton: true,
              emojiPickerOpen: false,
              onEmoji: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final attach = find.byKey(const ValueKey('composer-attach'));
    final emoji = find.byKey(const ValueKey('composer-emoji'));
    Rect icon(Finder button) => tester.getRect(
      find.descendant(of: button, matching: find.byType(Icon)),
    );
    expect(
      icon(emoji).left - icon(attach).right,
      moreOrLessEquals(16, epsilon: 1),
    );
    for (final button in [attach, emoji]) {
      final size = tester.getSize(button);
      expect(size.width, greaterThanOrEqualTo(40));
      expect(size.height, greaterThanOrEqualTo(40));
    }
  });
}
