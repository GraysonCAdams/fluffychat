// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/gestures.dart';
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

/// A pointer over a message leaves its row as it is; keyboard focus on a
/// message rings its bubble.
void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('chat row hover');
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

  testWidgets('hovering a message paints nothing on its row', (tester) async {
    final group = addFakeChat(client, '!grp:x', 'Squad Goals');
    await open(tester, group);
    final row = find
        .descendant(
          of: messageOf('Waffle House?'),
          matching: find.byType(InkWell),
        )
        .first;
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: Offset.zero);
    addTearDown(mouse.removePointer);
    // Over the row, beside the bubble, where the row's own surface is.
    final rect = tester.getRect(row);
    await mouse.moveTo(Offset(rect.left + 40, rect.center.dy));
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(row));
    // The row's ink lands on the page's Material.
    final ink = Material.of(tester.element(row)) as RenderObject;
    expect(ink, isNot(paints..rrect(color: theme.hoverColor)));
    expect(ink, isNot(paints..rect(color: theme.hoverColor)));
    // The ring is for keyboard focus only.
    expect(ringOf(tester, 'Waffle House?').border, isNull);
  });

  testWidgets('keyboard focus on a message rings its bubble', (tester) async {
    final group = addFakeChat(client, '!grp:x', 'Squad Goals');
    await open(tester, group);
    FocusManager.instance.highlightStrategy =
        FocusHighlightStrategy.alwaysTraditional;
    addTearDown(
      () => FocusManager.instance.highlightStrategy =
          FocusHighlightStrategy.automatic,
    );
    final row = find
        .descendant(
          of: messageOf('Waffle House?'),
          matching: find.byType(InkWell),
        )
        .first;
    Focus.of(
      tester.element(
        find.descendant(of: row, matching: find.byType(Material)).first,
      ),
    ).requestFocus();
    await tester.pumpAndSettle();

    final theme = Theme.of(tester.element(row));
    expect(ringOf(tester, 'Waffle House?').border, isNotNull);
    expect(ringOf(tester, 'Eat their bones').border, isNull);
    final ink = Material.of(tester.element(row)) as RenderObject;
    expect(ink, isNot(paints..rrect(color: theme.focusColor)));
  });
}

BoxDecoration ringOf(WidgetTester tester, String text) =>
    tester
            .widget<DecoratedBox>(
              find.ancestor(
                of: find.text(text),
                matching: find.byKey(const ValueKey('message_focus_ring')),
              ),
            )
            .decoration
        as BoxDecoration;
