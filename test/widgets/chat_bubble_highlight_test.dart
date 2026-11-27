// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

/// A message the chat jumps to, as from a search result or a reply, is
/// marked by its bubble turning brighter for a moment, not by a tint
/// across its row.
void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('chat bubble highlight');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Opens [room] with a message from someone else and one of the user's
  /// own in it.
  Future<ChatController> open(WidgetTester tester, Room room) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('chat list')),
          routes: [
            GoRoute(
              path: 'chat',
              builder: (_, _) => ChatPage(roomId: room.id),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _Matrix(client, prefs),
        child: MaterialApp.router(
          theme: ThemeData(brightness: Brightness.dark),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/chat');
    await settle(tester);
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [
                    MatrixEvent(
                      type: EventTypes.Message,
                      content: {'msgtype': 'm.text', 'body': 'Eat their bones'},
                      senderId: '@drew:x',
                      eventId: r'$bones',
                      originServerTs: DateTime(2026, 11, 27, 9),
                    ),
                    MatrixEvent(
                      type: EventTypes.Message,
                      content: {'msgtype': 'm.text', 'body': 'Waffle House?'},
                      senderId: client.userID!,
                      eventId: r'$waffle',
                      originServerTs: DateTime(2026, 11, 27, 10),
                    ),
                  ],
                ),
              ),
            },
          ),
        ),
      ),
    );
    await settle(tester);
    return tester.state<ChatController>(find.byType(ChatPageWithRoom));
  }

  Finder messageOf(String text) =>
      find.ancestor(of: find.text(text), matching: find.byType(Message));

  /// How bright the flash over [text]'s bubble is: the alpha of its colour,
  /// 0 while the bubble shows its normal colour.
  double flashOf(WidgetTester tester, String text) {
    return tester
        .state<BubbleHighlightState>(
          find.ancestor(
            of: find.text(text),
            matching: find.byType(BubbleHighlight),
          ),
        )
        .amount;
  }

  /// Whether [text]'s row has a tint behind it.
  bool rowTinted(WidgetTester tester, String text) {
    final theme = Theme.of(tester.element(messageOf(text)));
    return tester
        .widgetList<Material>(
          find.descendant(of: messageOf(text), matching: find.byType(Material)),
        )
        .any(
          (material) =>
              material.color ==
              theme.colorScheme.secondaryContainer.withAlpha(128),
        );
  }

  for (final (who, text) in [
    ('the user\'s own', 'Waffle House?'),
    ('someone else\'s', 'Eat their bones'),
  ]) {
    testWidgets('$who message brightens its bubble, then fades back', (
      tester,
    ) async {
      final group = addFakeChat(client, '!grp:x', 'Squad Goals');
      final chat = await open(tester, group);
      final eventId = text == 'Waffle House?' ? r'$waffle' : r'$bones';
      final other = text == 'Waffle House?'
          ? 'Eat their bones'
          : 'Waffle House?';
      expect(flashOf(tester, text), 0);

      unawaited(chat.scrollToEventId(eventId));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(chat.scrollToEventIdMarker, eventId);
      expect(rowTinted(tester, text), isFalse);
      expect(flashOf(tester, text), greaterThan(0));
      // Only that message's bubble.
      expect(flashOf(tester, other), 0);

      // Still bright while it holds, then back to normal and forgotten,
      // so a rebuild does not light it again.
      await tester.pump(const Duration(milliseconds: 1000));
      expect(flashOf(tester, text), greaterThan(0));
      await tester.pump(const Duration(milliseconds: 2600));
      expect(flashOf(tester, text), 0);
      expect(chat.scrollToEventIdMarker, isNull);
      expect(rowTinted(tester, text), isFalse);
    });
  }
}
