// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/data_detectors/dart_data_detector.dart';
import 'package:fluffychat/utils/data_detectors/detection.dart';
import 'package:flutter_test/flutter_test.dart';

/// Seam's own data detector, used where the platform has none (Windows).
void main() {
  // Friday, Nov 27 2026, 10:00.
  final sent = DateTime(2026, 11, 27, 10);

  List<Detection> detect(String text) =>
      DartDataDetector.detectSync(text, referenceTime: sent);

  List<(DetectionType, String)> found(String text) => [
    for (final d in detect(text)) (d.type, d.text),
  ];

  group('addresses', () {
    test('the two from the chat in the bug report, written over lines', () {
      const first = '3456 Chelsea Park Lane Apt D\nPeachtree Corners GA\n30092';
      const second =
          '4532 Chamblee Dunwoody Rd\nAtlanta, GA  30338\nUnited States';
      expect(found(first), [(DetectionType.address, first)]);
      expect(found(second), [(DetectionType.address, second)]);
    });

    test('inside a sentence, on one line', () {
      expect(found('Come by 123 Main St, Springfield, IL 62701 after work'), [
        (DetectionType.address, '123 Main St, Springfield, IL 62701'),
      ]);
      expect(
        found(
          'Come to 3456 Chelsea Park Lane Apt D, Peachtree Corners GA '
          '30092 and ring',
        ),
        [
          (
            DetectionType.address,
            '3456 Chelsea Park Lane Apt D, Peachtree Corners GA 30092',
          ),
        ],
      );
    });

    test('a street without a city and state is not enough', () {
      expect(found('I live at 12 Oak Street now'), isEmpty);
      expect(found('We need 3 more chairs'), isEmpty);
      expect(found('Room 404 Main Hall'), isEmpty);
    });

    test('its ZIP code and house number are not read as anything else', () {
      expect(
        detect('4532 Chamblee Dunwoody Rd, Atlanta, GA 30338').single.type,
        DetectionType.address,
      );
    });
  });

  group('phone numbers', () {
    test('North American numbers in their usual forms', () {
      for (final number in [
        '(404) 555-0123',
        '404-555-0123',
        '404.555.0123',
        '+1 404 555 0123',
        '1-404-555-0123',
      ]) {
        expect(found('Call me at $number when you are close'), [
          (DetectionType.phone, number),
        ], reason: number);
      }
    });

    test('international numbers with a +', () {
      expect(found('My UK number is +44 20 7946 0958.'), [
        (DetectionType.phone, '+44 20 7946 0958'),
      ]);
    });

    test('digit runs that are not phone numbers', () {
      expect(found('Order 4045550123 shipped'), isEmpty);
      expect(found('Code 123456'), isEmpty);
      expect(found('Pay 1,000,000 dollars'), isEmpty);
      expect(found('Area code 123-555-0123 is invalid'), isEmpty);
    });

    test('a number in a link is left to the link', () {
      expect(found('https://example.com/call/404-555-0123'), isEmpty);
    });
  });

  group('flight numbers', () {
    test('major airlines', () {
      expect(found("I'm on DL 1234, lands at 6:45 pm"), [
        (DetectionType.flight, 'DL 1234'),
        (DetectionType.dateTime, '6:45 pm'),
      ]);
      expect(found('UA2345 is delayed'), [(DetectionType.flight, 'UA2345')]);
    });

    test('codes that are states or part numbers are not flights', () {
      expect(found('I lived in CA 12 years'), isEmpty);
      expect(found('Part AB 1234'), isEmpty);
      expect(found('dl 1234'), isEmpty);
    });
  });

  group('dates and times', () {
    DateTime? when(String text) => detect(text).single.when;

    test('relative days, from the time the message was sent', () {
      expect(when('Dinner tomorrow at 7pm?'), DateTime(2026, 11, 28, 19));
      expect(when('lands tomorrow at 6:45'), DateTime(2026, 11, 28, 18, 45));
      expect(when('Dinner Saturday at 7pm?'), DateTime(2026, 11, 28, 19));
      expect(when('see you Thursday'), DateTime(2026, 12, 3));
      expect(when('Dinner Friday at 7pm?'), DateTime(2026, 11, 27, 19));
      expect(when('see you next Friday'), DateTime(2026, 12, 4));
      expect(when('today at noon'), DateTime(2026, 11, 27, 12));
    });

    test('calendar dates', () {
      expect(when('Nov 28 works too'), DateTime(2026, 11, 28));
      expect(when('on December 3rd at 5:30 pm'), DateTime(2026, 12, 3, 17, 30));
      expect(when('since Jan 5'), DateTime(2027, 1, 5));
      expect(when('due 12/24/2026'), DateTime(2026, 12, 24));
    });

    test('what is underlined', () {
      expect(found('Dinner Friday at 7pm? Nov 28 works too'), [
        (DetectionType.dateTime, 'Friday at 7pm'),
        (DetectionType.dateTime, 'Nov 28'),
      ]);
      expect(found('meet at 7:30 pm'), [(DetectionType.dateTime, '7:30 pm')]);
    });

    test('a date has no time; a date with a time does', () {
      expect(detect('Nov 28 works').single.hasTime, isFalse);
      expect(detect('Friday at 7pm').single.hasTime, isTrue);
    });

    test('numbers that are not times', () {
      expect(found('The score was 6:45'), isEmpty);
      expect(found('I am 7'), isEmpty);
      expect(found('Maybe'), isEmpty);
      expect(found('Feb 30'), isEmpty);
      expect(found('half 1/2 of it'), isEmpty);
    });
  });

  test('several kinds in one message, in reading order', () {
    const text =
        'Come to 3456 Chelsea Park Lane Apt D, Peachtree Corners GA 30092 '
        'and ring (404) 555-0199 at the gate';
    expect(detect(text).map((d) => d.type), [
      DetectionType.address,
      DetectionType.phone,
    ]);
  });

  test('a long message is not scanned', () {
    final text = 'Call (404) 555-0123 ${'x' * DartDataDetector.maxLength}';
    expect(detect(text), isEmpty);
  });
}
