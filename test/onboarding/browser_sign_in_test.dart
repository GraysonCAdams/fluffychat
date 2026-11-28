// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/sign_in/browser_sign_in_page.dart';
import 'package:fluffychat/utils/sign_in_flows/sign_in_method.dart';
import 'package:fluffychat/utils/sign_in_flows/sso_login.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/message_search/search_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late L10n l10n;
  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    l10n = await L10n.delegate.load(const Locale('en'));
  });
  setUp(() async => client = await createSearchTestClient());
  tearDown(() => client.dispose(closeDatabase: true));

  Future<void> pump(
    WidgetTester tester,
    Future<void> Function(BuildContext, SsoIdentityProvider?) signIn, {
    SignInMethod method = SignInMethod.oidc,
    List<LoginFlow> loginFlows = const [],
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: BrowserSignInPage(
          signIn: signIn,
          args: BrowserSignInArgs(
            client: client,
            method: method,
            loginFlows: loginFlows,
            signUp: false,
            homeserverInput: 'fakeserver.notexisting',
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 40 &&
          find.byType(FilledButton).evaluate().isEmpty &&
          find.byType(OutlinedButton).evaluate().isEmpty;
      i++
    ) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  testWidgets(
    'explains the hand-off, waits, and closing the browser comes back',
    (tester) async {
      var calls = 0;
      late Completer<void> browser;
      await pump(tester, (_, _) {
        calls++;
        browser = Completer();
        return browser.future;
      });
      expect(find.text(l10n.signInOnServerPageTitle), findsOneWidget);
      expect(calls, 0, reason: 'nothing opens before Continue');

      await tester.tap(find.text(l10n.continueToSignInPage));
      await tester.pump();
      expect(calls, 1);
      expect(find.text(l10n.finishSigningInBrowser), findsOneWidget);

      browser.completeError(PlatformException(code: 'CANCELED'));
      await tester.pump();
      expect(find.text(l10n.signInOnServerPageTitle), findsOneWidget);
      expect(find.byIcon(Icons.error_outline), findsNothing);
    },
  );

  testWidgets('a failed sign-in shows why, in place', (tester) async {
    await pump(tester, (_, _) async => throw Exception('state mismatch'));
    await tester.tap(find.text(l10n.continueToSignInPage));
    await tester.pump();
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsOneWidget);
    expect(find.text(l10n.continueToSignInPage), findsOneWidget);
  });

  testWidgets('cancel drops an attempt that returns later', (tester) async {
    final browser = Completer<void>();
    await pump(tester, (_, _) => browser.future);
    await tester.tap(find.text(l10n.continueToSignInPage));
    await tester.pump();
    await tester.tap(find.text(l10n.cancel));
    await tester.pump();
    expect(find.text(l10n.signInOnServerPageTitle), findsOneWidget);
    browser.completeError(Exception('late'));
    await tester.pump();
    expect(find.byIcon(Icons.error_outline), findsNothing);
  });

  testWidgets('several SSO providers each get a button', (tester) async {
    SsoIdentityProvider? chosen;
    await pump(
      tester,
      (_, provider) async {
        chosen = provider;
        await Completer<void>().future;
      },
      method: SignInMethod.sso,
      loginFlows: [
        LoginFlow.fromJson({
          'type': 'm.login.sso',
          'identity_providers': [
            {'id': 'github', 'name': 'GitHub'},
            {'id': 'oidc-work', 'name': 'Work'},
          ],
        }),
      ],
    );
    expect(find.text(l10n.chooseHowToSignIn), findsOneWidget);
    await tester.tap(find.text(l10n.continueWithProvider('Work')));
    await tester.pump();
    expect(chosen?.id, 'oidc-work');
  });
}
