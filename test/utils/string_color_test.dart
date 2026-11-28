// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/string_color.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

void main() {
  // One string per colour: the buckets are the code unit sum modulo 12.
  final all = [for (var i = 0; i < 12; i++) String.fromCharCode(72 + i)];

  test('there are 12 initials colours, none of them pink or violet', () {
    final fills = {for (final s in all) s.avatarColors.fill};
    expect(fills, hasLength(12));
    for (final fill in fills) {
      final hct = Hct.fromInt(fill.toARGB32());
      // Greys have no hue to judge.
      if (hct.chroma < 8) continue;
      expect(
        hct.hue,
        inInclusiveRange(30, 280),
        reason: '${fill.toARGB32().toRadixString(16)} is pink or violet',
      );
    }
  });

  test('a few warm colours stay, so contacts remain apart', () {
    final warm = all.where((s) {
      final hct = Hct.fromInt(s.avatarColors.fill.toARGB32());
      return hct.chroma >= 8 && hct.hue < 100;
    });
    expect(warm.length, greaterThanOrEqualTo(3));
  });

  test('the letters read on their fill', () {
    for (final s in all) {
      final colors = s.avatarColors;
      expect(contrast(colors.onFill, colors.fill), greaterThanOrEqualTo(4.5));
    }
  });

  test('the same name always gets the same colour', () {
    expect('GA'.avatarColors, 'GA'.avatarColors);
    expect('AG'.avatarColors, 'GA'.avatarColors);
  });
}
