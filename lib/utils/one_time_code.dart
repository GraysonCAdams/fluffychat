// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Words that say a number nearby is a one-time passcode.
final _keyword = RegExp(
  r'\b(?:codes?|otp|passcodes?|pass code|verification|verify|pin|'
  r'one[- ]time|2fa|is your)\b',
  caseSensitive: false,
);

/// A run of digits, its groups joined by single spaces or hyphens, so
/// "123 456", "555-123-4567" and "2024-05-12" are each one run.
final _digitRun = RegExp(r'\d+(?:[ -]\d+)*');

/// Text after a number that makes it an amount.
final _amountAfter = RegExp(
  r'^\s*(?:%|usd\b|eur\b|gbp\b|dollars?\b|euros?\b|pounds?\b|k\b|m\b)',
  caseSensitive: false,
);

/// How far a code may be from its keyword, in characters.
const _maxKeywordDistance = 40;

/// The one-time passcode in [text], digits only, or null if there is none.
///
/// A code is 4 to 8 digits, or two groups of 3 or 4 digits split by a space
/// or hyphen ("123 456"), within a few words of a keyword such as "code",
/// "OTP", "PIN", "verification" or "is your". Numbers that read as part of a
/// phone number, a date, a price or another longer number are skipped, and
/// so is a bare year unless the keyword introduces it ("code: 2024"). When
/// several numbers qualify, the one closest to a keyword wins.
String? findOneTimeCode(String text) {
  final keywords = _keyword.allMatches(text).toList();
  if (keywords.isEmpty) return null;

  String? best;
  var bestDistance = _maxKeywordDistance + 1;
  for (final run in _digitRun.allMatches(text)) {
    final code = _codeOfRun(text, run);
    if (code == null) continue;
    for (final keyword in keywords) {
      final distance = keyword.end <= run.start
          ? run.start - keyword.end
          : keyword.start >= run.end
          ? keyword.start - run.end
          : 0;
      if (distance >= bestDistance) continue;
      if (_isYear(code) && !_introduces(text, keyword, run)) continue;
      best = code;
      bestDistance = distance;
    }
  }
  return best;
}

/// The digits of [run] if its shape and surroundings fit a code.
String? _codeOfRun(String text, RegExpMatch run) {
  final groups = run[0]!.split(RegExp('[ -]'));
  final digits = groups.join();
  if (groups.length == 1) {
    if (digits.length < 4 || digits.length > 8) return null;
  } else if (groups.length != 2 ||
      groups.any((group) => group.length < 3 || group.length > 4)) {
    return null;
  }

  final before = run.start == 0 ? '' : text[run.start - 1];
  final after = run.end == text.length ? '' : text[run.end];
  // Glued to a word or symbol: "x1234", "$1234", "+1234", "(555)", or part
  // of a date, decimal or path: "12/05", "1,234", "1.5", "10:30".
  if (RegExp(r'[\w$€£¥+(/.,:]').hasMatch(before)) return null;
  if (RegExp(r'\w|%').hasMatch(after)) return null;
  if (RegExp(r'[/.,:]').hasMatch(after) &&
      run.end + 1 < text.length &&
      RegExp(r'\d').hasMatch(text[run.end + 1])) {
    return null;
  }
  // "G-123456" is a code; "12-123456" was already one run.
  if (before == '-' &&
      run.start >= 2 &&
      !RegExp(r'[A-Za-z]').hasMatch(text[run.start - 2])) {
    return null;
  }
  // The tail of a longer number: "(555) 123-4567", "$ 1234".
  final lead = text.substring(0, run.start).trimRight();
  if (lead.isNotEmpty && RegExp(r'[\d)$€£¥]$').hasMatch(lead)) return null;
  if (_amountAfter.hasMatch(text.substring(run.end))) return null;
  return digits;
}

bool _isYear(String code) {
  if (code.length != 4) return false;
  final value = int.parse(code);
  return value >= 1900 && value <= 2099;
}

/// Whether [keyword] directly introduces [run], as in "code 2024",
/// "PIN: 2024" or "code is 2024".
bool _introduces(String text, RegExpMatch keyword, RegExpMatch run) =>
    keyword.end <= run.start &&
    RegExp(
      r'^\s*(?:[:#-]\s*|is\s+)?$',
      caseSensitive: false,
    ).hasMatch(text.substring(keyword.end, run.start));
