// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

@TestOn('windows')
library;

import 'dart:ui';

import 'package:fluffychat/utils/spell_check_ffi.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final service = WindowsSpellCheckService.instance;

  test('flags misspelled words with suggestions', () async {
    const text = 'Ths is a smple tset';
    final spans = await service.fetchSpellCheckSuggestions(
      const Locale('en', 'US'),
      text,
    );
    expect(spans, isNotNull);
    final flagged = {
      for (final span in spans!) span.range.textInside(text): span.suggestions,
    };
    expect(flagged.keys, containsAll(['Ths', 'smple', 'tset']));
    expect(flagged['smple'], contains('simple'));
  });

  test('leaves correct text alone', () async {
    final spans = await service.fetchSpellCheckSuggestions(
      const Locale('en'),
      'This is a simple test',
    );
    expect(spans, isEmpty);
  });
}
