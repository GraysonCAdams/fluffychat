// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  testWidgets('a composer icon button is a 48dp target, its icon 12dp in', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: ComposerIconButton(
              key: const ValueKey('button'),
              tooltip: 'Emojis',
              icon: const Icon(Icons.add_reaction_outlined),
              onPressed: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final slot = tester.getRect(find.byKey(const ValueKey('button')));
    final button = tester.getRect(find.byType(IconButton));
    final icon = tester.getRect(find.byType(Icon));
    expect(button.size, const Size.square(48));
    // As tall as one line of the composer, so in a row aligned to its end
    // the icon sits level with the last line.
    expect(slot.size, const Size(48, ChatInputRow.height));
    expect(icon.left - slot.left, 12);
    expect(slot.right - icon.right, 12);
    expect(icon.center.dy, slot.center.dy);
  });
}
