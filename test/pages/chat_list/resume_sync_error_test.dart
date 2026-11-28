// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:fluffychat/utils/shown_sync_status.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'chat_list_fakes.dart';

/// A sync the phone broke off while the app was in the background is not
/// shown as a connection error when the app comes back; a sync that fails
/// while the app is on screen is.
void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('resume sync error test');
    addFakeChat(client, '!a:x', 'Drew');
  });

  tearDown(() => tearDownFakeChatList(client));

  /// Whether the sync status pill is up.
  bool toastShown() => find
      .descendant(
        of: find.byType(SyncStatusToast),
        matching: find.byType(CircularProgressIndicator),
      )
      .evaluate()
      .isNotEmpty;

  /// A sync the system broke off, as Android reports it, and the frames
  /// that show what follows from it.
  Future<void> failSync(WidgetTester tester) async {
    client.onSyncStatus.add(
      SyncStatusUpdate(
        SyncStatus.error,
        error: SdkError(
          exception: Exception('Software caused connection abort'),
        ),
      ),
    );
    await tester.pump();
    await tester.pump();
  }

  /// Moves the app to [state] through the states between, as the system
  /// does.
  Future<void> lifecycle(WidgetTester tester, AppLifecycleState state) async {
    const order = [
      AppLifecycleState.resumed,
      AppLifecycleState.inactive,
      AppLifecycleState.hidden,
      AppLifecycleState.paused,
    ];
    var at = order.indexOf(
      tester.binding.lifecycleState ?? AppLifecycleState.resumed,
    );
    final to = order.indexOf(state);
    while (at != to) {
      at += at < to ? 1 : -1;
      tester.binding.handleAppLifecycleStateChanged(order[at]);
    }
    await tester.pump();
  }

  Future<void> pumpList(WidgetTester tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await pumpFakeChatList(tester, client);
    expect(toastShown(), isFalse, reason: 'synced');
  }

  testWidgets('a sync broken off in the background shows no error on '
      'resume, and none once a sync after it works', (tester) async {
    await pumpList(tester);
    await lifecycle(tester, AppLifecycleState.paused);
    await failSync(tester);

    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));
    expect(toastShown(), isFalse, reason: 'just resumed');

    // The sync the client starts on resume works.
    client.onSyncStatus.add(
      const SyncStatusUpdate(SyncStatus.waitingForResponse),
    );
    await tester.pump(const Duration(seconds: 1));
    client.onSyncStatus.add(const SyncStatusUpdate(SyncStatus.finished));
    await tester.pump(ShownSyncStatus.grace * 2);
    expect(toastShown(), isFalse, reason: 'synced again');

    await finishFakeChatList(tester, client);
  });

  testWidgets('a sync failing after the resume shows at once', (tester) async {
    await pumpList(tester);
    await lifecycle(tester, AppLifecycleState.paused);
    await failSync(tester);
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(const Duration(milliseconds: 50));
    expect(toastShown(), isFalse);

    await failSync(tester);
    expect(toastShown(), isTrue);

    await finishFakeChatList(tester, client);
  });

  testWidgets('with no sync working within the grace after resume, the '
      'failure shows', (tester) async {
    await pumpList(tester);
    await lifecycle(tester, AppLifecycleState.paused);
    await failSync(tester);
    await lifecycle(tester, AppLifecycleState.resumed);
    await tester.pump(ShownSyncStatus.grace - const Duration(seconds: 1));
    expect(toastShown(), isFalse, reason: 'within the grace');

    await tester.pump(const Duration(seconds: 2));
    expect(toastShown(), isTrue, reason: 'after the grace');

    await finishFakeChatList(tester, client);
  });

  testWidgets('a sync failing while the app is on screen shows', (
    tester,
  ) async {
    await pumpList(tester);
    await failSync(tester);
    expect(toastShown(), isTrue);

    // Between retries the failure stays up, until a sync works.
    client.onSyncStatus.add(
      const SyncStatusUpdate(SyncStatus.waitingForResponse),
    );
    await tester.pump();
    expect(toastShown(), isTrue);
    client.onSyncStatus.add(const SyncStatusUpdate(SyncStatus.finished));
    await tester.pump(const Duration(seconds: 1));
    expect(toastShown(), isFalse);

    await finishFakeChatList(tester, client);
  });
}
