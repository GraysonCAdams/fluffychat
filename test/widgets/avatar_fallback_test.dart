// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('fallback letters', () {
    for (final (name, letters) in [
      ('Family (New)', 'F'),
      ('Jane (Work) Doe', 'JD'),
      ('John Smith', 'JS'),
      ('Alice', 'A'),
      ('(New)', '@'),
    ]) {
      test('"$name" gives "$letters"', () {
        expect(Avatar.calcFallbackLetters(name), letters);
      });
    }
  });

  group('number icon', () {
    for (final (name, icon) in [
      ('83356', Icons.storefront_outlined),
      ('22395', Icons.storefront_outlined),
      ('+1 (312) 555-0100', Icons.person_outline),
      ('(312) 555-0100', Icons.person_outline),
      ('3125550100', Icons.person_outline),
      ('John Smith', null),
      ('Family (New)', null),
      ('42', null),
    ]) {
      test('"$name" gives $icon', () {
        expect(Avatar.numberIcon(name), icon);
      });
    }
  });
}
