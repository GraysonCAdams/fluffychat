// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Turns text emoticons such as `:-)` and `<3` into emoji as they are
/// typed (see [EmoticonFormatter]) and when a message is sent (see
/// [convertTrailingEmoticon]), while the setting for it is on.
library;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/services.dart';

/// The emoticons converted, and their emoji. `B)` is left out: it is also
/// how a list item or an aside in brackets ends, as in "option B)".
const emoticons = <String, String>{
  ':)': '🙂',
  ':-)': '🙂',
  ':(': '🙁',
  ':-(': '🙁',
  ';)': '😉',
  ';-)': '😉',
  ':D': '😄',
  ':-D': '😄',
  'XD': '😆',
  'xD': '😆',
  ':P': '😛',
  ':p': '😛',
  ':-P': '😛',
  ':-p': '😛',
  ':O': '😮',
  ':o': '😮',
  ':-O': '😮',
  ':-o': '😮',
  ":'(": '😢',
  '<3': '❤️',
  '</3': '💔',
  ':|': '😐',
  ':-|': '😐',
  ':/': '😕',
  ':-/': '😕',
  ':*': '😘',
  ':-*': '😘',
  '^^': '😊',
  'o/': '👋',
};

/// Whether [offset] in [text] lies inside Markdown code: an inline code
/// span or a fenced block, which keep what is typed in them as it is.
bool _inCode(String text, int offset) {
  final before = text.substring(0, offset);
  final fences = '```'.allMatches(before).length;
  if (fences.isOdd) return true;
  final ticks = before.replaceAll('```', '').split('`').length - 1;
  return ticks.isOdd;
}

/// The emoticon that ends at [end] in [text], as a whole word: it starts
/// the text or follows whitespace, so a link (`https://`), a time (`10:30`)
/// or a word with an emoticon in it (`a:D`) is left alone. Returns where it
/// starts and its emoji, or null.
({int start, String emoji})? _emoticonEndingAt(String text, int end) {
  var start = end;
  while (start > 0 && !_isSpace(text.codeUnitAt(start - 1))) {
    start--;
  }
  final emoji = emoticons[text.substring(start, end)];
  if (emoji == null || _inCode(text, start)) return null;
  return (start: start, emoji: emoji);
}

bool _isSpace(int unit) =>
    unit == 0x20 || unit == 0x0A || unit == 0x09 || unit == 0x0D;

/// [text] with an emoticon at its very end replaced, for a message sent
/// without a space after its last emoticon.
String convertTrailingEmoticon(String text) {
  final found = _emoticonEndingAt(text, text.length);
  if (found == null) return text;
  return text.replaceRange(found.start, text.length, found.emoji);
}

/// Converts an emoticon as a space or line break is typed after it, with
/// the cursor kept after that space. Backspace right after a conversion
/// puts the emoticon back, and that one is not converted again until the
/// text changes elsewhere. Does nothing while the setting is off.
class EmoticonFormatter extends TextInputFormatter {
  /// The text as it was converted, and the text the user had typed, for
  /// undoing with Backspace.
  TextEditingValue? _converted;
  TextEditingValue? _typed;

  /// An emoticon the user undid, by where it starts, which stays as typed.
  int? _kept;

  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    if (!AppSettings.convertEmoticons.value) return newValue;
    final converted = _converted;
    final typed = _typed;
    _converted = _typed = null;

    // Backspace right after a conversion: the emoticon comes back as typed,
    // without the space that converted it.
    if (converted != null &&
        typed != null &&
        oldValue.text == converted.text &&
        _isBackspace(oldValue, newValue)) {
      final cursor = typed.selection.baseOffset - 1;
      _kept = _emoticonEndingAt(typed.text, cursor)?.start;
      return TextEditingValue(
        text: typed.text.replaceRange(cursor, cursor + 1, ''),
        selection: TextSelection.collapsed(offset: cursor),
      );
    }

    final cursor = newValue.selection.baseOffset;
    final inserted = newValue.text.length - oldValue.text.length;
    if (inserted != 1 ||
        !newValue.selection.isCollapsed ||
        cursor < 1 ||
        !_isSpace(newValue.text.codeUnitAt(cursor - 1)) ||
        oldValue.text != newValue.text.replaceRange(cursor - 1, cursor, '')) {
      if (inserted != 1) _kept = null;
      return newValue;
    }
    final found = _emoticonEndingAt(newValue.text, cursor - 1);
    if (found == null) return newValue;
    if (found.start == _kept) return newValue;
    _kept = null;
    final text = newValue.text.replaceRange(
      found.start,
      cursor - 1,
      found.emoji,
    );
    final result = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(
        offset: cursor - (cursor - 1 - found.start) + found.emoji.length,
      ),
    );
    _converted = result;
    _typed = newValue;
    return result;
  }

  /// Whether [newValue] is [oldValue] with the character before its cursor
  /// deleted.
  static bool _isBackspace(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    final cursor = oldValue.selection.baseOffset;
    if (!oldValue.selection.isCollapsed || cursor < 1) return false;
    return newValue.text.length == oldValue.text.length - 1 &&
        newValue.selection.baseOffset == cursor - 1 &&
        newValue.text == oldValue.text.replaceRange(cursor - 1, cursor, '');
  }
}
