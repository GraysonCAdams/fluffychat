// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  const cobalt = 0xFF1A5AD7;
  const dynamicColor = Color(0xFF00AA00);

  group('colorSchemeSeedInt', () {
    setUp(() async {
      SharedPreferences.setMockInitialValues({});
      await AppSettings.init(loadWebConfigFile: false);
      await AppSettings.store.remove(AppSettings.colorSchemeSeedInt.key);
    });

    test('defaults to Seam Cobalt', () {
      expect(AppSettings.colorSchemeSeedInt.value, cobalt);
    });

    test('drops the stored FluffyChat purple default', () async {
      await AppSettings.colorSchemeSeedInt.setItem(
        AppSettings.legacyColorSchemeSeed,
      );
      await AppSettings.dropLegacyColorSchemeSeed(AppSettings.store);
      expect(AppSettings.colorSchemeSeedInt.value, cobalt);
    });

    test('keeps a colour the user picked', () async {
      await AppSettings.colorSchemeSeedInt.setItem(0xFF9C27B0);
      await AppSettings.dropLegacyColorSchemeSeed(AppSettings.store);
      expect(AppSettings.colorSchemeSeedInt.value, 0xFF9C27B0);
    });
  });

  group('ThemeBuilder', () {
    Future<Color?> builtColor(
      WidgetTester tester,
      Map<String, Object> stored,
    ) async {
      SharedPreferences.setMockInitialValues(stored);
      final prefs = await SharedPreferences.getInstance();
      Color? color;
      await tester.pumpWidget(
        ThemeBuilder(
          store: prefs,
          dynamicPrimaryColor: dynamicColor,
          builder: (context, mode, primaryColor) {
            color = primaryColor;
            return const SizedBox();
          },
        ),
      );
      return color;
    }

    testWidgets('uses no override by default, so the cobalt seed applies', (
      tester,
    ) async {
      expect(await builtColor(tester, {}), isNull);
    });

    testWidgets('uses the dynamic colour once the system colour is picked', (
      tester,
    ) async {
      expect(
        await builtColor(tester, {'primary_color_from_system': true}),
        dynamicColor,
      );
    });

    testWidgets('uses a picked colour', (tester) async {
      expect(
        await builtColor(tester, {'primary_color': 0xFFFF0000}),
        const Color(0xFFFF0000),
      );
    });

    testWidgets('picking the system colour and then a colour switches', (
      tester,
    ) async {
      SharedPreferences.setMockInitialValues({});
      final prefs = await SharedPreferences.getInstance();
      Color? color;
      await tester.pumpWidget(
        ThemeBuilder(
          store: prefs,
          dynamicPrimaryColor: dynamicColor,
          builder: (context, mode, primaryColor) {
            color = primaryColor;
            return const SizedBox();
          },
        ),
      );
      final controller = tester.state<ThemeController>(
        find.byType(ThemeBuilder),
      );
      await controller.setPrimaryColor(null);
      await tester.pump();
      expect(color, dynamicColor);
      expect(prefs.getBool('primary_color_from_system'), isTrue);

      await controller.setPrimaryColor(const Color(0xFF2196F3));
      await tester.pump();
      expect(color, const Color(0xFF2196F3));
      expect(prefs.getBool('primary_color_from_system'), isNull);
    });
  });
}
