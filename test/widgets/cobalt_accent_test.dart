// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

double contrast(Color a, Color b) {
  final la = a.computeLuminance();
  final lb = b.computeLuminance();
  return (la > lb ? la + 0.05 : lb + 0.05) / (la > lb ? lb + 0.05 : la + 0.05);
}

double hue(Color c) => Hct.fromInt(c.toARGB32()).hue;

void main() {
  Future<ColorScheme> scheme(
    WidgetTester tester,
    Brightness brightness, [
    Color seed = AppConfig.primaryColor,
  ]) async {
    late ColorScheme result;
    await tester.pumpWidget(
      Builder(
        builder: (context) {
          result = FluffyThemes.buildTheme(
            context,
            brightness,
            seed,
          ).colorScheme;
          return const SizedBox();
        },
      ),
    );
    return result;
  }

  testWidgets('the default accent is a cobalt tint, not periwinkle', (
    tester,
  ) async {
    final dark = await scheme(tester, Brightness.dark);
    final light = await scheme(tester, Brightness.light);
    expect(dark.primary, const Color(0xFF84AAFF));
    expect(light.primary, const Color(0xFF235AB9));
    // Today's rainbow primary, #B3C5FF, is tone 80 at chroma 35.
    expect(Hct.fromInt(dark.primary.toARGB32()).chroma, greaterThan(45));
  });

  testWidgets('the selected chat is slate blue over neutral surfaces', (
    tester,
  ) async {
    for (final b in Brightness.values) {
      final s = await scheme(tester, b);
      // Turned towards cyan from the seed's hue of about 271, which reads
      // violet at low chroma.
      expect(hue(s.secondaryContainer), inInclusiveRange(245, 260));
      expect(Hct.fromInt(s.surface.toARGB32()).chroma, lessThan(4));
      expect(
        Hct.fromInt(s.surfaceContainerHigh.toARGB32()).chroma,
        lessThan(4),
      );
    }
  });

  testWidgets('accent text and fills keep their contrast', (tester) async {
    for (final b in Brightness.values) {
      final s = await scheme(tester, b);
      final pairs = {
        'primary on surface': (s.primary, s.surface),
        'link in a received bubble': (s.primary, s.surfaceContainerHigh),
        'typing in the selected chat': (s.primary, s.secondaryContainer),
        'button or badge label': (s.onPrimary, s.primary),
        'mention of the user': (s.onPrimaryContainer, s.primaryContainer),
        'selected chat or chip label': (
          s.onSecondaryContainer,
          s.secondaryContainer,
        ),
      };
      for (final MapEntry(key: role, value: (fg, bg)) in pairs.entries) {
        expect(
          contrast(fg, bg),
          greaterThanOrEqualTo(4.5),
          reason: '$role in ${b.name} mode',
        );
      }
    }
  });

  testWidgets('another seed keeps the rainbow scheme it always had', (
    tester,
  ) async {
    const green = Color(0xFF2E7D32);
    for (final b in Brightness.values) {
      final s = await scheme(tester, b, green);
      final expected = ColorScheme.fromSeed(
        brightness: b,
        seedColor: green,
        dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
      );
      expect(s.primary, expected.primary);
      expect(s.secondaryContainer, expected.secondaryContainer);
    }
  });
}
