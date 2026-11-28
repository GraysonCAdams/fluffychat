// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/intro/intro_page.dart';
import 'package:fluffychat/widgets/seam_mark.dart';
import 'package:fluffychat/widgets/seam_startup.dart';
import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:fluffychat/widgets/terms_acceptance_views.dart';
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
    Size size = const Size(360, 800),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size * 3;
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    var signIns = 0;
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(
            disableAnimations: reduceMotion,
            textScaler: TextScaler.linear(textScale),
          ),
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
    // All white, as the loader draws it.
    expect(tester.widget<SeamMark>(find.byType(SeamMark)).pale, Colors.white);
    await tester.pumpAndSettle();
    // The mark keeps the loader's size and rises above the sheet.
    expect(markSize(tester), SeamStartup.loaderSize);
    final mark = tester.getRect(find.byType(SeamMark));
    expect(mark.center.dx, 180);
    expect(mark.center.dy, lessThan(300));
    expect(
      tester.widget<SeamMark>(find.byType(SeamMark)).pale,
      SeamStitchPainter.periwinkle,
    );
    expect(find.text(l10n.welcomeTagline, findRichText: true), findsOneWidget);
    // The sheet has come up under it, to the bottom of the window.
    final sheet = tester.getRect(find.byType(SignInTermsGate));
    expect(sheet.top, greaterThan(mark.bottom));
    expect(sheet.top, lessThan(800));
  });

  testWidgets('later welcome pages and reduced motion start settled', (
    tester,
  ) async {
    IntroPage.morphed = true;
    await pumpWelcome(tester);
    expect(markSize(tester), SeamStartup.loaderSize);
    expect(tester.getCenter(find.byType(SeamMark)).dy, lessThan(300));

    IntroPage.morphed = false;
    await pumpWelcome(tester, reduceMotion: true);
    expect(tester.getCenter(find.byType(SeamMark)).dy, lessThan(300));
  });

  testWidgets('a wide or landscape window puts the sheet beside the hero', (
    tester,
  ) async {
    for (final (size, twoPane) in [
      (const Size(1280, 800), true),
      (const Size(840, 1000), false),
      (const Size(841, 1000), true),
      // Medium: two panes in landscape, stacked in portrait.
      (const Size(700, 500), true),
      (const Size(600, 400), true),
      (const Size(700, 900), false),
      (const Size(599, 400), false),
    ]) {
      // Never morphs with two panes, so it starts settled.
      IntroPage.morphed = !twoPane;
      await pumpWelcome(tester, size: size);
      final mark = tester.getRect(find.byType(SeamMark));
      final sheet = tester.getRect(find.byType(SignInTermsGate));
      expect(
        sheet.left > mark.right,
        twoPane,
        reason: '$size: mark $mark, sheet $sheet',
      );
      if (twoPane) {
        expect(
          sheet.right,
          lessThanOrEqualTo(size.width - 24),
          reason: '$size',
        );
      }
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('fits at twice the text size, scrolling when it must', (
    tester,
  ) async {
    IntroPage.morphed = true;
    for (final size in const [
      Size(360, 800),
      Size(320, 568),
      Size(600, 400),
      Size(1280, 800),
    ]) {
      await pumpWelcome(tester, size: size, textScale: 2);
      expect(tester.takeException(), isNull, reason: '$size');
      // Sign in can be brought on screen and pressed.
      await tester.ensureVisible(find.byKey(const Key('terms_agree_checkbox')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('terms_agree_checkbox')));
      await tester.pump();
      await tester.ensureVisible(find.text(l10n.signIn));
      await tester.pump();
      await tester.tap(find.text(l10n.signIn));
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '$size');
    }
  });

  testWidgets('the terms card is labelled and its targets are 48 dp', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    IntroPage.morphed = true;
    await pumpWelcome(tester);
    expect(
      tester.getSemantics(find.byKey(const Key('terms_agree_checkbox'))),
      isSemantics(
        label: '${l10n.agreeToTermsOfUse}\n${l10n.agreeToTermsOfUseHint}',
        hasCheckedState: true,
        isChecked: false,
        hasTapAction: true,
      ),
    );
    for (final name in [l10n.termsOfUse, l10n.privacyPolicy]) {
      final link = find.bySemanticsLabel(l10n.opensInBrowser(name));
      expect(link, findsOneWidget);
      expect(
        tester.getSemantics(link),
        isSemantics(isLink: true, hasTapAction: true),
      );
      expect(tester.getSize(link).height, greaterThanOrEqualTo(48));
    }
    expect(
      tester.getSize(find.byKey(const Key('terms_agree_checkbox'))).height,
      greaterThanOrEqualTo(48),
    );
    await expectLater(tester, meetsGuideline(androidTapTargetGuideline));
    await expectLater(tester, meetsGuideline(labeledTapTargetGuideline));
    handle.dispose();
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
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, l10n.createAnAccount),
          )
          .onPressed,
      isNotNull,
    );
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
