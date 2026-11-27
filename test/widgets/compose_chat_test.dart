// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:async';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/composer_attachments.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_picker.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/utils/android_direct_share.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/utils/share_items.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
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
import '../utils/merged_contacts/fake_rooms.dart' show setMergedContacts;

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

/// A network of usernames, which takes no phone numbers.
const _linkedin = BridgeInfo(
  name: 'linkedin',
  networkId: 'linkedin',
  displayName: 'LinkedIn',
  icon: null,
  loginId: 'login-linkedin',
  bridgeBot: '@linkedinbot:x',
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

  /// The kind of group each bridge creates, by bridge name.
  final Map<String, BridgeGroupType> groupTypes = {
    'imessage': _imessageGroup,
    'gmessages': _smsGroup,
  };

  /// What `resolve_identifier` knows, by bridge name and identifier.
  final Map<String, BridgeUser> reachable = {};
  final List<String> resolved = [];

  /// What `resolve_identifier` throws instead of answering, for every
  /// bridge, or by bridge name.
  Object? resolveError;
  final Map<String, Object> resolveErrors = {};

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
    await sourcesGate?.future;
    sources.bridges = bridgeList;
    sources.bridgeContacts = bridgeContacts;
    // As the real sources do when the bridges answer.
    sources.onChanged();
  }

  /// The bridges the user is logged in to.
  List<BridgeInfo> bridgeList = const [
    _imessage,
    _gmessages,
    _telegram,
    _linkedin,
  ];

  /// When set, the bridges answer once it completes.
  Completer<void>? sourcesGate;

  @override
  Future<bool> hasBridges(Client client) async => bridges;

  /// What each bridge declares it looks people up by, by bridge name;
  /// a bridge with none is what its network is known to take.
  final Map<String, BridgeLookups> lookups = {};

  @override
  Future<BridgeLookups> lookupsOn(Client client, BridgeInfo bridge) async =>
      lookups[bridge.name] ?? BridgeLookups.knownFor(bridge);

  @override
  Future<BridgeGroupType?> groupTypeOn(
    Client client,
    BridgeInfo bridge,
  ) async => groupTypes[bridge.name];

  @override
  Future<BridgeUser?> resolveOnNetwork(
    Client client,
    BridgeInfo bridge,
    String identifier,
  ) async {
    resolved.add('${bridge.name} $identifier');
    final error = resolveErrors[bridge.name] ?? resolveError;
    if (error != null) throw error;
    return reachable['${bridge.name} $identifier'];
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

  /// One entry per message sent: room and text, then the effect id the
  /// message content carries, when it has one.
  @override
  Future<void> sendText(Room room, String text, {MessageEffect? effect}) async {
    final effectId = effect == null
        ? null
        : room.textContentWithEffect(text, effect)[messageEffectKey];
    sent.add('${room.id}: $text${effectId == null ? '' : ' [$effectId]'}');
  }

  /// One entry per share sent: room, the files' names, the number of
  /// forwarded messages and the text, then the effect id when one was
  /// picked.
  final List<String> shared = [];

  @override
  Future<void> sendShare(
    BuildContext context,
    Room room,
    SharePayload payload, {
    MessageEffect? effect,
  }) async {
    shared.add(
      '${room.id}: ${payload.files.map((file) => file.path.split('/').last).join(',')} '
      '${payload.contents.length} "${payload.text}"'
      '${effect == null ? '' : ' [${effect.id}]'}',
    );
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
            mxid: _quinnGhost,
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

  Future<void> pump(
    WidgetTester tester, {
    bool startGroup = false,
    SharedDraft? share,
    bool appTheme = false,
    bool pushed = false,
  }) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      // Opened from the chat list, so Back has somewhere to go.
      initialLocation: pushed ? '/home' : '/',
      routes: [
        GoRoute(
          path: '/home',
          builder: (_, _) => const Scaffold(body: Text('chat list')),
        ),
        GoRoute(
          path: '/',
          builder: (_, _) => NewPrivateChat(
            deeplink: null,
            delivery: delivery,
            startGroup: startGroup,
            share: share,
          ),
        ),
        GoRoute(
          path: '/rooms/newgroup',
          builder: (_, _) => const Scaffold(body: Text('matrix group')),
        ),
        GoRoute(
          path: '/rooms/:roomid',
          builder: (_, state) =>
              Scaffold(body: Text('chat ${state.pathParameters['roomid']}')),
        ),
        GoRoute(
          path: '/rooms/contact/:id',
          builder: (_, state) =>
              Scaffold(body: Text('contact ${state.pathParameters['id']}')),
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
          builder: appTheme
              ? (context, child) => Theme(
                  data: FluffyThemes.buildTheme(context, Brightness.light),
                  child: child!,
                )
              : null,
        ),
      ),
    );
    await tester.pumpAndSettle();
    if (pushed) {
      router.push('/');
      await tester.pumpAndSettle();
    }
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

    // A Matrix chat is on none of the user's networks.
    expect(find.byKey(const ValueKey('compose-networks')), findsNothing);
    expect(composerHint(tester), 'Write a message…');

    await sendMessage(tester, 'hi');
    expect(delivery.sent, ['!quade:x: hi']);
    expect(delivery.started, isEmpty);
    expect(find.text('chat !quade:x'), findsOneWidget);
  });

  testWidgets('one new person on one network: no switcher, no line under '
      'the To field, and the first message starts the chat there', (
    tester,
  ) async {
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    // The other networks were asked and do not reach Quinn.
    expect(delivery.resolved, [
      'gmessages +14045550101',
      'telegram +14045550101',
    ]);
    expect(find.text('Your first message starts the chat'), findsOneWidget);
    expect(find.byKey(const ValueKey('compose-networks')), findsNothing);
    expect(find.byKey(const ValueKey('compose-network')), findsNothing);
    expect(find.text('You pick the network when you send'), findsNothing);
    expect(find.text('On iMessage'), findsNothing);
    expect(composerHint(tester), 'iMessage');
    expect(groupTitle, findsNothing);

    await tester.enterText(messageField, 'hey');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('compose-send')));
    await tester.pump();
    // Nothing asks for the network on send.
    expect(find.byType(BottomSheet), findsNothing);
    await tester.pumpAndSettle();
    expect(delivery.started, ['imessage $_quinnGhost']);
    expect(delivery.sent, ['!new-dm:x: hey']);
    expect(find.text('chat !new-dm:x'), findsOneWidget);
  });

  testWidgets('two people with a group show it and send there', (tester) async {
    addTripGroup();
    await pump(tester);
    await pick(tester, 'quinn', 'Quinn Imsg');
    await pick(tester, 'quinby', 'Quinby Imsg');
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
      'imessage/group tel:+14045550101,tel:+14045550102 "Trip"',
    ]);
    expect(delivery.sent, ['!group:x: yo']);
    expect(find.text('chat !group:x'), findsOneWidget);
  });

  testWidgets('a network without group names shows no name field', (
    tester,
  ) async {
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
      'gmessages/group tel:+14045550101,tel:+14045550102 "null"',
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
      'imessage/group tel:+14045550101,tel:+14045550102 "null"',
    ]);
  });

  testWidgets('a network that needs a name holds Save and Send until set', (
    tester,
  ) async {
    delivery.groupTypes['imessage'] = const BridgeGroupType(
      id: 'group',
      nameAllowed: true,
      nameRequired: true,
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
      'imessage/group tel:+14045550101,tel:+14045550102 "Trip"',
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
            mxid: _quinnGhost,
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

    testWidgets('two typical names share the To row in the app\'s font', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final loader = FontLoader('GoogleSansFlex');
        for (final weight in ['Regular', 'Medium']) {
          final file = File(
            'assets/fonts/google_sans_flex/GoogleSansFlex-$weight.ttf',
          );
          loader.addFont(
            Future.value(ByteData.sublistView(file.readAsBytesSync())),
          );
        }
        await loader.load();
      });
      delivery.bridgeContacts = [
        BridgeContactInput(
          _imessage,
          const BridgeUser(
            id: 'tel:+14045550111',
            name: 'Drew Andersen',
            identifiers: ['tel:+14045550111'],
            mxid: '@imessage_drew:x',
          ),
        ),
        BridgeContactInput(
          _imessage,
          const BridgeUser(
            id: 'tel:+14045550112',
            name: 'Harrison Young',
            identifiers: ['tel:+14045550112'],
            mxid: '@imessage_harrison:x',
          ),
        ),
      ];
      await pump(tester, appTheme: true);
      tester.view.physicalSize = const Size(412 * 3, 915 * 3);
      await tester.pumpAndSettle();
      await pick(tester, 'drew', 'Drew Andersen');
      await pick(tester, 'harrison', 'Harrison Young');
      final drew = tester.getRect(chip('+14045550111'));
      final harrison = tester.getRect(chip('+14045550112'));
      expect(harrison.center.dy, moreOrLessEquals(drew.center.dy, epsilon: 1));
      expect(harrison.left, greaterThan(drew.right));
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

  testWidgets('with someone in the To field, group chats are not suggested', (
    tester,
  ) async {
    addTripGroup();
    await pump(tester);
    await search(tester, 'trip');
    // Nobody picked yet: the group is offered, and opens.
    expect(find.text('Trip crew'), findsOneWidget);

    await tester.enterText(toField, '');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
    await pick(tester, 'quinn', 'Quinn Imsg');
    await search(tester, 'trip');
    expect(find.text('Trip crew'), findsNothing);
    expect(find.text("Group chats can't be added"), findsNothing);
    // A group bubble looks its sender up in the database, whose
    // transaction holds a ten-second timer in the test's fake time.
    await tester.pump(const Duration(seconds: 11));
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
    expect(delivery.resolved, contains('imessage +14045550103'));
    expect(chip('+14045550103'), findsNothing);
    expect(find.text('Quill Sms: Not on iMessage'), findsOneWidget);
  });

  group('a group picked from the suggestions', () {
    final lockedTo = find.byKey(const ValueKey('compose-to-locked'));

    testWidgets('is locked in as the recipient, with the message field '
        'focused', (tester) async {
      addTripGroup();
      await pump(tester);
      await pick(tester, 'trip', 'Trip crew');
      // The composer stays open on the group.
      expect(find.text('chat !trip:x'), findsNothing);
      expect(lockedTo, findsOneWidget);
      expect(
        find.descendant(of: lockedTo, matching: find.text('Trip crew')),
        findsOneWidget,
      );
      // No chip field: nobody can be typed in or added, nor the group
      // taken out.
      expect(toField, findsNothing);
      expect(find.byType(InputChip), findsNothing);
      expect(find.text('trip plans'), findsOneWidget);
      final message = tester.widget<TextField>(messageField);
      expect(message.focusNode!.hasFocus, isTrue);
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('takes the message and opens the group', (tester) async {
      addTripGroup();
      await pump(tester);
      await pick(tester, 'trip', 'Trip crew');
      await sendMessage(tester, 'on my way');
      expect(delivery.sent, ['!trip:x: on my way']);
      expect(delivery.started, isEmpty);
      expect(find.text('chat !trip:x'), findsOneWidget);
      // The group's history looked its senders up in the database, whose
      // transaction holds a ten-second timer in the test's fake time.
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('Back leaves the composer', (tester) async {
      addTripGroup();
      await pump(tester, pushed: true);
      await pick(tester, 'trip', 'Trip crew');
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('chat list'), findsOneWidget);
      expect(lockedTo, findsNothing);
      expect(toField, findsNothing);
      await tester.pump(const Duration(seconds: 11));
    });
  });

  group('network switcher', () {
    final networks = find.byKey(const ValueKey('compose-networks'));
    Finder network(String name) =>
        find.descendant(of: networks, matching: find.byTooltip(name));

    testWidgets('a typed number two networks reach shows the switcher, '
        'and the picked network starts the chat', (tester) async {
      delivery.reachable['imessage +14045550199'] = const BridgeUser(
        id: 'imsg-0199',
      );
      delivery.reachable['gmessages +14045550199'] = const BridgeUser(
        id: 'gm-0199',
      );
      await pump(tester);
      await tester.enterText(toField, '404-555-0199');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(networks, findsOneWidget);
      expect(network('iMessage'), findsOneWidget);
      expect(network('Google Messages'), findsOneWidget);
      expect(
        tester.getCenter(network('iMessage')).dx,
        lessThan(tester.getCenter(network('Google Messages')).dx),
        reason: 'iMessage comes first, as in the network order',
      );
      // No chat with them yet: the first network that reaches them.
      expect(composerHint(tester), 'iMessage');

      await tester.tap(network('Google Messages'));
      await tester.pumpAndSettle();
      expect(composerHint(tester), 'Google Messages');

      await sendMessage(tester, 'hey');
      expect(find.byType(BottomSheet), findsNothing);
      expect(delivery.started, ['gmessages +14045550199']);
      expect(delivery.sent, ['!new-dm:x: hey']);
    });

    /// Quinn with a chat on each network, not merged: the iMessage one
    /// older, the Google Messages one newer.
    void addQuinnOnBoth() {
      final imsg = addFakeChat(
        client,
        '!q-im:x',
        'Quinn Imsg',
        partner: _quinnGhost,
        lastMessageTime: DateTime(2026, 11, 20),
      );
      final sms = addFakeChat(
        client,
        '!q-gm:x',
        'Quinn Sms',
        partner: '@gmessages_quinn:x',
        lastMessageTime: DateTime(2026, 11, 24),
      );
      addFakeBridge(imsg, bot: _imessage.bridgeBot!);
      addFakeBridge(sms, bot: _gmessages.bridgeBot!);
      delivery.history[imsg.id] = [text(imsg, 'from imessage', _quinnGhost)];
      delivery.history[sms.id] = [text(sms, 'from sms', '@gmessages_quinn:x')];
      delivery.reachable['gmessages +14045550101'] = const BridgeUser(
        id: 'gm-quinn',
        mxid: '@gmessages_quinn:x',
        dmRoomId: '!q-gm:x',
      );
    }

    testWidgets('a person with a chat on each network starts on the most '
        'recent one; picking another swaps the history and the hint', (
      tester,
    ) async {
      addQuinnOnBoth();
      await pump(tester);
      await pick(tester, 'quinn', 'Quinn Imsg');
      expect(networks, findsOneWidget);
      expect(composerHint(tester), 'Google Messages');
      expect(find.text('from sms'), findsOneWidget);
      expect(find.text('from imessage'), findsNothing);

      await tester.tap(network('iMessage'));
      await tester.pumpAndSettle();
      expect(composerHint(tester), 'iMessage');
      expect(find.text('from imessage'), findsOneWidget);
      expect(find.text('from sms'), findsNothing);

      await sendMessage(tester, 'yo');
      expect(delivery.sent, ['!q-im:x: yo']);
      expect(delivery.started, isEmpty);
      // A bubble looks its sender up in the database, whose transaction
      // holds a ten-second timer in the test's fake time.
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('a group stays on the picked network; one someone is not on '
        'is faded, says who, and does not pick', (tester) async {
      delivery.reachable['gmessages +14045550101'] = const BridgeUser(
        id: 'gm-quinn',
      );
      await pump(tester);
      await pick(tester, 'quinn', 'Quinn Imsg');
      expect(networks, findsOneWidget);
      await pick(tester, 'quinby', 'Quinby Imsg');
      expect(chip('+14045550102'), findsOneWidget);
      expect(composerHint(tester), 'iMessage');
      expect(
        find.descendant(of: groupTitle, matching: find.text('New group chat')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: groupTitle,
          matching: find.byIcon(Icons.edit_outlined),
        ),
        findsOneWidget,
      );
      // Quinby is on iMessage only.
      expect(network('Quinby Imsg: Not on Google Messages'), findsOneWidget);
      expect(network('Google Messages'), findsNothing);

      await tester.tap(network('Quinby Imsg: Not on Google Messages'));
      await tester.pumpAndSettle();
      expect(
        find.descendant(
          of: find.byType(SnackBar),
          matching: find.text('Quinby Imsg: Not on Google Messages'),
        ),
        findsOneWidget,
      );
      expect(composerHint(tester), 'iMessage');
      ScaffoldMessenger.of(tester.element(messageField)).hideCurrentSnackBar();
      await tester.pumpAndSettle();

      await sendMessage(tester, 'yo');
      expect(delivery.created, [
        'imessage/group tel:+14045550101,tel:+14045550102 "null"',
      ]);
    });

    testWidgets('someone the picked network does not reach cannot be added', (
      tester,
    ) async {
      delivery.reachable['gmessages +14045550101'] = const BridgeUser(
        id: 'gm-quinn',
      );
      await pump(tester);
      await pick(tester, 'quinn', 'Quinn Imsg');
      await tester.tap(network('Google Messages'));
      await tester.pumpAndSettle();
      await pick(tester, 'quinby', 'Quinby Imsg');
      expect(chip('+14045550102'), findsNothing);
      expect(find.text('Quinby Imsg: Not on Google Messages'), findsOneWidget);
      expect(composerHint(tester), 'Google Messages');
    });

    testWidgets('a network that fails to answer is shown with the reason and '
        'a retry, never skipped', (tester) async {
      delivery.resolveErrors['imessage'] = const BridgeProvisioningException(
        'imessage',
        statusCode: 500,
        errcode: 'M_UNKNOWN',
        error: 'lookup refused',
      );
      await pump(tester);
      await tester.enterText(toField, '404-555-0199');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      // Google Messages answered it does not reach them, but iMessage
      // failing is no "not found": nothing is picked and send stays off.
      expect(
        find.text("Couldn't check +1 404 555 0199 on iMessage: lookup refused"),
        findsOneWidget,
      );
      expect(find.text("Couldn't check this person"), findsOneWidget);
      expect(networks, findsNothing);
      await tester.enterText(messageField, 'hey');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('compose-send')))
            .onPressed,
        isNull,
      );

      delivery.resolveErrors.clear();
      delivery.reachable['imessage +14045550199'] = const BridgeUser(
        id: 'imsg-0199',
      );
      await tester.tap(find.byTooltip('Try again'));
      await tester.pumpAndSettle();
      expect(
        delivery.resolved.where((asked) => asked.startsWith('imessage')),
        hasLength(2),
      );
      expect(find.textContaining("Couldn't check"), findsNothing);
      expect(composerHint(tester), 'iMessage');
      await tester.tap(find.byKey(const ValueKey('compose-send')));
      await tester.pumpAndSettle();
      expect(delivery.started, ['imessage +14045550199']);
    });

    Future<void> typeNumber(WidgetTester tester) async {
      await tester.enterText(toField, '404-555-0199');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
    }

    testWidgets('a typed number is never sent to a network that takes no '
        'phone numbers', (tester) async {
      // Telegram declares it does not look up numbers; LinkedIn declares
      // nothing and is not a network of phone numbers.
      delivery.lookups['telegram'] = const BridgeLookups(
        phone: false,
        email: false,
      );
      await pump(tester);
      await typeNumber(tester);
      expect(delivery.resolved, [
        'imessage +14045550199',
        'gmessages +14045550199',
      ]);
      expect(find.textContaining("Couldn't check"), findsNothing);
    });

    testWidgets('a bridge that rejects the identifier is a network the person '
        'is not on, without a failure line', (tester) async {
      delivery.reachable['imessage +14045550199'] = const BridgeUser(
        id: 'imsg-0199',
      );
      delivery.resolveErrors['gmessages'] = const BridgeProvisioningException(
        'gmessages',
        statusCode: 500,
        errcode: 'M_UNKNOWN',
        error: 'invalid identifier: +14045550199',
      );
      await pump(tester);
      await typeNumber(tester);
      expect(delivery.resolved, contains('gmessages +14045550199'));
      expect(find.byKey(const ValueKey('compose-check-failed')), findsNothing);
      expect(find.textContaining("Couldn't check"), findsNothing);
      expect(composerHint(tester), 'iMessage');
    });

    testWidgets('a network that times out keeps its line, with its logo and '
        'the person named; the lines hide while a name is typed', (
      tester,
    ) async {
      final sms = addFakeChat(
        client,
        '!someone-gm:x',
        'Someone Sms',
        partner: '@gmessages_someone:x',
      );
      addFakeBridge(sms, bot: _gmessages.bridgeBot!);
      addFakeSpace(client, '!gspace:x', 'Google Messages', [sms.id]).setState(
        StrippedStateEvent(
          type: EventTypes.RoomAvatar,
          content: {'url': 'mxc://x/gmessages-logo'},
          senderId: '@gmessagesbot:x',
          stateKey: '',
        ),
      );
      delivery.reachable['imessage +14045550199'] = const BridgeUser(
        id: 'imsg-0199',
      );
      delivery.resolveErrors['gmessages'] = TimeoutException(
        'no answer',
        const Duration(seconds: 30),
      );
      await pump(tester);
      await typeNumber(tester);
      final line = find.byKey(
        const ValueKey('check-failed-gmessages-+14045550199'),
      );
      expect(line, findsOneWidget);
      expect(
        find.descendant(
          of: line,
          matching: find.textContaining(
            "Couldn't check +1 404 555 0199 on Google Messages: ",
          ),
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<Avatar>(
              find.descendant(of: line, matching: find.byType(Avatar)),
            )
            .mxContent,
        Uri.parse('mxc://x/gmessages-logo'),
      );

      // Typing a name: the line is about the chip, not the search.
      await tester.enterText(toField, 'qu');
      await tester.pump();
      expect(line, findsNothing);
      await tester.enterText(toField, '');
      await tester.pump(const Duration(milliseconds: 600));
      await tester.pumpAndSettle();
      expect(line, findsOneWidget);
    });

    testWidgets('each person a network failed on gets a line of their own', (
      tester,
    ) async {
      delivery.resolveErrors['gmessages'] = TimeoutException('no answer');
      await pump(tester);
      await pick(tester, 'quinn', 'Quinn Imsg');
      await pick(tester, 'quinby', 'Quinby Imsg');
      expect(
        find.byKey(const ValueKey('check-failed-gmessages-+14045550101')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('check-failed-gmessages-+14045550102')),
        findsOneWidget,
      );
      expect(
        find.textContaining("Couldn't check Quinby Imsg on Google Messages"),
        findsOneWidget,
      );
    });

    testWidgets('no network reaches them: says so and holds send', (
      tester,
    ) async {
      await pump(tester);
      await tester.enterText(toField, '404-555-0199');
      await tester.testTextInput.receiveAction(TextInputAction.done);
      await tester.pumpAndSettle();
      expect(
        find.text('None of your networks can reach this person'),
        findsOneWidget,
      );
      await tester.enterText(messageField, 'hey');
      await tester.pump();
      expect(
        tester
            .widget<IconButton>(find.byKey(const ValueKey('compose-send')))
            .onPressed,
        isNull,
      );
    });
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
    delivery.reachable['imessage +14045550103'] = const BridgeUser(
      id: 'tel:+14045550103',
    );
    await tester.tap(find.text('Try again'));
    await tester.pumpAndSettle();
    expect(chip('+14045550103'), findsOneWidget);
  });

  group('New group row', () {
    final newGroup = find.text('New group');

    testWidgets('comes first whether the networks are loading, have some or '
        'have none', (tester) async {
      delivery.sourcesGate = Completer();
      await pump(tester);
      expect(newGroup, findsOneWidget);
      expect(find.text('Pick two or more people'), findsOneWidget);
      final share = find.text('Share invite link');
      if (share.evaluate().isNotEmpty) {
        expect(
          tester.getTopLeft(newGroup).dy,
          lessThan(tester.getTopLeft(share).dy),
        );
      }
      delivery.sourcesGate!.complete();
      await tester.pumpAndSettle();
      expect(newGroup, findsOneWidget);
    });

    testWidgets('shown on an account with no networks too', (tester) async {
      delivery.bridgeList = const [];
      await pump(tester);
      expect(newGroup, findsOneWidget);
    });

    testWidgets('with networks, puts the cursor in the To field', (
      tester,
    ) async {
      await pump(tester);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      expect(tester.widget<TextField>(toField).focusNode!.hasFocus, isFalse);
      await tester.tap(newGroup);
      await tester.pumpAndSettle();
      // The To field has the focus on opening, so it is taken away first.
      expect(tester.widget<TextField>(toField).focusNode!.hasFocus, isTrue);
      expect(find.text('matrix group'), findsNothing);
    });

    testWidgets('without networks, opens the Matrix group page', (
      tester,
    ) async {
      delivery.bridges = false;
      delivery.bridgeList = const [];
      await pump(tester);
      await tester.tap(newGroup);
      await tester.pumpAndSettle();
      expect(find.text('matrix group'), findsOneWidget);
    });
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

  group('effects', () {
    final sendButton = find.byKey(const ValueKey('compose-send'));

    Future<void> longPressSend(WidgetTester tester, String text) async {
      await tester.enterText(messageField, text);
      await tester.pump();
      await tester.longPress(sendButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
    }

    testWidgets('a long press on send for an iMessage group opens the picker '
        'and Fireworks goes with the first message', (tester) async {
      await pump(tester);
      await pick(tester, 'quinn', 'Quinn Imsg');
      await pick(tester, 'quinby', 'Quinby Imsg');
      await longPressSend(tester, 'yo');
      expect(find.byType(MessageEffectPicker), findsOneWidget);
      expect(delivery.created, isEmpty);

      await tester.tap(find.text('Screen'));
      await tester.pump();
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('send_effect_fireworks')),
        60,
        scrollable: find.descendant(
          of: find.byType(MessageEffectPicker),
          matching: find.byType(Scrollable),
        ),
      );
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byKey(const ValueKey('send_effect_fireworks')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 1));
      expect(delivery.created, [
        'imessage/group tel:+14045550101,tel:+14045550102 "null"',
      ]);
      expect(delivery.sent, ['!group:x: yo [${MessageEffect.fireworks.id}]']);
      expect(find.text('chat !group:x'), findsOneWidget);
    });

    testWidgets('not offered for a Google Messages group', (tester) async {
      delivery.bridgeContacts = [
        for (final contact in delivery.bridgeContacts)
          BridgeContactInput(_gmessages, contact.user),
      ];
      await pump(tester);
      await pick(tester, 'quinn', 'Quinn Imsg');
      await pick(tester, 'quinby', 'Quinby Imsg');
      await longPressSend(tester, 'yo');
      expect(find.byType(MessageEffectPicker), findsNothing);
      expect(delivery.created, isEmpty);
      expect(delivery.sent, isEmpty);
    });

    for (final caption in ['yo', '']) {
      testWidgets('offered with a shared photo staged, '
          '${caption.isEmpty ? 'alone' : 'with a caption'}, and the effect '
          'goes with the share', (tester) async {
        await pump(
          tester,
          share: SharedDraft([FileShareItem(XFile('/tmp/photo.jpg'))]),
        );
        await pick(tester, 'quinn', 'Quinn Imsg');
        await pick(tester, 'quinby', 'Quinby Imsg');
        await longPressSend(tester, caption);
        expect(find.byType(MessageEffectPicker), findsOneWidget);
        expect(
          find.descendant(
            of: find.byType(MessageEffectPicker),
            matching: find.byKey(const ValueKey('effect_preview_media')),
          ),
          findsOneWidget,
        );
        await tester.pump(const Duration(seconds: 3));
        await tester.tap(find.byKey(const ValueKey('send_effect_slam')));
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        await tester.pump(const Duration(seconds: 1));
        expect(delivery.shared, [
          '!group:x: photo.jpg 0 "$caption" [${MessageEffect.slam.id}]',
        ]);
      });
    }
  });

  group('share', () {
    final photo = XFile('/tmp/photo.jpg', name: 'photo.jpg');
    final recent = find.byKey(const ValueKey('compose-recent'));
    final networks = find.byKey(const ValueKey('compose-networks'));
    final returns = <Object?>[];

    setUp(() {
      returns.clear();
      AndroidDirectShare.debugIsAndroid = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('chat.fluffy.fluffychat/share'),
            (call) async {
              if (call.method == 'returnToSourceApp') {
                returns.add(call.arguments);
              }
              return null;
            },
          );
    });

    tearDown(() {
      AndroidDirectShare.debugIsAndroid = null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
            const MethodChannel('chat.fluffy.fluffychat/share'),
            null,
          );
    });

    List<XFile> stagedFiles(WidgetTester tester) => tester
        .widget<ComposerAttachmentStrip>(find.byType(ComposerAttachmentStrip))
        .files;

    /// Quinn on iMessage and on Google Messages, merged into one contact,
    /// each room in its network's bridge space.
    void addMergedQuinn() {
      final imsg = addFakeChat(
        client,
        '!q-imsg:x',
        'Quinn Merged',
        partner: '@imessage_qm:x',
        lastMessageTime: DateTime(2026, 11, 25),
      );
      final sms = addFakeChat(
        client,
        '!q-sms:x',
        'Quinn Merged',
        partner: '@gmessages_qm:x',
        lastMessageTime: DateTime(2026, 11, 24),
      );
      addFakeSpace(client, '!ispace:x', 'iMessage', [imsg.id]);
      addFakeSpace(client, '!gspace:x', 'Google Messages', [sms.id]);
      setMergedContacts(client, {
        'c_q': {
          'rooms': [imsg.id, sms.id],
          'send_via': imsg.id,
          'updated': 1,
        },
      });
    }

    testWidgets('a recent group without a photo shows its members as the '
        'chat list does', (tester) async {
      addTripGroup();
      await pump(tester, share: SharedDraft([FileShareItem(photo)]));
      final row = find.ancestor(
        of: find.descendant(of: recent, matching: find.text('Trip crew')),
        matching: find.byType(ListTile),
      );
      expect(
        find.descendant(of: row, matching: find.byType(GroupAvatar)),
        findsOneWidget,
      );
      // A group bubble looks its sender up in the database, whose
      // transaction holds a ten-second timer in the test's fake time.
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('a recent row shows its networks\' own logos, in colour, as '
        'the network switcher does', (tester) async {
      final imsg = addFakeChat(
        client,
        '!q-imsg:x',
        'Quinn Imsg',
        partner: '@imessage_qm:x',
      );
      addFakeSpace(client, '!ispace:x', 'iMessage', [imsg.id]).setState(
        StrippedStateEvent(
          type: EventTypes.RoomAvatar,
          content: {'url': 'mxc://x/imessage-logo'},
          senderId: '@imessagebot:x',
          stateKey: '',
        ),
      );
      await pump(tester, share: SharedDraft([FileShareItem(photo)]));
      final row = find.ancestor(
        of: find.descendant(of: recent, matching: find.text('Quinn Imsg')),
        matching: find.byType(ListTile),
      );
      final logo = find.descendant(
        of: row,
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Avatar &&
              widget.mxContent == Uri.parse('mxc://x/imessage-logo'),
        ),
      );
      expect(logo, findsOneWidget);
      expect(
        find.ancestor(of: logo, matching: find.byType(ColorFiltered)),
        findsNothing,
      );
    });

    testWidgets('opens with the To field empty, recent chats offered and '
        'the share staged', (tester) async {
      await pump(
        tester,
        share: SharedDraft([
          FileShareItem(photo),
          TextShareItem('https://example.org'),
        ]),
      );
      expect(tester.widget<TextField>(toField).controller!.text, isEmpty);
      expect(
        find.descendant(of: recent, matching: find.text('Quade Matrix')),
        findsOneWidget,
      );
      expect(stagedFiles(tester), [photo]);
      expect(
        tester.widget<TextField>(messageField).controller!.text,
        'https://example.org',
      );
      expect(delivery.shared, isEmpty);
      expect(delivery.sent, isEmpty);
    });

    testWidgets('a recent chat becomes the recipient; send sends the share '
        'there and opens it', (tester) async {
      await pump(tester, share: SharedDraft([FileShareItem(photo)]));
      await tester.tap(
        find.descendant(of: recent, matching: find.text('Quade Matrix')),
      );
      await tester.pumpAndSettle();
      expect(chip('@quade:x'), findsOneWidget);
      expect(find.text('see you soon'), findsOneWidget);
      expect(delivery.shared, isEmpty);

      await sendMessage(tester, 'look');
      expect(delivery.shared, ['!quade:x: photo.jpg 0 "look"']);
      expect(delivery.sent, isEmpty);
      expect(find.text('chat !quade:x'), findsOneWidget);
      // Shared from inside the app: Seam stays.
      expect(returns, isEmpty);
    });

    testWidgets('the network buttons pick the room a merged contact\'s share '
        'goes to', (tester) async {
      addMergedQuinn();
      await pump(tester, share: SharedDraft([FileShareItem(photo)]));
      await tester.tap(
        find.descendant(of: recent, matching: find.text('Quinn Merged')),
      );
      await tester.pumpAndSettle();
      expect(networks, findsOneWidget);
      expect(composerHint(tester), 'iMessage');

      await tester.tap(
        find.descendant(
          of: networks,
          matching: find.byTooltip('Google Messages'),
        ),
      );
      await tester.pumpAndSettle();
      expect(composerHint(tester), 'Google Messages');

      await tester.tap(find.byKey(const ValueKey('compose-send')));
      await tester.pumpAndSettle();
      expect(delivery.shared, ['!q-sms:x: photo.jpg 0 ""']);
      expect(find.text('contact c_q'), findsOneWidget);
      // The contacts store's merge suggestions run after a change, and
      // each network's history is read in a database transaction that
      // holds a ten-second timer in the test's fake time.
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('a recent chat joined by its contact gets the networks its '
        'number reaches', (tester) async {
      final imsg = addFakeChat(
        client,
        '!q-im:x',
        'Quinn Imsg',
        partner: _quinnGhost,
        lastMessageTime: DateTime(2026, 11, 25),
      );
      addFakeBridge(imsg, bot: _imessage.bridgeBot!);
      delivery.reachable['gmessages +14045550101'] = const BridgeUser(
        id: 'gm-quinn',
      );
      await pump(tester, share: SharedDraft([FileShareItem(photo)]));
      await tester.tap(
        find.descendant(of: recent, matching: find.text('Quinn Imsg')),
      );
      await tester.pumpAndSettle();
      expect(networks, findsOneWidget);
      expect(composerHint(tester), 'iMessage');
      expect(stagedFiles(tester), [photo]);

      await tester.tap(
        find.descendant(
          of: networks,
          matching: find.byTooltip('Google Messages'),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('compose-send')));
      await tester.pumpAndSettle();
      expect(delivery.started, ['gmessages +14045550101']);
      expect(delivery.shared, ['!new-dm:x: photo.jpg 0 ""']);
    });

    testWidgets('sent from the share sheet, Seam returns to the sharing app '
        'with a toast', (tester) async {
      addMergedQuinn();
      await pump(
        tester,
        share: SharedDraft([FileShareItem(photo)], fromShareIntent: true),
      );
      await tester.tap(
        find.descendant(of: recent, matching: find.text('Quinn Merged')),
      );
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(
          of: networks,
          matching: find.byTooltip('Google Messages'),
        ),
      );
      await tester.pumpAndSettle();
      expect(returns, isEmpty);
      await tester.tap(find.byKey(const ValueKey('compose-send')));
      await tester.pumpAndSettle();
      expect(delivery.shared, ['!q-sms:x: photo.jpg 0 ""']);
      expect(returns, [
        {'toast': 'Sent to Quinn Merged on Google Messages'},
      ]);
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('back without sending sends nothing and returns to the '
        'sharing app', (tester) async {
      tester.view.physicalSize = const Size(1200, 3000);
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
                path: 'compose',
                builder: (_, _) => NewPrivateChat(
                  deeplink: null,
                  delivery: delivery,
                  share: SharedDraft([
                    FileShareItem(photo),
                    TextShareItem('hello'),
                  ], fromShareIntent: true),
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
      router.push('/compose');
      await tester.pumpAndSettle();
      await tester.tap(
        find.descendant(of: recent, matching: find.text('Quade Matrix')),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.text('chat list'), findsOneWidget);
      expect(delivery.shared, isEmpty);
      expect(delivery.sent, isEmpty);
      expect(returns, [
        {'toast': null},
      ]);
    });
  });
}
