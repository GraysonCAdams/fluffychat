// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
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
    client = await setUpFakeChatList('group details test');
  });

  tearDown(() => tearDownFakeChatList(client));

  void addMember(Room room, String id, String name) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': name},
      senderId: id,
      stateKey: id,
    ),
  );

  Future<void> pumpDetails(WidgetTester tester, Room room) async {
    final prefs = await SharedPreferences.getInstance();
    // The test font draws every letter as wide as it is tall, so long rows
    // overflow; that is not what is tested here.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
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
                builder: (context, state) => ChatDetails(roomId: room.id),
              ),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a bridged group lists members with network and number', (
    tester,
  ) async {
    final room = addFakeChat(client, '!group:x', 'Drew, Harrison');
    addFakeBridge(room);
    addFakeSpace(client, '!imessage:x', 'iMessage', [room.id]);
    addMember(room, '@imessage_tel=3a+14045550142:x', 'Drew Andersen');
    addMember(room, '@imessage_tel=3a+16785550198:x', 'Harrison Young');
    addMember(room, client.userID!, 'Gray');
    addMember(room, '@imessagebot:x', 'iMessage bridge bot');
    room.summary.mJoinedMemberCount = 5;
    await pumpDetails(tester, room);

    expect(find.byType(GroupAvatar), findsOneWidget);
    expect(find.text('iMessage group · 4 people'), findsOneWidget);
    expect(find.text('4 members'), findsOneWidget);
    // The bridge bot is plumbing.
    expect(find.text('iMessage bridge bot'), findsNothing);
    expect(find.text('Drew Andersen'), findsOneWidget);
    expect(find.text('+1 404 555 0142'), findsOneWidget);
    // The user comes last, with the network.
    final you = find.text('You');
    expect(you, findsOneWidget);
    expect(
      tester.getTopLeft(you).dy,
      greaterThan(tester.getTopLeft(find.text('Harrison Young')).dy),
    );
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Leave group'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Leave group')).dy,
      greaterThan(tester.getTopLeft(you).dy),
    );
  });

  testWidgets('a direct chat has no group options', (tester) async {
    final room = addFakeChat(
      client,
      '!kim:x',
      'Kim',
      partner: '@kim:matrix.org',
    );
    await pumpDetails(tester, room);
    expect(find.text('Leave group'), findsNothing);
    expect(find.byType(GroupAvatar), findsNothing);
  });
}
