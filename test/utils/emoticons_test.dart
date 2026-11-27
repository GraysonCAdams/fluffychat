// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/emoticons.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    // The settings outlive a test, and one test turns this off.
    await AppSettings.convertEmoticons.setItem(true);
  });

  /// Types [text] into [formatter] one character at a time, as a keyboard
  /// does, and returns what the field holds.
  TextEditingValue type(
    EmoticonFormatter formatter,
    String text, {
    TextEditingValue start = TextEditingValue.empty,
  }) {
    var value = start;
    for (final char in text.split('')) {
      final cursor = value.selection.baseOffset < 0
          ? value.text.length
          : value.selection.baseOffset;
      final next = TextEditingValue(
        text: value.text.replaceRange(cursor, cursor, char),
        selection: TextSelection.collapsed(offset: cursor + 1),
      );
      value = formatter.formatEditUpdate(value, next);
    }
    return value;
  }

  TextEditingValue backspace(
    EmoticonFormatter formatter,
    TextEditingValue value,
  ) {
    final cursor = value.selection.baseOffset;
    return formatter.formatEditUpdate(
      value,
      TextEditingValue(
        text: value.text.replaceRange(cursor - 1, cursor, ''),
        selection: TextSelection.collapsed(offset: cursor - 1),
      ),
    );
  }

  test('each emoticon turns into its emoji when a space follows', () {
    for (final MapEntry(key: emoticon, value: emoji) in emoticons.entries) {
      final value = type(EmoticonFormatter(), 'hi $emoticon ');
      expect(value.text, 'hi $emoji ', reason: emoticon);
      expect(value.selection.baseOffset, value.text.length, reason: emoticon);
    }
    expect(emoticons[':)'], '🙂');
    expect(emoticons['<3'], '❤️');
    expect(emoticons[':-/'], '😕');
    expect(emoticons.containsKey('B)'), isFalse);
  });

  test('a line break converts too, and the cursor stays where it was', () {
    final formatter = EmoticonFormatter();
    final value = type(
      formatter,
      ':D\n',
      start: const TextEditingValue(
        text: 'x',
        selection: TextSelection.collapsed(offset: 0),
      ),
    );
    expect(value.text, '😄\nx');
    expect(value.selection.baseOffset, '😄\n'.length);
  });

  test('links, times, code and emoticons inside words stay as typed', () {
    for (final text in [
      'see https://example.org ',
      'at 10:30 ',
      'a:D ',
      'x:) ',
      'use `:) ',
      'in ```\n:) ',
      'ok:( ',
      '(option B) ',
    ]) {
      expect(type(EmoticonFormatter(), text).text, text, reason: text);
    }
    // After the code span closes, emoticons convert again.
    expect(type(EmoticonFormatter(), '`a` :) ').text, '`a` 🙂 ');
  });

  test('backspace right after a conversion puts the emoticon back', () {
    final formatter = EmoticonFormatter();
    var value = type(formatter, 'hi :) ');
    expect(value.text, 'hi 🙂 ');
    value = backspace(formatter, value);
    expect(value.text, 'hi :)');
    expect(value.selection.baseOffset, 'hi :)'.length);
    // A space now keeps the emoticon the user chose to keep.
    value = type(formatter, ' ', start: value);
    expect(value.text, 'hi :) ');
    // A later one converts as usual.
    value = type(formatter, ';) ', start: value);
    expect(value.text, 'hi :) 😉 ');
  });

  test('a message ending in an emoticon converts when it is sent', () {
    expect(convertTrailingEmoticon('see you <3'), 'see you ❤️');
    expect(convertTrailingEmoticon(':P'), '😛');
    expect(convertTrailingEmoticon('at 10:30'), 'at 10:30');
    expect(convertTrailingEmoticon('`:)'), '`:)');
  });

  test('with the setting off nothing converts', () async {
    await AppSettings.convertEmoticons.setItem(false);
    expect(type(EmoticonFormatter(), 'hi :) ').text, 'hi :) ');
  });

  testWidgets('a text field with the formatter converts as the user types', (
    tester,
  ) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);
    final formatter = EmoticonFormatter();
    await tester.pumpWidget(
      MaterialApp(
        home: Material(
          child: TextField(
            controller: controller,
            inputFormatters: [formatter],
          ),
        ),
      ),
    );
    for (final text in ['o', 'ok', 'ok ', 'ok :', 'ok :)', 'ok :) ']) {
      await tester.enterText(find.byType(TextField), text);
    }
    expect(controller.text, 'ok 🙂 ');
    await tester.enterText(find.byType(TextField), 'ok 🙂');
    expect(controller.text, 'ok :)');
  });
}
