// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:fluffychat/utils/android_spell_check.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

const _text =
    'Given nephew thing I gather not relevnt, but no presure either way';

Map<String, Object> _span(String word, int attributes, [String? fix]) => {
  'startIndex': _text.indexOf(word),
  'endIndex': _text.indexOf(word) + word.length,
  'suggestions': [fix ?? word],
  'attributes': attributes,
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  final service = AndroidSpellCheckService.instance;
  const channel = MethodChannel(AndroidSpellCheckService.channelName);

  tearDown(() => messenger.setMockMethodCallHandler(channel, null));

  test('keeps typos and drops grammar suggestions', () async {
    late MethodCall sent;
    messenger.setMockMethodCallHandler(channel, (call) async {
      sent = call;
      return [
        // What a Pixel reports for the screenshot's message: grammar spans
        // over correctly spelled words, next to real typos.
        _span(
          'Given nephew thing',
          AndroidSpellCheckService.looksLikeGrammarError,
        ),
        _span('relevnt', AndroidSpellCheckService.looksLikeTypo, 'relevant'),
        _span(
          'gather not',
          AndroidSpellCheckService.looksLikeGrammarError |
              AndroidSpellCheckService.inTheDictionary,
        ),
        _span(
          'presure',
          AndroidSpellCheckService.looksLikeTypo |
              AndroidSpellCheckService.looksLikeGrammarError,
          'pressure',
        ),
        // Marked a typo yet in the user's dictionary: not underlined.
        _span(
          'nephew',
          AndroidSpellCheckService.looksLikeTypo |
              AndroidSpellCheckService.inTheDictionary,
        ),
      ];
    });

    final spans = await service.fetchSpellCheckSuggestions(
      const Locale('en', 'US'),
      _text,
    );

    expect(sent.method, 'check');
    expect(sent.arguments, ['en-US', _text]);
    expect(
      {
        for (final span in spans!)
          span.range.textInside(_text): span.suggestions,
      },
      {
        'relevnt': ['relevant'],
        'presure': ['pressure'],
      },
    );
  });

  test('keeps the last results while another check is running', () async {
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => throw PlatformException(code: 'pending'),
    );
    expect(
      await service.fetchSpellCheckSuggestions(const Locale('en'), _text),
      isNull,
    );
  });
}
