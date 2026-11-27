// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/input_bar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../chat_list/chat_list_fakes.dart';

/// When the composer suggests emoji after a colon: only with the setting
/// on, which it is not by default, and never for an emoticon.
void main() {
  late FakeChatListClient client;
  late InputBar bar;

  setUp(() async {
    client = await setUpFakeChatList('input bar suggestions');
    final room = addFakeChat(client, '!a:x', 'Drew', partner: '@drew:x');
    bar = InputBar(
      room: room,
      decoration: const InputDecoration(),
      suggestionEmojis: [
        for (final category in getDefaultEmojiLocale(const Locale('en')))
          ...category.emoji,
      ],
    );
  });

  tearDown(() => tearDownFakeChatList(client));

  List<Map<String, String?>> suggest(String text) => bar.getSuggestions(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );

  Iterable<String?> emoji(String text) =>
      suggest(text).where((s) => s['type'] == 'emoji').map((s) => s['emoji']);

  test('emoji suggestions are off by default', () {
    expect(AppSettings.emojiSuggestions.value, isFalse);
    expect(emoji('hi :smi'), isEmpty);
  });

  group('with emoji suggestions on', () {
    setUp(() => AppSettings.emojiSuggestions.setItem(true));
    tearDown(() => AppSettings.emojiSuggestions.setItem(false));

    test('two letters after the colon list emoji', () {
      expect(emoji('hi :smi'), isNotEmpty);
      expect(emoji(':dr'), contains('🤤'));
    });

    test('an emoticon or a single letter lists nothing', () {
      for (final text in [
        ':D',
        ':d',
        ':P',
        ':p',
        ':-P',
        ':-p',
        ':-D',
        ':o',
        'XD',
        'xD',
        ':s',
        'hi :x',
      ]) {
        expect(emoji(text), isEmpty, reason: text);
      }
    });

    test('links, times and code list nothing', () {
      for (final text in [
        'see https://exa',
        'at 10:30',
        'use `:smi',
        '```\n:smi',
      ]) {
        expect(emoji(text), isEmpty, reason: text);
      }
    });
  });

  test('mentions are suggested whatever the emoji setting', () {
    expect(suggest('hey @dr').where((s) => s['type'] == 'user'), isNotEmpty);
  });
}
