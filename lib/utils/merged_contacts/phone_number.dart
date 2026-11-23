// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Phone number normalisation for merged contacts.
///
/// Bridges format the same number in many ways (`+14045551234`,
/// `tel:+1404...`, `(404) 555-1234`, `1 404 555 1234`, or escaped as
/// `tel=3a+1404...` inside a ghost user ID). Every number goes through
/// [normalizePhone] before it is compared or stored, so two chats with the
/// same person match on exact string equality of the E.164 form.
///
/// This is deliberately not a full libphonenumber port: it only needs to
/// recognise the formats bridges actually emit and to reject things that are
/// not phone numbers (short codes, alphanumeric senders).
library;

final _escapedByte = RegExp(r'=([0-9a-fA-F]{2})');

/// A `tel` prefix, either plain (`tel:`) or with the colon still in its
/// bridge-escaped form when the `=` was lost (`tel3a+1...`, `3a+1...`).
final _telPrefix = RegExp(r'^(?:tel:|(?:tel)?3a(?=\+))', caseSensitive: false);

/// Everything from an extension marker to the end: a URI parameter
/// (`;ext=12`, `;phone-context=...`) or a written extension (`x123`,
/// `ext. 123`, `extension 123`).
final _extension = RegExp(
  r'(?:;|(?:extension|ext\.?|x)\s*\d).*$',
  caseSensitive: false,
);

final _nonDigit = RegExp(r'\D');
final _e164 = RegExp(r'^\+\d{8,15}$');

/// Regions sharing the North American Numbering Plan (country code 1), where
/// a number without a `+` can be completed from its digit count alone.
const _nanpRegions = {'US', 'CA'};

/// Returns [raw] as an E.164 phone number (`+` and 8 to 15 digits), or null
/// when it is not a phone number.
///
/// Steps, in order:
/// 1. Decode bridge escaping (`=3a` is `:`), drop a `tel:` prefix and any
///    extension (`;ext=12`, `x123`).
/// 2. Keep only digits and a leading `+`; a leading `00` becomes `+`.
/// 3. Without a `+`, apply [defaultRegion]. For `US` and `CA` (both +1),
///    10 digits get `+1` and 11 digits starting with `1` get `+`. Other
///    regions have no rule for national numbers, so the number is rejected
///    rather than guessed.
/// 4. The result must be `+` and 8 to 15 digits. Short codes (`83356`) and
///    alphanumeric senders (`AMAZON`) fail here and return null, which lets
///    the caller fall back to name matching.
String? normalizePhone(String raw, {String defaultRegion = 'US'}) {
  // Step 1.
  var text = raw
      .replaceAllMapped(
        _escapedByte,
        (m) => String.fromCharCode(int.parse(m[1]!, radix: 16)),
      )
      .trim()
      .replaceFirst(_telPrefix, '')
      .replaceFirst(_extension, '')
      .trim();

  // Step 2.
  final hasPlus = text.startsWith('+');
  text = text.replaceAll(_nonDigit, '');
  if (text.isEmpty) return null;
  var plus = hasPlus;
  if (!plus && text.startsWith('00')) {
    text = text.substring(2);
    plus = true;
  }

  // Step 3.
  if (!plus) {
    if (!_nanpRegions.contains(defaultRegion.toUpperCase())) return null;
    if (text.length == 10) {
      text = '1$text';
    } else if (!(text.length == 11 && text.startsWith('1'))) {
      return null;
    }
  }

  // Step 4.
  final result = '+$text';
  return _e164.hasMatch(result) ? result : null;
}

/// Formats an E.164 number from [normalizePhone] for labels such as
/// "Same number: +1 404 555 1234".
///
/// Only +1 numbers are grouped (`+1 404 555 1234`), since their layout is
/// fixed. Other countries group digits differently and that would need
/// per-country tables, so they are shown as `+` and the digits unchanged.
String formatPhoneForDisplay(String e164) {
  final digits = e164.startsWith('+') ? e164.substring(1) : e164;
  if (digits.length == 11 &&
      digits.startsWith('1') &&
      !digits.contains(_nonDigit)) {
    return '+1 ${digits.substring(1, 4)} ${digits.substring(4, 7)} '
        '${digits.substring(7)}';
  }
  return '+$digits';
}
