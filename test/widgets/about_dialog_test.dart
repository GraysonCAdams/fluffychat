// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// The About dialog: the app's icon with its name and version beside it,
/// the legal notice, the links as one aligned list, at Material 3's 24dp
/// dialog padding.
void main() {
  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    PackageInfo.setMockInitialValues(
      appName: 'Seam',
      packageName: 'dev.threeonetwo.seam',
      version: '2.11.6',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  Future<void> open(WidgetTester tester, Size size) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () => PlatformInfos.showDialog(context),
              child: const Text('about'),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.text('about'));
    await tester.pumpAndSettle();
  }

  /// The dialog's surface, inside the screen margin Dialog keeps around it.
  Rect surface(WidgetTester tester) => tester.getRect(
    find
        .descendant(of: find.byType(Dialog), matching: find.byType(Material))
        .first,
  );

  Rect rect(WidgetTester tester, String key) =>
      tester.getRect(find.byKey(ValueKey(key)));

  const links = [
    'about-link-source',
    'about-link-upstream',
    'about-link-logs',
    'about-link-configs',
  ];

  testWidgets('the name and version share a column beside the icon', (
    tester,
  ) async {
    await open(tester, const Size(412, 915));
    final icon = rect(tester, 'about-icon');
    final name = rect(tester, 'about-name');
    final version = rect(tester, 'about-version');
    expect(find.text('Seam'), findsOneWidget);
    expect(find.text('Version: 2.11.6'), findsOneWidget);
    expect(name.left, icon.right + 16);
    expect(version.left, name.left);
    expect(version.top, greaterThanOrEqualTo(name.bottom));
    // The two lines sit centred on the icon.
    expect((name.top + version.bottom) / 2, closeTo(icon.center.dy, 1));
  });

  testWidgets('everything keeps 24dp from the dialog\'s sides', (tester) async {
    await open(tester, const Size(412, 915));
    final dialog = surface(tester);
    final legalese = rect(tester, 'about-legalese');
    expect(rect(tester, 'about-icon').left - dialog.left, 24);
    expect(legalese.left - dialog.left, 24);
    expect(dialog.right - legalese.right, 24);
  });

  testWidgets('the links are full-width 48dp rows with their icons in line', (
    tester,
  ) async {
    await open(tester, const Size(412, 915));
    final dialog = surface(tester);
    final iconLefts = <double>{};
    for (final key in links) {
      final row = rect(tester, key);
      expect(row.height, 48, reason: key);
      expect(row.left, dialog.left, reason: key);
      expect(row.right, dialog.right, reason: key);
      iconLefts.add(
        tester
            .getRect(
              find.descendant(
                of: find.byKey(ValueKey(key)),
                matching: find.byType(Icon),
              ),
            )
            .left,
      );
    }
    expect(iconLefts, {dialog.left + 24});
  });

  testWidgets('on a wide window the dialog is at most 560 wide', (
    tester,
  ) async {
    await open(tester, const Size(1600, 1000));
    expect(surface(tester).width, 560);
    expect(find.text('View licenses'), findsOneWidget);
    await tester.tap(find.text('Close'));
    await tester.pumpAndSettle();
    expect(find.byType(Dialog), findsNothing);
  });
}
