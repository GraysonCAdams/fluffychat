// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_matrix_features/settings_matrix_features.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/widgets/chat_settings_popup_menu.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('messenger mode test');
  });

  tearDown(() => tearDownFakeChatList(client));

  /// Shows [child] at `/rooms` with the fake Matrix widget around it.
  Future<void> pumpPage(WidgetTester tester, Widget child) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: GoRouter(
            initialLocation: '/rooms',
            routes: [
              GoRoute(
                path: '/rooms',
                builder: (context, state) => Scaffold(body: child),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> closeMenu(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 595));
    await tester.pumpAndSettle();
  }

  /// Opens the account menu and runs [check] on it. The test font draws
  /// every letter as wide as it is tall, so the longer menu entries overflow
  /// the menu's width; those layout reports are not what is tested here.
  Future<void> inAccountMenu(WidgetTester tester, void Function() check) async {
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      onError?.call(details);
    };
    try {
      await tester.tap(find.byKey(const Key('accounts_and_settings_buttons')));
      await tester.pumpAndSettle();
      check();
      await closeMenu(tester);
    } finally {
      FlutterError.onError = onError;
    }
  }

  group('account menu', () {
    testWidgets('hides Matrix-only items in messenger mode', (tester) async {
      final room = addFakeChat(client, '!a:x', 'Drew', partner: '@ghost:x');
      addFakeBridge(room);
      await pumpFakeChatList(tester, client);
      await inAccountMenu(tester, () {
        expect(find.text('Snooze notifications'), findsOneWidget);
        expect(find.text('Set status'), findsNothing);
        expect(find.text('Invite contact'), findsNothing);
        expect(find.text('Add account'), findsNothing);
      });
      await finishFakeChatList(tester, client);
    });

    testWidgets('leaves Create group and Mark all as read out', (
      tester,
    ) async {
      addFakeChat(client, '!kim:x', 'Kim', partner: '@kim:matrix.org');
      await pumpFakeChatList(tester, client);
      await inAccountMenu(tester, () {
        expect(find.text('Create group'), findsNothing);
        expect(find.text('Mark all as read'), findsNothing);
        for (final kept in [
          'Set status',
          'Snooze notifications',
          'Invite contact',
          'Archive',
          'Settings',
        ]) {
          expect(find.text(kept), findsOneWidget, reason: kept);
        }
      });
      await finishFakeChatList(tester, client);
    });

    testWidgets('brings status and invite back after a Matrix contact', (
      tester,
    ) async {
      addFakeChat(client, '!kim:x', 'Kim', partner: '@kim:matrix.org');
      await pumpFakeChatList(tester, client);
      await inAccountMenu(tester, () {
        expect(find.text('Set status'), findsOneWidget);
        expect(find.text('Invite contact'), findsOneWidget);
        // Add account lives in Settings > Advanced either way.
        expect(find.text('Add account'), findsNothing);
      });
      await finishFakeChatList(tester, client);
    });
  });

  group('chat menu', () {
    Future<void> openChatMenu(WidgetTester tester, Room room) async {
      await pumpPage(tester, ChatSettingsPopupMenu(room, true));
      await tester.tap(find.byType(PopupMenuButton<ChatPopupMenuActions>));
      await tester.pumpAndSettle();
    }

    testWidgets('a bridged chat has no encryption and deletes instead', (
      tester,
    ) async {
      final room = addFakeChat(client, '!a:x', 'Drew', partner: '@ghost:x');
      addFakeBridge(room);
      // Decided per chat: a Matrix contact elsewhere changes nothing here.
      addFakeChat(client, '!kim:x', 'Kim', partner: '@kim:matrix.org');
      await openChatMenu(tester, room);
      expect(find.text('Chat details'), findsOneWidget);
      expect(find.text('Search'), findsOneWidget);
      expect(find.text('Encryption'), findsNothing);
      expect(find.text('Leave'), findsNothing);
      expect(find.text('Delete conversation'), findsOneWidget);
      await closeMenu(tester);
    });

    testWidgets('a plain Matrix room keeps the full menu', (tester) async {
      final room = addFakeChat(
        client,
        '!kim:x',
        'Kim',
        partner: '@kim:matrix.org',
      );
      await openChatMenu(tester, room);
      expect(find.text('Encryption'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      expect(find.text('Delete conversation'), findsNothing);
      await closeMenu(tester);
    });

    testWidgets('always show brings encryption back to a bridged chat', (
      tester,
    ) async {
      final room = addFakeChat(client, '!a:x', 'Drew', partner: '@ghost:x');
      addFakeBridge(room);
      await MatrixFeatures.forClient(
        client,
      ).setMode(MatrixFeaturesMode.alwaysShow);
      await openChatMenu(tester, room);
      expect(find.text('Encryption'), findsOneWidget);
      expect(find.text('Leave'), findsOneWidget);
      await closeMenu(tester);
    });
  });

  group('Matrix features settings', () {
    testWidgets('shows what auto decided and overrides a feature', (
      tester,
    ) async {
      await pumpPage(tester, const SettingsMatrixFeatures());
      expect(
        find.text(
          'Auto right now: messenger mode '
          '(0 Matrix contacts outside bridged chats)',
        ),
        findsOneWidget,
      );
      expect(
        find.text('Hidden · shows after your first Matrix contact'),
        findsNWidgets(3),
      );

      await tester.tap(find.byKey(const ValueKey('matrix_feature_status')));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Show'));
      await tester.pumpAndSettle();
      final features = MatrixFeatures.forClient(client);
      expect(features.overrides, {
        MatrixFeature.status: MatrixFeatureOverride.show,
      });
      expect(find.text('Shown · your choice'), findsOneWidget);

      await tester.tap(find.text('Always hide'));
      await tester.pumpAndSettle();
      expect(features.mode, MatrixFeaturesMode.alwaysHide);
      expect(find.text('Hidden · Always hide'), findsNWidgets(6));
    });
  });
}
