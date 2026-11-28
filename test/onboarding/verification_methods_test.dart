// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/client_manager.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';

void main() {
  test('every platform compares emoji and offers QR codes', () {
    // Desktop hosts (this suite runs on Windows) included.
    expect(
      ClientManager.verificationMethods,
      containsAll({
        KeyVerificationMethod.emoji,
        KeyVerificationMethod.numbers,
        KeyVerificationMethod.qrShow,
        KeyVerificationMethod.reciprocate,
      }),
    );
  });
}
