// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages, deprecated_member_use

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/add_people/add_people.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/add_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/utils/room_features.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

const _imessage = BridgeInfo(
  name: 'imessage',
  networkId: 'imessage',
  displayName: 'iMessage',
  icon: null,
  loginId: 'login-imessage',
  spaceRoomId: '!imessage:x',
  bridgeBot: '@imessagebot:x',
);

const _gmessages = BridgeInfo(
  name: 'gmessages',
  networkId: 'gmessages',
  displayName: 'Google Messages',
  icon: null,
  loginId: 'login-gmessages',
  spaceRoomId: '!gmessages:x',
  bridgeBot: '@gmessagesbot:x',
);

const _drewGhost = '@imessage_tel=3a+14045550142:x';

/// Stands in for the bridges: answers which bridge owns the room, what
/// `resolve_identifier` knows, and records invites instead of sending them.
class _FakeDelivery extends NewChatDelivery {
  /// What [bridgeOfRoom] answers.
  BridgeInfo? roomBridge = _imessage;

  /// What `resolve_identifier` knows, by identifier.
  final Map<String, BridgeUser> reachable = {};
  final List<String> resolved = [];

  /// Invites that fail, by ghost, with the error they throw.
  final Map<String, Object> inviteErrors = {};
  final List<String> invited = [];

  @override
  Future<void> loadSources(Client client, NewChatSources sources) async {}

  @override
  Future<BridgeInfo?> bridgeOfRoom(Client client, Room room) async =>
      roomBridge;

  @override
  Future<BridgeUser?> resolveOnNetwork(
    Client client,
    BridgeInfo bridge,
    String identifier,
  ) async {
    resolved.add('${bridge.name} $identifier');
    return reachable[identifier];
  }

  @override
  Future<void> invite(Room room, String userId) async {
    final error = inviteErrors[userId];
    if (error != null) throw error;
    invited.add('${room.id} $userId');
  }
}

void main() {
  late FakeChatListClient client;
  late _FakeDelivery delivery;
  late Room room;

  setUp(() async {
    client = await setUpFakeChatList('add people test');
    delivery = _FakeDelivery();
  });

  tearDown(() => tearDownFakeChatList(client));

  void addMember(Room room, String id, String name) {
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'displayname': name},
        senderId: id,
        stateKey: id,
      ),
    );
    // Known presence, so avatars do not read it from the database.
    room.client.presences[id] = CachedPresence.neverSeen(id);
  }

  void setFeatures(Room room, Map<String, Object?> content) => room.setState(
    StrippedStateEvent(
      type: RoomFeatures.eventType,
      content: content,
      senderId: '@imessagebot:x',
      stateKey: 'fi.mau.imessage',
    ),
  );

  /// An iMessage group with Drew, the user and the bridge bot, whose
  /// features take invites, as the iMessage bridge's group rooms do.
  Room bridgedGroup() {
    final group = addFakeChat(client, '!group:x', 'Drew, Harrison');
    addFakeBridge(group);
    addFakeSpace(client, '!imessage:x', 'iMessage', [group.id]);
    // addFakeChat makes its sender a member; this group has no such person.
    group.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        content: {'membership': 'leave'},
        senderId: '@someone:x',
        stateKey: '@someone:x',
      ),
    );
    addMember(group, _drewGhost, 'Drew Andersen');
    addMember(group, client.userID!, 'Gray');
    addMember(group, '@imessagebot:x', 'iMessage bridge bot');
    group.summary
      ..mJoinedMemberCount = 3
      ..mInvitedMemberCount = 0;
    // Its state is loaded, as for a chat the user has opened, so reading
    // the members needs no database.
    group.partial = false;
    setFeatures(group, {
      'member_actions': {'invite': 2, 'kick': 2, 'leave': 1},
    });
    return group;
  }

  Future<GoRouter> pumpApp(WidgetTester tester, String location) async {
    final prefs = await SharedPreferences.getInstance();
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      // The test font is wider than real ones, so long rows overflow; that
      // is not what is tested here.
      if (details.exceptionAsString().contains('overflowed')) return;
      onError?.call(details);
    };
    addTearDown(() => FlutterError.onError = onError);
    tester.view.physicalSize = const Size(800, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final router = GoRouter(
      initialLocation: location,
      routes: [
        GoRoute(
          path: '/rooms/:roomid',
          builder: (_, state) =>
              Scaffold(body: Text('chat ${state.pathParameters['roomid']}')),
          routes: [
            GoRoute(
              path: 'details',
              builder: (_, state) =>
                  ChatDetails(roomId: state.pathParameters['roomid']!),
            ),
            GoRoute(
              path: 'invite',
              builder: (_, _) =>
                  const Scaffold(body: Text('matrix invite page')),
            ),
            GoRoute(
              path: 'add-people',
              builder: (_, state) => AddPeople(
                roomId: state.pathParameters['roomid']!,
                delivery: delivery,
              ),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    return router;
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField), text);
    await tester.pumpAndSettle();
  }

  ListTile tileOf(WidgetTester tester, String text) => tester.widget<ListTile>(
    find.ancestor(of: find.text(text), matching: find.byType(ListTile)).first,
  );

  group('the entry', () {
    testWidgets('a bridged group offers Add people, which opens the picker '
        'on its network', (tester) async {
      room = bridgedGroup();
      await pumpApp(tester, '/rooms/!group:x/details');
      expect(find.text('Invite'), findsNothing);
      await tester.tap(find.text('Add people'));
      await tester.pumpAndSettle();
      expect(find.widgetWithText(AppBar, 'Add people'), findsOneWidget);
      // The picker is limited to the group's network: its icon leads the
      // picked people.
      expect(find.byKey(const ValueKey('group-network')), findsOneWidget);
      expect(find.byTooltip('iMessage'), findsOneWidget);
      expect(find.text('Name, phone number or email'), findsOneWidget);
    });

    testWidgets('a bridged group whose network takes no invites hides it', (
      tester,
    ) async {
      room = bridgedGroup();
      setFeatures(room, {
        'member_actions': {'invite': 0, 'leave': 1},
      });
      await pumpApp(tester, '/rooms/!group:x/details');
      expect(find.text('Add people'), findsNothing);
      expect(find.text('Invite'), findsNothing);
    });

    testWidgets('a Matrix group keeps the invite page', (tester) async {
      room = addFakeChat(client, '!matrix:x', 'Book club');
      addMember(room, '@ana:matrix.org', 'Ana');
      addMember(room, client.userID!, 'Gray');
      await pumpApp(tester, '/rooms/!matrix:x/details');
      expect(find.text('Add people'), findsNothing);
      await tester.tap(find.text('Invite'));
      await tester.pumpAndSettle();
      expect(find.text('matrix invite page'), findsOneWidget);
    });
  });

  group('addMembersEntryOf', () {
    test('needs the power level to invite', () {
      room = bridgedGroup();
      expect(addMembersEntryOf(room), AddMembersEntry.addPeople);
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomPowerLevels,
          content: {
            'invite': 1,
            'users': {client.userID!: 0},
          },
          senderId: '@imessagebot:x',
          stateKey: '',
        ),
      );
      expect(addMembersEntryOf(room), isNull);
    });

    test('a bridged room without member_actions offers nothing', () {
      room = bridgedGroup();
      setFeatures(room, {});
      expect(addMembersEntryOf(room), isNull);
    });

    test('a plain room offers the invite page', () {
      room = addFakeChat(client, '!matrix:x', 'Book club');
      expect(addMembersEntryOf(room), AddMembersEntry.invite);
    });
  });

  group('bridgeOfRoom', () {
    test('matches the bridge bot, else the space', () {
      room = bridgedGroup();
      expect(bridgeOfRoom([_gmessages, _imessage], room), same(_imessage));
      const noBot = BridgeInfo(
        name: 'imessage',
        networkId: 'imessage',
        displayName: 'iMessage',
        icon: null,
        loginId: 'login-imessage',
        spaceRoomId: '!imessage:x',
      );
      expect(bridgeOfRoom([_gmessages, noBot], room), same(noBot));
      // The bot wins over a space that another bridge claims.
      const botOnly = BridgeInfo(
        name: 'imessage',
        networkId: 'imessage',
        displayName: 'iMessage',
        icon: null,
        loginId: 'login-imessage',
        bridgeBot: '@imessagebot:x',
      );
      const sameSpace = BridgeInfo(
        name: 'other',
        networkId: 'other',
        displayName: 'Other',
        icon: null,
        loginId: 'login-other',
        spaceRoomId: '!imessage:x',
      );
      expect(bridgeOfRoom([sameSpace, botOnly], room), same(botOnly));
      expect(bridgeOfRoom([_gmessages], room), isNull);
    });
  });

  group('the picker', () {
    testWidgets('a typed phone number is resolved and its ghost invited', (
      tester,
    ) async {
      room = bridgedGroup();
      delivery.reachable['+14045550199'] = const BridgeUser(
        id: 'tel:+14045550199',
        mxid: '@imessage_tel=3a+14045550199:x',
      );
      await pumpApp(tester, '/rooms/!group:x/add-people');
      await search(tester, '404-555-0199');
      await tester.tap(find.text('Phone number'));
      await tester.pumpAndSettle();
      expect(delivery.resolved, ['imessage +14045550199']);
      expect(
        find.byKey(const ValueKey('group-chip-+14045550199')),
        findsOneWidget,
      );
      expect(delivery.invited, isEmpty);
      await tester.tap(find.text('Add 1 person'));
      await tester.pumpAndSettle();
      expect(delivery.invited, ['!group:x @imessage_tel=3a+14045550199:x']);
      expect(find.text('chat !group:x'), findsOneWidget);
      expect(find.text('1 person added'), findsOneWidget);
    });

    testWidgets('a typed email is resolved and its ghost invited', (
      tester,
    ) async {
      room = bridgedGroup();
      delivery.reachable['bob@example.com'] = const BridgeUser(
        id: 'mailto:bob@example.com',
        mxid: '@imessage_mailto=3abob=40example.com:x',
      );
      await pumpApp(tester, '/rooms/!group:x/add-people');
      await search(tester, 'Bob@example.com');
      await tester.tap(find.text('Email address'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 1 person'));
      await tester.pumpAndSettle();
      expect(delivery.resolved, ['imessage bob@example.com']);
      expect(delivery.invited, [
        '!group:x @imessage_mailto=3abob=40example.com:x',
      ]);
    });

    testWidgets('someone the network does not reach is named and not added', (
      tester,
    ) async {
      room = bridgedGroup();
      await pumpApp(tester, '/rooms/!group:x/add-people');
      await search(tester, '404-555-0177');
      await tester.tap(find.text('Phone number'));
      await tester.pumpAndSettle();
      expect(delivery.resolved, ['imessage +14045550177']);
      expect(find.text('+1 404 555 0177: Not on iMessage'), findsOneWidget);
      expect(
        find.byKey(const ValueKey('group-chip-+14045550177')),
        findsNothing,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(delivery.invited, isEmpty);
    });

    testWidgets('a failed invite is listed with its reason', (tester) async {
      room = bridgedGroup();
      const ghost = '@imessage_tel=3a+14045550199:x';
      delivery.reachable['+14045550199'] = const BridgeUser(
        id: 'tel:+14045550199',
        mxid: ghost,
      );
      delivery.inviteErrors[ghost] = MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'The bridge refused the invite',
      });
      await pumpApp(tester, '/rooms/!group:x/add-people');
      await search(tester, '404-555-0199');
      await tester.tap(find.text('Phone number'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Add 1 person'));
      await tester.pumpAndSettle();
      expect(delivery.invited, isEmpty);
      expect(find.text('Not added'), findsOneWidget);
      expect(
        find.textContaining('+1 404 555 0199: ', findRichText: true),
        findsOneWidget,
      );
      expect(find.text('chat !group:x'), findsNothing);
    });

    testWidgets('a member is shown as one and cannot be picked', (
      tester,
    ) async {
      room = bridgedGroup();
      addFakeChat(client, '!drew:x', 'Drew Andersen', partner: _drewGhost);
      await pumpApp(tester, '/rooms/!group:x/add-people');
      await search(tester, 'drew');
      expect(tileOf(tester, 'Drew Andersen').enabled, isFalse);
      expect(find.text('Already in this group'), findsOneWidget);
      await tester.tap(find.text('Drew Andersen'), warnIfMissed: false);
      await tester.pumpAndSettle();
      expect(delivery.resolved, isEmpty);
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('a number that resolves to a member is not picked', (
      tester,
    ) async {
      room = bridgedGroup();
      delivery.reachable['+14045550142'] = const BridgeUser(
        id: 'tel:+14045550142',
        mxid: _drewGhost,
      );
      await pumpApp(tester, '/rooms/!group:x/add-people');
      await search(tester, '404-555-0142');
      await tester.tap(find.text('Phone number'));
      await tester.pumpAndSettle();
      expect(
        find.text('+1 404 555 0142: Already in this group'),
        findsOneWidget,
      );
      expect(find.byType(FloatingActionButton), findsNothing);
    });

    testWidgets('a bridge the user has no login on says so', (tester) async {
      room = bridgedGroup();
      delivery.roomBridge = null;
      await pumpApp(tester, '/rooms/!group:x/add-people');
      expect(
        find.text(
          "iMessage can't be reached right now, so no one can be added. "
          'Try again later.',
        ),
        findsOneWidget,
      );
      expect(find.byType(TextField), findsNothing);
    });
  });
}
