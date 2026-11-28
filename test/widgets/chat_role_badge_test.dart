// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/matrix_features.dart';
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

/// The moderator badge before a sender's name: noise in a bridged chat,
/// whose bridge makes its bot and puppets moderators, so messenger mode
/// leaves it out there unless the user asks for it.
void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('chat role badge');
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

  /// A group in which Drew, a moderator, sent a message; bridged to
  /// iMessage when [bridged].
  Room group({required bool bridged}) {
    final room = addFakeChat(client, '!grp:x', 'Squad Goals');
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomPowerLevels,
        content: {
          'users': {'@drew:x': 50},
        },
        senderId: '@drew:x',
        stateKey: '',
      ),
    );
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'displayname': 'Drew'},
        senderId: '@drew:x',
        stateKey: '@drew:x',
      ),
    );
    if (bridged) addFakeBridge(room);
    return room;
  }

  Future<void> open(WidgetTester tester, Room room) async {
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
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
                  ],
                ),
              ),
            },
          ),
        ),
      ),
    );
    await settle(tester);
    expect(find.text('Eat their bones'), findsOneWidget);
  }

  final badge = find.byIcon(Icons.add_moderator_outlined);

  testWidgets('a bridged chat in messenger mode shows no moderator badge', (
    tester,
  ) async {
    final room = group(bridged: true);
    expect(
      MatrixFeatures.forClient(client).signals.messengerMode,
      isTrue,
      reason: 'every chat is bridged',
    );
    await open(tester, room);
    expect(badge, findsNothing);
  });

  testWidgets('the badge comes back when the user asks for it', (tester) async {
    final room = group(bridged: true);
    await MatrixFeatures.forClient(
      client,
    ).setOverride(MatrixFeature.roleBadges, MatrixFeatureOverride.show);
    await open(tester, room);
    expect(badge, findsOneWidget);
  });

  testWidgets('a plain Matrix room shows the badge', (tester) async {
    final room = group(bridged: false);
    await open(tester, room);
    expect(badge, findsOneWidget);
  });
}
