// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'render_pixels.dart';

void main() {
  // Avatar, border and background all in one color: drawn right, the avatar
  // disappears into the background. Anything else on its edge is a fringe
  // where one anti-aliased edge lets what lies under it show through.
  const grey = Color(0xFF808080);

  for (final brightness in Brightness.values) {
    testWidgets('a ${brightness.name} avatar has no fringe on its edge', (
      tester,
    ) async {
      final (pixels, _) = await renderPixels(
        tester,
        const Avatar(name: 'Emil Abel', backgroundColor: grey, textColor: grey),
        background: grey,
        brightness: brightness,
      );
      expect(maxDeviation(pixels, grey), lessThanOrEqualTo(2));
    });

    testWidgets('a ${brightness.name} avatar with a border has no fringe', (
      tester,
    ) async {
      final (pixels, _) = await renderPixels(
        tester,
        Avatar(
          name: 'Emil Abel',
          backgroundColor: grey,
          textColor: grey,
          shapeBorder: RoundedSuperellipseBorder(
            side: const BorderSide(width: 2, color: grey),
            borderRadius: BorderRadius.circular(24),
          ),
        ),
        background: grey,
        brightness: brightness,
      );
      expect(maxDeviation(pixels, grey), lessThanOrEqualTo(2));
    });
  }
}
