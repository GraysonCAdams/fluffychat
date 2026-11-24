// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/one_time_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('finds a code', () {
    const cases = {
      'Your verification code is 282295': '282295',
      '282295 is your Instagram code. Don\'t share it.': '282295',
      'Your OTP: 4821': '4821',
      'Use passcode 12345678 to sign in': '12345678',
      'Your Microsoft PIN is 9034.': '9034',
      '123 456 is your Signal code': '123456',
      'Your security code is 1234-5678': '12345678',
      'G-583921 is your Google verification code.': '583921',
      'Your PIN is 2024': '2024',
      'Your code is 482913. It expires on 12/05/2025.': '482913',
      'Order 55512 shipped. Your one-time code is 730114': '730114',
    };
    cases.forEach((text, code) {
      test(text, () => expect(findOneTimeCode(text), code));
    });
  });

  group('finds no code', () {
    const cases = [
      // No keyword.
      'See you at 1830 by gate 12345',
      'Lunch costs 1234 today',
      // Phone numbers.
      'Call me at 555-123-4567 for the code',
      'Code questions? Call (555) 123-4567',
      'Text +1 555 123 4567 with your code',
      // Prices.
      'The code costs \$1234',
      'Verification fee: 1234.50',
      'Your code saves you 5000 dollars',
      // Dates and years.
      'The code changed on 2024-05-12',
      'Code expires 12/05/2025',
      'Your code was issued in 2024',
      // The end of a link or a decimal.
      'Verify at example.com/v/482913',
      'Code version 3.48291',
      // Too short, too long, or joined to a word.
      'Your code is 123',
      'Your code is 123456789',
      'Your code is abc12345',
    ];
    for (final text in cases) {
      test(text, () => expect(findOneTimeCode(text), isNull));
    }
  });
}
