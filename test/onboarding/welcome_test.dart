// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/intro/intro_page.dart';
import 'package:fluffychat/widgets/seam_mark.dart';
import 'package:fluffychat/widgets/seam_startup.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late L10n l10n;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  Future<int> pumpWelcome(
    WidgetTester tester, {
    bool reduceMotion = false,
  }) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var signIns = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(
            context,
          ).copyWith(disableAnimations: reduceMotion),
          child: child!,
        ),
        home: IntroPage(
          isLoading: false,
          loggingInToHomeserver: null,
          hasPresetHomeserver: false,
          welcomeText: null,
          login: () => signIns++,
        ),
      ),
    );
    for (var i = 0; i < 40 && find.byType(IntroPage).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
    return signIns;
  }

  double markSize(WidgetTester tester) =>
      tester.getSize(find.byType(SeamMark)).width;

  testWidgets('the first welcome page grows out of the start screen', (
    tester,
  ) async {
    IntroPage.morphed = false;
    await pumpWelcome(tester);
    // As the start screen left it: the mark at the loader's size, centred.
    expect(markSize(tester), SeamStartup.loaderSize);
    expect(tester.getCenter(find.byType(SeamMark)), const Offset(180, 400));
    await tester.pumpAndSettle();
    expect(markSize(tester), 112);
    expect(tester.getCenter(find.byType(SeamMark)).dy, lessThan(250));
    expect(find.text(l10n.welcomeTagline), findsOneWidget);
  });

  testWidgets('later welcome pages and reduced motion start settled', (
    tester,
  ) async {
    IntroPage.morphed = true;
    await pumpWelcome(tester);
    expect(markSize(tester), 112);

    IntroPage.morphed = false;
    await pumpWelcome(tester, reduceMotion: true);
    expect(markSize(tester), 112);
  });

  testWidgets('sign in waits for the terms', (tester) async {
    IntroPage.morphed = true;
    await pumpWelcome(tester);
    FilledButton signIn() =>
        tester.widget(find.widgetWithText(FilledButton, l10n.signIn));
    expect(signIn().onPressed, isNull);
    await tester.tap(find.byKey(const Key('terms_agree_checkbox')));
    await tester.pump();
    expect(signIn().onPressed, isNotNull);
    expect(find.text(l10n.createAnAccount), findsOneWidget);
  });

  testWidgets('the menu keeps restore from a backup file', (tester) async {
    IntroPage.morphed = true;
    await pumpWelcome(tester);
    await tester.tap(find.byTooltip(l10n.moreOptions));
    await tester.pumpAndSettle();
    expect(find.text(l10n.hydrate), findsOneWidget);
    expect(find.text(l10n.about), findsOneWidget);
  });
}
