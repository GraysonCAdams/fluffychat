// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/phone_number.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizePhone', () {
    const atlanta = '+14045551234';

    // Formats seen from the iMessage, Google Messages and SMS bridges.
    final sameNumber = {
      '+14045551234': 'E.164',
      'tel:+14045551234': 'tel URI',
      'TEL:+14045551234': 'upper-case tel URI',
      '(404) 555-1234': 'US national with parentheses',
      '404-555-1234': 'US national with dashes',
      '1 404 555 1234': 'US with trunk 1 and spaces',
      '404.555.1234': 'US national with dots',
      '+1 (404) 555-1234': 'international with punctuation',
      '0014045551234': '00 international prefix',
      'tel=3a+14045551234': 'bridge-escaped tel URI',
      '3a+14045551234': 'bridge-escaped colon without tel',
      '+14045551234;ext=12': 'URI extension',
      '404-555-1234 x123': 'written extension',
      '404-555-1234 ext. 9': 'written ext. extension',
      '  +1 404 555 1234  ': 'surrounding whitespace',
    };
    for (final MapEntry(key: raw, value: why) in sameNumber.entries) {
      test('$why: "$raw"', () {
        expect(normalizePhone(raw), atlanta);
      });
    }

    test('unnamed SMS contact display name', () {
      expect(normalizePhone('(866) 405-4049'), '+18664054049');
    });

    test('UK number with + is kept as is', () {
      expect(normalizePhone('+44 20 7946 0958'), '+442079460958');
      expect(
        normalizePhone('+44 20 7946 0958', defaultRegion: 'GB'),
        '+442079460958',
      );
    });

    test('UK number with 00 prefix in a non-US region', () {
      expect(
        normalizePhone('0044 20 7946 0958', defaultRegion: 'GB'),
        '+442079460958',
      );
    });

    test('national number in a non-US region is rejected', () {
      expect(normalizePhone('020 7946 0958', defaultRegion: 'GB'), isNull);
      expect(normalizePhone('404-555-1234', defaultRegion: 'GB'), isNull);
    });

    test('CA is treated like US', () {
      expect(
        normalizePhone('416-555-1234', defaultRegion: 'CA'),
        '+14165551234',
      );
      expect(
        normalizePhone('416-555-1234', defaultRegion: 'ca'),
        '+14165551234',
      );
    });

    final notPhones = {
      '83356': 'short code',
      'AMAZON': 'alphanumeric sender',
      '': 'empty',
      '   ': 'blank',
      '+123': 'too short',
      '+1234567': '7 digits',
      '+1234567890123456': '16 digits',
      '+12345678901234567890': '20 digits',
      '555-1234': '7-digit US local number',
      '24045551234': '11 digits not starting with 1',
    };
    for (final MapEntry(key: raw, value: why) in notPhones.entries) {
      test('rejects $why: "$raw"', () {
        expect(normalizePhone(raw), isNull);
      });
    }

    test('accepts the E.164 length bounds', () {
      expect(normalizePhone('+12345678'), '+12345678');
      expect(normalizePhone('+123456789012345'), '+123456789012345');
    });
  });

  group('formatPhoneForDisplay', () {
    test('groups +1 numbers', () {
      expect(formatPhoneForDisplay('+14045551234'), '+1 404 555 1234');
    });

    test('leaves other countries ungrouped', () {
      expect(formatPhoneForDisplay('+442079460958'), '+442079460958');
    });

    test('does not group a +1-prefixed number of the wrong length', () {
      expect(formatPhoneForDisplay('+1404555123'), '+1404555123');
    });
  });
}
