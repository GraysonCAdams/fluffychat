// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_list_fakes.dart';

/// An account that can be signed out: it then has no sync position, as a
/// client that logged out has not.
class _Account extends FakeChatListClient {
  _Account(super.clientName, {required super.database});

  bool signedOut = false;

  @override
  String? get prevBatch => signedOut ? null : 'synced';
}

/// Two accounts on the device, one of them active.
class _Accounts extends FakeMatrix {
  _Accounts(this.accounts, SharedPreferences prefs)
    : super(accounts.first, prefs);

  final List<Client> accounts;
  late Client active = accounts.last;

  @override
  Client get client => active;

  @override
  Map<String?, List<Client?>> get accountBundles => {
    for (final account in accounts) account.clientName: [account],
  };

  @override
  List<Client?>? get currentBundle => accounts;

  @override
  bool get hasClients => accounts.isNotEmpty;
}

/// The sync pill follows the active account: once an added account signs
/// out and is removed, it shows the remaining account's sync, not the
/// signed-out one's, which never syncs again.
void main() {
  late _Account gray;
  late _Account review;

  setUp(() async {
    gray = await setUpFakeChatList(
      'sync pill gray',
      create: (name, database) => _Account(name, database: database),
    );
    review = await setUpFakeChatList(
      'sync pill review',
      create: (name, database) => _Account(name, database: database),
    );
  });

  tearDown(() {
    tearDownFakeChatList(gray);
    tearDownFakeChatList(review);
  });

  bool pillShown() => find
      .descendant(
        of: find.byType(SyncStatusToast),
        matching: find.byType(CircularProgressIndicator),
      )
      .evaluate()
      .isNotEmpty;

  /// Signs the added, active account out the way the app does: the SDK
  /// clears its session, last having reported that it waits for the
  /// server, and the app drops it and makes the other account active.
  Future<_Accounts> signOutAdded(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    final accounts = _Accounts([
      gray,
      review,
    ], await SharedPreferences.getInstance());
    // The added account is active, as the Add account flow leaves it.
    await pumpFakeChatList(tester, review, matrix: accounts);
    expect(find.byType(SyncStatusToast), findsOneWidget);
    expect(pillShown(), isFalse, reason: 'both accounts synced');

    // Its last long poll had reported that it waits for the server.
    review.onSyncStatus.add(
      const SyncStatusUpdate(SyncStatus.waitingForResponse),
    );
    await tester.pump();
    review.signedOut = true;
    accounts.accounts.remove(review);
    accounts.active = gray;
    review.onLoginStateChanged.add(LoginState.loggedOut);
    await tester.pumpAndSettle();
    return accounts;
  }

  /// Ways the pill is drawn again on the phone with no new sync status from
  /// the remaining account.
  final redraws = <String, Future<void> Function(WidgetTester tester)>{
    'the app comes back to the front': (tester) async {
      for (final state in [
        AppLifecycleState.inactive,
        AppLifecycleState.hidden,
        AppLifecycleState.paused,
        AppLifecycleState.hidden,
        AppLifecycleState.inactive,
        AppLifecycleState.resumed,
      ]) {
        tester.binding.handleAppLifecycleStateChanged(state);
      }
    },
    'the window changes size': (tester) async {
      tester.view.physicalSize = const Size(400, 700);
    },
  };

  for (final MapEntry(key: redraw, value: trigger) in redraws.entries) {
    testWidgets('after the added account signs out, $redraw: the pill '
        'follows the remaining account', (tester) async {
      await signOutAdded(tester);
      await trigger(tester);
      // Settling would wait forever on a pill's spinner.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(
        pillShown(),
        isFalse,
        reason: 'not the signed-out account, frozen waiting',
      );

      // And it reports the remaining account's sync from now on.
      gray.onSyncStatus.add(
        SyncStatusUpdate(
          SyncStatus.error,
          error: SdkError(exception: Exception('offline')),
        ),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(pillShown(), isTrue, reason: 'the remaining account failed');

      await finishFakeChatList(tester, gray);
    });
  }
}
