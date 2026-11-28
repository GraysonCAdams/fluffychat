// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/bootstrap/bootstrap_page.dart';
import 'package:fluffychat/pages/bootstrap/view_model/bootstrap_view_model.dart';
import 'package:fluffychat/pages/sign_in/sign_in_page.dart';
import 'package:fluffychat/pages/sign_in/view_model/sign_in_view_model.dart';
import 'package:fluffychat/utils/sign_in_flows/sign_in_method.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/message_search/search_test_client.dart';

class _Connected extends BootstrapCrypto {
  _Connected(super.client);

  @override
  Future<CryptoIdentityState> state() async => (
    connected: true,
    crossSigningEnabled: true,
    initialized: true,
    keyBackupEnabled: true,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late L10n l10n;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    l10n = await L10n.delegate.load(const Locale('en'));
  });

  Future<void> pump(WidgetTester tester, Widget home) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: home,
      ),
    );
    for (var i = 0; i < 40 && find.byType(Scaffold).evaluate().isEmpty; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump(const Duration(milliseconds: 16));
    }
  }

  test('setup after a sign-in is marked when it added an account', () {
    expect(MatrixState.setupLocation(accountAdded: false), '/backup');
    expect(MatrixState.setupLocation(accountAdded: true), '/backup?added=true');
  });

  testWidgets('typing an account already signed in offers to switch to it', (
    tester,
  ) async {
    final viewModel = SignInViewModel(
      null,
      signUp: false,
      checkServer: (_) async => SignInMethod.password,
    );
    addTearDown(viewModel.dispose);
    String? switchedTo;
    await pump(
      tester,
      ValueListenableBuilder(
        valueListenable: viewModel,
        builder: (context, _, _) => ServerStepView(
          viewModel: viewModel,
          signUp: false,
          signedInUserId: '@gray:d.graysons.network',
          signedInUserIds: const {'@gray:d.graysons.network'},
          onSwitchAccount: (userId) => switchedTo = userId,
        ),
      ),
    );
    expect(find.text(l10n.addAnotherAccount), findsOneWidget);

    await tester.enterText(find.byType(TextField), '@gray:d.graysons.network');
    await tester.pump(SignInViewModel.lookupDelay);
    await tester.pump();
    expect(find.text(l10n.alreadySignedInHere), findsOneWidget);
    expect(
      tester
          .widget<FilledButton>(
            find.widgetWithText(FilledButton, l10n.continueText),
          )
          .onPressed,
      isNull,
    );
    await tester.tap(find.text(l10n.switchToIt));
    expect(switchedTo, '@gray:d.graysons.network');

    await tester.enterText(find.byType(TextField), '@grayson:matrix.org');
    await tester.pump(SignInViewModel.lookupDelay);
    await tester.pump();
    expect(find.text(l10n.alreadySignedInHere), findsNothing);
  });

  testWidgets('setup after adding an account ends on Account added', (
    tester,
  ) async {
    final client = await tester.runAsync(createSearchTestClient);
    final viewModel = BootstrapViewModel(
      client: client!,
      reset: false,
      crypto: _Connected(client),
    );
    await pump(
      tester,
      ValueListenableBuilder(
        valueListenable: viewModel,
        builder: (context, _, _) =>
            BootstrapStepView(viewModel, accountAdded: true),
      ),
    );
    for (var i = 0; i < 20 && viewModel.step == BootstrapStep.loading; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 20)),
      );
      await tester.pump();
    }
    expect(viewModel.step, BootstrapStep.leave);
    expect(find.text(l10n.accountAddedTitle), findsOneWidget);
    expect(find.text(l10n.openItsChats), findsOneWidget);
    viewModel.dispose();
    await tester.runAsync(() => client.dispose(closeDatabase: true));
  });
}
