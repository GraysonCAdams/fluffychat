// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('every network colour gets white text', () {
    for (final MapEntry(key: network, value: color)
        in NetworkColors.defaults.entries) {
      expect(
        NetworkColors.foregroundOn(color),
        const Color(0xFFFFFFFF),
        reason: network,
      );
    }
  });

  test('a pale custom colour gets black text', () {
    expect(
      NetworkColors.foregroundOn(const Color(0xFFFFF59D)),
      const Color(0xFF000000),
    );
  });
}
