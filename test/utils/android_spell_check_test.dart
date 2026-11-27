// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/spell_check_ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _text = 'Ths is a smple tset';

class _FakeSpellCheckService implements SpellCheckService {
  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async => [
    if (text.contains('smple'))
      SuggestionSpan(
        TextRange(start: text.indexOf('smple'), end: text.indexOf('smple') + 5),
        const ['simple'],
      ),
  ];
}

void main() {
  testWidgets('tapping a misspelled word on Android leaves the corrections to '
      'the keyboard and keeps the long-press menu working', (tester) async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: TextField(
            controller: controller,
            spellCheckConfiguration: androidSpellCheckConfiguration(
              service: _FakeSpellCheckService(),
            ),
          ),
        ),
      ),
    );
    await tester.enterText(find.byType(TextField), _text);
    await tester.pumpAndSettle();
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    expect(state.findSuggestionSpanAtCursorIndex(11), isNotNull);

    final renderEditable = state.renderEditable;
    Offset at(int offset) => renderEditable.localToGlobal(
      renderEditable.getLocalRectForCaret(TextPosition(offset: offset)).center,
    );

    // Move the caret away first, as Flutter only shows the spelling toolbar
    // for a tap that changes the selection.
    await tester.tapAt(at(2));
    await tester.pumpAndSettle(const Duration(milliseconds: 400));
    await tester.tapAt(at(11));
    await tester.pumpAndSettle();
    expect(controller.selection, const TextSelection.collapsed(offset: 11));
    expect(find.byType(SpellCheckSuggestionsToolbar), findsNothing);
    expect(find.text('simple'), findsNothing);

    await tester.longPressAt(at(4));
    await tester.pumpAndSettle();
    expect(find.text('Copy'), findsOneWidget);

    debugDefaultTargetPlatformOverride = null;
  });
}
