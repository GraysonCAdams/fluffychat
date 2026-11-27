// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Agreement to the Terms of use: the sign-in checkbox, the record on the
// device and in account data, and the dialog and composer gate for an
// account that has not agreed yet.

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/terms_acceptance.dart';
import 'package:fluffychat/widgets/terms_acceptance_views.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_search/search_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late L10n l10n;

  const type = TermsAcceptance.accountDataType;
  const version = TermsAcceptance.currentVersion;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  setUp(() async {
    await AppSettings.store.remove(AppSettings.termsAcceptedVersion.key);
    await AppSettings.store.remove(AppSettings.termsAcceptedAt.key);
    client = await createSearchTestClient();
    // Account data the client writes comes back through its sync.
    FakeMatrixApi.client = client;
  });

  tearDown(() async {
    TermsAcceptance.resetForTest();
    await client.dispose(closeDatabase: true);
  });

  /// The terms record another device of this account wrote, arriving by
  /// sync. Sync listeners hear of it a microtask later.
  Future<void> agreeOnAnotherDevice() async {
    await client.handleSync(
      SyncUpdate(
        nextBatch: '',
        accountData: [
          BasicEvent(
            type: type,
            content: {'version': version, 'accepted_at': 1764115200000},
          ),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
  }

  /// Pumps until the deferred English strings have loaded and [done].
  Future<void> pumpUntil(WidgetTester tester, bool Function() done) async {
    for (var i = 0; i < 40 && !done(); i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  group('record', () {
    test('an account that never agreed is not accepted', () async {
      final terms = TermsAcceptance.of(client);
      expect(await terms.settle(), isFalse);
      expect(client.accountData[type], isNull);
    });

    test(
      'agreeing on the sign-in page reaches account data after sign-in',
      () async {
        final at = DateTime.utc(2026, 11, 27, 15);
        await TermsAcceptance.recordOnDevice(now: at);
        expect(AppSettings.termsAcceptedVersion.value, version);
        expect(AppSettings.termsAcceptedAt.value, at.millisecondsSinceEpoch);

        final terms = TermsAcceptance.of(client);
        expect(await terms.settle(), isTrue);
        expect(client.accountData[type]?.content, {
          'version': version,
          'accepted_at': at.millisecondsSinceEpoch,
        });
      },
    );

    test(
      'agreeing in the dialog records on the device and the account',
      () async {
        final terms = TermsAcceptance.of(client);
        final at = DateTime.utc(2026, 11, 27, 16);
        await terms.accept(now: at);
        expect(terms.value, isTrue);
        expect(AppSettings.termsAcceptedVersion.value, version);
        expect(AppSettings.termsAcceptedAt.value, at.millisecondsSinceEpoch);
        expect(client.accountData[type]?.content['version'], version);
        expect(
          client.accountData[type]?.content['accepted_at'],
          at.millisecondsSinceEpoch,
        );
      },
    );

    test(
      'agreement from another device counts, and is kept on this one',
      () async {
        final terms = TermsAcceptance.of(client);
        expect(terms.value, isFalse);
        await agreeOnAnotherDevice();
        expect(terms.value, isTrue);
        expect(await terms.settle(), isTrue);
        expect(AppSettings.termsAcceptedVersion.value, version);
        expect(AppSettings.termsAcceptedAt.value, 1764115200000);
      },
    );

    test('an older version does not count', () async {
      await AppSettings.termsAcceptedVersion.setItem('2020-01-01');
      expect(TermsAcceptance.acceptedOnDevice, isFalse);
      expect(await TermsAcceptance.of(client).settle(), isFalse);
    });
  });

  group('sign-in page', () {
    testWidgets('sign-in stays disabled until the box is ticked', (
      tester,
    ) async {
      var signIns = 0;
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: SignInTermsGate(
              builder: (context, gate) => ElevatedButton(
                onPressed: gate(() => signIns++),
                child: const Text('Sign in'),
              ),
            ),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => find.byType(SignInTermsGate).evaluate().isNotEmpty,
      );
      ElevatedButton button() =>
          tester.widget<ElevatedButton>(find.byType(ElevatedButton));

      expect(find.text(l10n.agreeToTermsOfUse), findsOneWidget);
      expect(find.text(l10n.termsOfUse), findsOneWidget);
      expect(find.text(l10n.privacyPolicy), findsOneWidget);
      expect(button().onPressed, isNull);

      await tester.tap(find.byKey(const Key('terms_agree_checkbox')));
      await tester.pump();
      expect(button().onPressed, isNotNull);
      expect(
        AppSettings.termsAcceptedVersion.value,
        isEmpty,
        reason: 'ticking alone records nothing; signing in does',
      );

      await tester.tap(find.text('Sign in'));
      await tester.pump();
      expect(signIns, 1);
      expect(AppSettings.termsAcceptedVersion.value, version);
      expect(AppSettings.termsAcceptedAt.value, greaterThan(0));

      // Unticking disables it again.
      await tester.tap(find.byKey(const Key('terms_agree_checkbox')));
      await tester.pump();
      expect(button().onPressed, isNull);
    });
  });

  group('signed-in account', () {
    final navigatorKey = GlobalKey<NavigatorState>();

    Future<void> pumpChat(WidgetTester tester) async {
      await tester.pumpWidget(
        MaterialApp(
          navigatorKey: navigatorKey,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            bottomNavigationBar: TermsComposerGate(
              client: client,
              child: const Text('composer'),
            ),
          ),
        ),
      );
      await pumpUntil(
        tester,
        () => find.byType(TermsComposerGate).evaluate().isNotEmpty,
      );
    }

    /// Runs the launch check, until it has either finished or put up the
    /// dialog, and returns whether it finished. The client's futures complete
    /// outside the test's fake clock, hence the real waits in pumpUntil.
    Future<bool> launch(WidgetTester tester) async {
      var finished = false;
      unawaited(
        promptForTermsIfNeeded(
          client,
          () => navigatorKey.currentContext!,
        ).whenComplete(() => finished = true),
      );
      await pumpUntil(
        tester,
        () => finished || find.byType(TermsUpdateDialog).evaluate().isNotEmpty,
      );
      await tester.pumpAndSettle();
      return finished;
    }

    testWidgets('the dialog blocks the composer until Agree', (tester) async {
      await pumpChat(tester);
      expect(find.byKey(const Key('terms_composer_gate')), findsOneWidget);
      expect(find.text('composer'), findsNothing);

      await launch(tester);
      expect(find.byType(TermsUpdateDialog), findsOneWidget);

      // Neither the scrim nor Back closes it.
      await tester.tapAt(const Offset(5, 5));
      await tester.pumpAndSettle();
      expect(find.byType(TermsUpdateDialog), findsOneWidget);
      await tester.binding.handlePopRoute();
      await tester.pumpAndSettle();
      expect(find.byType(TermsUpdateDialog), findsOneWidget);
      expect(find.text('composer'), findsNothing);

      await tester.tap(find.byKey(const Key('terms_agree_button')));
      await tester.pumpAndSettle();
      expect(find.byType(TermsUpdateDialog), findsNothing);
      expect(find.text('composer'), findsOneWidget);
      expect(AppSettings.termsAcceptedVersion.value, version);
      // The account copy follows. Waiting for all of it also keeps the
      // write from holding the database open when tearDown closes it.
      var written = false;
      TermsAcceptance.of(
        client,
      ).lastAccept!.whenComplete(() => written = true).ignore();
      await pumpUntil(tester, () => written);
      expect(written, isTrue);
      expect(client.accountData[type]?.content['version'], version);
    });

    testWidgets('Review on the disabled composer opens the dialog', (
      tester,
    ) async {
      await pumpChat(tester);
      await tester.tap(find.text(l10n.review));
      await tester.pumpAndSettle();
      expect(find.byType(TermsUpdateDialog), findsOneWidget);
      expect(find.text(l10n.signOut), findsOneWidget);
    });

    testWidgets('agreement already in account data skips the dialog', (
      tester,
    ) async {
      await tester.runAsync(agreeOnAnotherDevice);
      await pumpChat(tester);
      expect(await launch(tester), isTrue);
      expect(find.byType(TermsUpdateDialog), findsNothing);
      expect(find.text('composer'), findsOneWidget);
    });

    testWidgets('the dialog closes when another device agrees', (tester) async {
      await pumpChat(tester);
      await launch(tester);
      expect(find.byType(TermsUpdateDialog), findsOneWidget);

      await tester.runAsync(agreeOnAnotherDevice);
      await tester.pumpAndSettle();
      expect(find.byType(TermsUpdateDialog), findsNothing);
      expect(find.text('composer'), findsOneWidget);
    });
  });
}
