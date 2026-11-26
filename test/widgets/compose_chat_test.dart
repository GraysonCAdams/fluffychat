// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/pages/new_private_chat/start_chat_sheet.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

const _imessage = BridgeInfo(
  name: 'imessage',
  networkId: 'imessage',
  displayName: 'iMessage',
  icon: null,
  loginId: 'login-imessage',
  bridgeBot: '@imessagebot:x',
);

const _gmessages = BridgeInfo(
  name: 'gmessages',
  networkId: 'gmessages',
  displayName: 'Google Messages',
  icon: null,
  loginId: 'login-gmessages',
  bridgeBot: '@gmessagesbot:x',
);

const _telegram = BridgeInfo(
  name: 'telegram',
  networkId: 'telegram',
  displayName: 'Telegram',
  icon: null,
  loginId: 'login-telegram',
);

const _imessageGroup = BridgeGroupType(id: 'group', nameAllowed: true);
const _smsGroup = BridgeGroupType(id: 'group', minParticipants: 2);

const _quinnGhost = '@imessage_quinn:x';
const _quinbyGhost = '@imessage_quinby:x';

/// Records what the compose screen asks the bridges and the rooms for
/// instead of reaching them.
class _FakeDelivery extends NewChatDelivery {
  final Client client;

  _FakeDelivery(this.client);

  List<BridgeContactInput> bridgeContacts = const [];
  bool bridges = true;

  /// What the group network picker answers; null is the user closing it.
  GroupNetwork? groupNetwork = const GroupNetwork(_imessage, _imessageGroup);
  final List<String> groupPicks = [];

  /// The ghost the group network picker resolves each first member to.
  final Map<String, String> ghosts = {'Quinn Imsg': _quinnGhost};

  /// What `resolve_identifier` knows, by identifier.
  final Map<String, BridgeUser> reachable = {};
  final List<String> resolved = [];

  /// What `resolve_identifier` throws instead of answering, when set.
  Object? resolveError;

  /// One entry per network picker opened for a direct chat.
  final List<String> networkPicks = [];

  /// One entry per direct chat started, and per group created (network,
  /// participants and name).
  final List<String> started = [];
  final List<String> created = [];

  /// One entry per message sent: room and text.
  final List<String> sent = [];

  /// The history each room's timeline holds, newest first.
  final Map<String, List<Event>> history = {};

  @override
  Future<void> loadSources(Client client, NewChatSources sources) async {
    sources.bridges = [_imessage, _gmessages, _telegram];
    sources.bridgeContacts = bridgeContacts;
  }

  @override
  Future<bool> hasBridges(Client client) async => bridges;

  /// When set, the group network picker is the real sheet, asking this
  /// instead of the bridges.
  Future<BridgeUser?> Function(BridgeInfo bridge, String identifier)?
  sheetResolve;

  @override
  Future<(GroupNetwork, BridgeUser)?> pickGroupNetwork(
    BuildContext context,
    Client client,
    NewChatPerson person,
  ) async {
    groupPicks.add(person.name);
    final resolve = sheetResolve;
    if (resolve != null) {
      final choice = await showModalBottomSheet<StartChatChoice>(
        context: context,
        builder: (_) => StartChatSheet(
          person: person,
          bridges: const [_imessage, _gmessages],
          resolve: resolve,
          group: true,
        ),
      );
      if (choice == null) return null;
      final type = choice.bridge.name == 'imessage'
          ? _imessageGroup
          : _smsGroup;
      return (GroupNetwork(choice.bridge, type), choice.resolved);
    }
    final network = groupNetwork;
    if (network == null) return null;
    return (
      network,
      BridgeUser(id: 'id-${person.name}', mxid: ghosts[person.name]),
    );
  }

  @override
  Future<BridgeUser?> resolveOnNetwork(
    Client client,
    BridgeInfo bridge,
    String identifier,
  ) async {
    resolved.add('${bridge.name} $identifier');
    final error = resolveError;
    if (error != null) throw error;
    return reachable[identifier];
  }

  @override
  Future<StartChatChoice?> pickNetwork(
    BuildContext context,
    Client client,
    NewChatPerson person,
  ) async {
    networkPicks.add(person.name);
    final identifier = person.phone ?? person.name;
    return StartChatChoice(_imessage, identifier, BridgeUser(id: identifier));
  }

  @override
  Future<String> startChat(Client client, StartChatChoice choice) async {
    started.add('${choice.bridge.name} ${choice.identifier}');
    addFakeChat(client, '!new-dm:x', 'New DM', partner: '@imessage_new:x');
    return '!new-dm:x';
  }

  @override
  Future<CreatedGroup> createGroup(
    Client client,
    GroupNetwork network,
    List<GroupMember> members,
    String? name,
  ) async {
    created.add(
      '${network.bridge.name}/${network.type.id} '
      '${members.map((member) => member.user.id).join(',')} "$name"',
    );
    addFakeChat(client, '!group:x', 'G');
    return const CreatedGroup('!group:x');
  }

  @override
  Future<void> sendText(Room room, String text) async {
    sent.add('${room.id}: $text');
  }

  @override
  Future<Timeline> openTimeline(
    ExistingChat chat, {
    void Function()? onUpdate,
  }) async => Timeline(
    room: chat.room,
    chunk: TimelineChunk(events: history[chat.room.id] ?? []),
  );
}

void main() {
  late FakeChatListClient client;
  late _FakeDelivery delivery;

  Event text(Room room, String body, String senderId) => Event(
    content: {'msgtype': 'm.text', 'body': body},
    type: EventTypes.Message,
    eventId: '\$${room.id}-$body',
    senderId: senderId,
    originServerTs: DateTime(2026, 11, 20, 10),
    status: EventStatus.synced,
    room: room,
  );

  void member(Room room, String id, String name) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': name},
      senderId: id,
      stateKey: id,
    ),
  );

  /// An iMessage group with Quinn and Quinby, as the bridge sets one up:
  /// the user, the bridge bot and the two ghosts.
  Room addTripGroup() {
    final room = Room(id: '!trip:x', client: client);
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomName,
        content: {'name': 'Trip crew'},
        senderId: _imessage.bridgeBot!,
        stateKey: '',
      ),
    );
    member(room, client.userID!, 'Gray');
    member(room, _imessage.bridgeBot!, 'iMessage bridge bot');
    member(room, _quinnGhost, 'Quinn Imsg');
    member(room, _quinbyGhost, 'Quinby Imsg');
    addFakeBridge(room, bot: _imessage.bridgeBot!);
    room.lastEvent = text(room, 'trip plans', _quinnGhost);
    client.rooms.add(room);
    delivery.history[room.id] = [text(room, 'trip plans', _quinnGhost)];
    return room;
  }

  setUp(() async {
    client = await setUpFakeChatList('compose test');
    delivery = _FakeDelivery(client)
      ..bridgeContacts = [
        BridgeContactInput(
          _imessage,
          const BridgeUser(
            id: 'tel:+14045550101',
            name: 'Quinn Imsg',
            identifiers: ['tel:+14045550101'],
          ),
        ),
        BridgeContactInput(
          _imessage,
          const BridgeUser(
            id: 'tel:+14045550102',
            name: 'Quinby Imsg',
            identifiers: ['tel:+14045550102'],
            mxid: _quinbyGhost,
          ),
        ),
        BridgeContactInput(
          _gmessages,
          const BridgeUser(
            id: '1.3',
            name: 'Quill Sms',
            identifiers: ['tel:+14045550103'],
          ),
        ),
        BridgeContactInput(
          _telegram,
          const BridgeUser(
            id: '77',
            name: 'Quentin Tg',
            mxid: '@telegram_77:x',
          ),
        ),
      ];
    final quade = addFakeChat(
      client,
      '!quade:x',
      'Quade Matrix',
      partner: '@quade:x',
    );
    delivery.history[quade.id] = [text(quade, 'see you soon', '@quade:x')];
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<void> pump(WidgetTester tester, {bool startGroup = false}) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => NewPrivateChat(
            deeplink: null,
            delivery: delivery,
            startGroup: startGroup,
          ),
        ),
        GoRoute(
          path: '/rooms/:roomid',
          builder: (_, state) =>
              Scaffold(body: Text('chat ${state.pathParameters['roomid']}')),
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
  }

  final toField = find.byKey(const ValueKey('compose-to'));
  final messageField = find.byKey(const ValueKey('compose-message'));
  final nameField = find.byKey(const ValueKey('group-name'));
  final groupTitle = find.byKey(const ValueKey('group-title'));
  final nameSave = find.byKey(const ValueKey('group-name-save'));
  Finder chip(String key) => find.byKey(ValueKey('recipient-chip-$key'));

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(toField, text);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  Future<void> pick(WidgetTester tester, String query, String name) async {
    await search(tester, query);
    await tester.tap(find.text(name).last);
    await tester.pumpAndSettle();
  }

  Future<void> sendMessage(WidgetTester tester, String text) async {
    await tester.enterText(messageField, text);
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await tester.pumpAndSettle();
  }

  String? composerHint(WidgetTester tester) =>
      tester.widget<TextField>(messageField).decoration?.hintText;

  ListTile tileOf(WidgetTester tester, String name) => tester.widget<ListTile>(
    find.ancestor(of: find.text(name), matching: find.byType(ListTile)).first,
  );

  testWidgets('a tap makes a chip; backspace on the empty field removes it', (
    tester,
  ) async {
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    expect(chip('+14045550101'), findsOneWidget);
    expect(
      tester.widget<TextField>(toField).controller!.text,
      isEmpty,
      reason: 'the search clears for the next person',
    );
    // One person is not a group yet: no network is asked for.
    expect(delivery.groupPicks, isEmpty);

    await tester.sendKeyEvent(LogicalKeyboardKey.backspace);
    await tester.pumpAndSettle();
    expect(chip('+14045550101'), findsNothing);
  });

  testWidgets('a chip\'s remove button takes the person out', (tester) async {
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    await tester.tap(
      find.descendant(
        of: chip('+14045550101'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();
    expect(chip('+14045550101'), findsNothing);
  });

  testWidgets('Enter makes a chip of a typed number', (tester) async {
    await pump(tester);
    await tester.enterText(toField, '404-555-0199');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(chip('+14045550199'), findsOneWidget);
  });

  testWidgets('one person with a chat shows its history and sends there', (
    tester,
  ) async {
    await pump(tester);
    await pick(tester, 'quade', 'Quade Matrix');
    expect(chip('@quade:x'), findsOneWidget);
    expect(find.text('see you soon'), findsOneWidget);
    expect(groupTitle, findsNothing);

    await sendMessage(tester, 'hi');
    expect(delivery.sent, ['!quade:x: hi']);
    expect(delivery.networkPicks, isEmpty);
    expect(delivery.started, isEmpty);
    expect(find.text('chat !quade:x'), findsOneWidget);
  });

  testWidgets('one new person: the first message starts the chat', (
    tester,
  ) async {
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    expect(find.text('Your first message starts the chat'), findsOneWidget);
    expect(find.text('You pick the network when you send'), findsOneWidget);
    expect(groupTitle, findsNothing);

    await sendMessage(tester, 'hey');
    expect(delivery.networkPicks, ['Quinn Imsg']);
    expect(delivery.started, ['imessage +14045550101']);
    expect(delivery.sent, ['!new-dm:x: hey']);
    expect(find.text('chat !new-dm:x'), findsOneWidget);
  });

  testWidgets('two people with a group show it and send there', (tester) async {
    addTripGroup();
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    await pick(tester, 'quinby', 'Quinby Imsg');
    expect(delivery.groupPicks, ['Quinn Imsg']);
    expect(chip('+14045550101'), findsOneWidget);
    expect(chip('+14045550102'), findsOneWidget);
    // The composer names the group's network; no line under the To field
    // repeats it.
    expect(composerHint(tester), 'iMessage');
    expect(find.byKey(const ValueKey('compose-network')), findsNothing);
    expect(find.text('trip plans'), findsOneWidget);
    // The group has its name already.
    expect(groupTitle, findsNothing);

    await sendMessage(tester, 'yo');
    expect(delivery.created, isEmpty);
    expect(delivery.sent, ['!trip:x: yo']);
    expect(find.text('chat !trip:x'), findsOneWidget);
    // A group bubble looks its sender up in the database, whose
    // transaction holds a ten-second timer in the test's fake time.
    await tester.pump(const Duration(seconds: 11));
  });

  testWidgets('a group with someone else in it is not theirs', (tester) async {
    final trip = addTripGroup();
    member(trip, '@imessage_other:x', 'Someone else');
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    await pick(tester, 'quinby', 'Quinby Imsg');
    expect(find.text('trip plans'), findsNothing);
    expect(find.text('Your first message creates the group'), findsOneWidget);
  });

  testWidgets('two new people: the first message creates the named group', (
    tester,
  ) async {
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    expect(groupTitle, findsNothing);
    await pick(tester, 'quinby', 'Quinby Imsg');
    expect(find.text('Your first message creates the group'), findsOneWidget);
    expect(composerHint(tester), 'iMessage');
    expect(find.byKey(const ValueKey('compose-network')), findsNothing);
    // The name is set from the title, not a field on the screen.
    expect(nameField, findsNothing);
    expect(
      find.descendant(of: groupTitle, matching: find.text('New group chat')),
      findsOneWidget,
    );

    await tester.tap(groupTitle);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsOneWidget);
    expect(find.text('Group name (optional)'), findsOneWidget);
    expect(
      find.descendant(of: nameField, matching: find.text('Name')),
      findsOneWidget,
    );
    await tester.enterText(nameField, 'Trip');
    await tester.tap(nameSave);
    await tester.pumpAndSettle();
    expect(find.byType(AlertDialog), findsNothing);
    expect(
      find.descendant(of: groupTitle, matching: find.text('Trip')),
      findsOneWidget,
    );

    await sendMessage(tester, 'yo');
    expect(delivery.created, [
      'imessage/group id-Quinn Imsg,tel:+14045550102 "Trip"',
    ]);
    expect(delivery.sent, ['!group:x: yo']);
    expect(find.text('chat !group:x'), findsOneWidget);
  });

  testWidgets('a network without group names shows no name field', (
    tester,
  ) async {
    delivery.groupNetwork = const GroupNetwork(_gmessages, _smsGroup);
    delivery.bridgeContacts = [
      for (final contact in delivery.bridgeContacts)
        BridgeContactInput(_gmessages, contact.user),
    ];
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    await pick(tester, 'quinby', 'Quinby Imsg');
    expect(chip('+14045550102'), findsOneWidget);
    // The title stays plain: there is no name to set.
    expect(groupTitle, findsNothing);
    expect(find.text('New group chat'), findsOneWidget);

    await sendMessage(tester, 'yo');
    expect(delivery.created, [
      'gmessages/group id-Quinn Imsg,tel:+14045550102 "null"',
    ]);
  });

  testWidgets('a cleared name puts "New group chat" back in the title', (
    tester,
  ) async {
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    await pick(tester, 'quinby', 'Quinby Imsg');
    await tester.tap(groupTitle);
    await tester.pumpAndSettle();
    await tester.enterText(nameField, 'Trip');
    await tester.tap(nameSave);
    await tester.pumpAndSettle();

    await tester.tap(groupTitle);
    await tester.pumpAndSettle();
    expect(tester.widget<TextField>(nameField).controller!.text, 'Trip');
    await tester.enterText(nameField, '');
    await tester.tap(nameSave);
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: groupTitle, matching: find.text('New group chat')),
      findsOneWidget,
    );

    // Cancel leaves the name as it was.
    await tester.tap(groupTitle);
    await tester.pumpAndSettle();
    await tester.enterText(nameField, 'Other');
    await tester.tap(find.text('Cancel'));
    await tester.pumpAndSettle();
    expect(
      find.descendant(of: groupTitle, matching: find.text('New group chat')),
      findsOneWidget,
    );

    await sendMessage(tester, 'yo');
    expect(delivery.created, [
      'imessage/group id-Quinn Imsg,tel:+14045550102 "null"',
    ]);
  });

  testWidgets('a network that needs a name holds Save and Send until set', (
    tester,
  ) async {
    delivery.groupNetwork = const GroupNetwork(
      _imessage,
      BridgeGroupType(id: 'group', nameAllowed: true, nameRequired: true),
    );
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    await pick(tester, 'quinby', 'Quinby Imsg');
    await tester.enterText(messageField, 'yo');
    await tester.pump();
    IconButton send() =>
        tester.widget<IconButton>(find.byKey(const ValueKey('compose-send')));
    expect(send().onPressed, isNull);

    await tester.tap(groupTitle);
    await tester.pumpAndSettle();
    expect(find.text('Group name'), findsOneWidget);
    TextButton save() => tester.widget<TextButton>(nameSave);
    expect(save().onPressed, isNull);
    await tester.enterText(nameField, '   ');
    await tester.pump();
    expect(save().onPressed, isNull);
    await tester.enterText(nameField, 'Trip');
    await tester.pump();
    expect(save().onPressed, isNotNull);
    await tester.tap(nameSave);
    await tester.pumpAndSettle();
    expect(send().onPressed, isNotNull);

    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await tester.pumpAndSettle();
    expect(delivery.created, [
      'imessage/group id-Quinn Imsg,tel:+14045550102 "Trip"',
    ]);
  });

  group('To field at 412dp', () {
    /// Two people with short names, so that in the test font, whose
    /// letters are all a square, their chips are as wide as real names'.
    Future<void> pumpPhone(WidgetTester tester) async {
      delivery.bridgeContacts = [
        BridgeContactInput(
          _imessage,
          const BridgeUser(
            id: 'tel:+14045550101',
            name: 'Quinn',
            identifiers: ['tel:+14045550101'],
          ),
        ),
        BridgeContactInput(
          _imessage,
          const BridgeUser(
            id: 'tel:+14045550102',
            name: 'Romy',
            identifiers: ['tel:+14045550102'],
            mxid: _quinbyGhost,
          ),
        ),
      ];
      delivery.ghosts['Quinn'] = _quinnGhost;
      await pump(tester);
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      await tester.pumpAndSettle();
    }

    final label = find.byKey(const ValueKey('compose-to-label'));

    testWidgets('"To:" sits on the centre line of the chips and the field', (
      tester,
    ) async {
      await pumpPhone(tester);
      expect(
        tester.getCenter(label).dy,
        moreOrLessEquals(tester.getCenter(toField).dy, epsilon: 1),
      );
      await pick(tester, 'quinn', 'Quinn');
      await pick(tester, 'romy', 'Romy');
      for (final key in ['+14045550101', '+14045550102']) {
        expect(
          tester.getCenter(label).dy,
          moreOrLessEquals(tester.getCenter(chip(key)).dy, epsilon: 1),
        );
      }
    });

    testWidgets('the field stays on the chips\' line with two chips', (
      tester,
    ) async {
      await pumpPhone(tester);
      await pick(tester, 'quinn', 'Quinn');
      await pick(tester, 'romy', 'Romy');
      final lastChip = tester.getRect(chip('+14045550102'));
      final field = tester.getRect(toField);
      expect(field.left, greaterThan(lastChip.right));
      expect(field.center.dy, moreOrLessEquals(lastChip.center.dy, epsilon: 1));
    });
  });

  testWidgets('the group\'s network blocks people it cannot reach', (
    tester,
  ) async {
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    await pick(tester, 'quinby', 'Quinby Imsg');

    await search(tester, 'qu');
    // A Telegram contact has nothing iMessage can look up.
    expect(tileOf(tester, 'Quentin Tg').enabled, isFalse);
    // A Matrix chat is on no network.
    expect(tileOf(tester, 'Quade Matrix').enabled, isFalse);
    expect(find.text('Not on iMessage'), findsNWidgets(2));
    // A phone number is asked about on the pick.
    expect(tileOf(tester, 'Quill Sms').enabled, isTrue);
    await tester.tap(find.text('Quill Sms'));
    await tester.pumpAndSettle();
    expect(delivery.resolved, ['imessage +14045550103']);
    expect(chip('+14045550103'), findsNothing);
    expect(find.text('Quill Sms: Not on iMessage'), findsOneWidget);
  });

  testWidgets('a network that fails to answer is shown, never skipped', (
    tester,
  ) async {
    var appleDown = true;
    final asked = <String>[];
    delivery.sheetResolve = (bridge, identifier) async {
      asked.add(bridge.name);
      if (bridge.name == 'imessage' && appleDown) {
        throw const BridgeProvisioningException(
          'imessage',
          statusCode: 500,
          errcode: 'M_UNKNOWN',
          error: 'user not found on iMessage',
        );
      }
      return BridgeUser(id: '${bridge.name}-$identifier', mxid: _quinnGhost);
    };
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    await pick(tester, 'quinby', 'Quinby Imsg');

    // Google Messages reaches Quinn, but iMessage failing is no "not
    // found": the sheet stays open with the bridge's reason.
    expect(find.byType(StartChatSheet), findsOneWidget);
    expect(
      find.text("Couldn't check: user not found on iMessage"),
      findsOneWidget,
    );
    expect(chip('+14045550102'), findsNothing);
    expect(find.byKey(const ValueKey('group-network')), findsNothing);
    expect(delivery.created, isEmpty);

    appleDown = false;
    await tester.tap(find.byTooltip('Try again'));
    await tester.pumpAndSettle();
    expect(asked.where((name) => name == 'imessage'), hasLength(2));
    // Both networks answer now, so the user still picks.
    expect(find.byType(StartChatSheet), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(StartChatSheet),
        matching: find.text('iMessage'),
      ),
    );
    await tester.pumpAndSettle();
    expect(chip('+14045550102'), findsOneWidget);
    expect(composerHint(tester), 'iMessage');
    expect(delivery.created, isEmpty);
  });

  testWidgets('a later person the network fails on is named with the reason', (
    tester,
  ) async {
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    await pick(tester, 'quinby', 'Quinby Imsg');
    delivery.resolveError = const BridgeProvisioningException(
      'imessage',
      statusCode: 500,
      error: 'lookup refused',
    );
    await search(tester, 'quill');
    await tester.tap(find.text('Quill Sms'));
    await tester.pumpAndSettle();
    expect(
      find.text("iMessage couldn't check Quill Sms: lookup refused"),
      findsOneWidget,
    );
    expect(chip('+14045550103'), findsNothing);

    delivery.resolveError = null;
    delivery.reachable['+14045550103'] = const BridgeUser(
      id: 'tel:+14045550103',
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(chip('+14045550103'), findsOneWidget);
  });

  testWidgets('Create group on an account without bridges goes to Matrix', (
    tester,
  ) async {
    delivery.bridges = false;
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => NewPrivateChat(
            deeplink: null,
            delivery: delivery,
            startGroup: true,
          ),
        ),
        GoRoute(
          path: '/rooms/newgroup',
          builder: (_, _) => const Scaffold(body: Text('matrix group')),
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
    expect(find.text('matrix group'), findsOneWidget);
  });
}
