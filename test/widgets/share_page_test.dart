// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_group_widgets.dart';
import 'package:fluffychat/pages/new_private_chat/start_chat_sheet.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/share_scaffold_dialog.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/merged_contacts/fake_rooms.dart';

class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

BridgeInfo _bridge(String name, String displayName) => BridgeInfo(
  name: name,
  networkId: name,
  displayName: displayName,
  icon: null,
  loginId: 'login-$name',
);

/// Records what the page asks for instead of touching the network.
class _FakeDelivery extends ShareDelivery {
  final Client client;

  _FakeDelivery(this.client);

  List<BridgeContactInput> bridgeContacts = const [];

  /// What the network picker answers; null is the user closing it.
  StartChatChoice? choice;
  int picks = 0;

  /// Rooms whose send fails.
  final Set<String> failing = {};

  /// One entry per send: the room and the text.
  final List<String> sent = [];

  /// The first people of new groups, which fix the network (iMessage).
  final List<String> groupPicks = [];

  /// What `resolve_identifier` on the group's network knows.
  final Map<String, BridgeUser> reachable = {};

  /// One entry per `create_group`: network, participants and name.
  final List<String> created = [];

  @override
  Future<(GroupNetwork, BridgeUser)?> pickGroupNetwork(
    BuildContext context,
    Client client,
    NewChatPerson person,
  ) async {
    groupPicks.add(person.name);
    return (
      GroupNetwork(
        _bridge('imessage', 'iMessage'),
        const BridgeGroupType(id: 'group', nameAllowed: true),
      ),
      BridgeUser(id: 'id-${person.name}'),
    );
  }

  @override
  Future<BridgeUser?> resolveOnNetwork(
    Client client,
    BridgeInfo bridge,
    String identifier,
  ) async => reachable[identifier];

  @override
  Future<CreatedGroup> createGroup(
    Client client,
    GroupNetwork network,
    List<GroupMember> members,
    String? name,
  ) async {
    created.add(
      '${network.bridge.name} '
      '${members.map((member) => member.user.id).join(',')} "$name"',
    );
    addDirectChat(client, id: '!group:x', partner: '@group:x', name: 'G');
    return const CreatedGroup('!group:x');
  }

  @override
  Future<void> loadSources(Client client, NewChatSources sources) async {
    sources.bridgeContacts = bridgeContacts;
  }

  @override
  Future<StartChatChoice?> pickNetwork(
    BuildContext context,
    Client client,
    NewChatPerson person,
  ) async {
    picks++;
    return choice;
  }

  @override
  Future<({Room room, String route})> resolve(
    Client client,
    ShareTarget target,
  ) async {
    switch (target) {
      case ChatShareTarget(:final chat):
        return (room: chat.sendRoom, route: '/rooms/${chat.room.id}');
      case NewChatShareTarget(:final person):
        final room = addDirectChat(
          client,
          id: '!new-${person.name}:x',
          partner: '@new_${person.phones.length}:x',
          name: person.name,
        );
        return (room: room, route: '/rooms/${room.id}');
    }
  }

  @override
  Future<void> send(
    BuildContext context,
    Room room,
    SharePayload payload,
  ) async {
    if (failing.contains(room.id)) throw Exception('send failed');
    sent.add('${room.id} ${payload.text}');
  }
}

Widget _app(Client client, _FakeDelivery delivery, List<ShareItem> items) {
  final router = GoRouter(
    routes: [
      GoRoute(
        path: '/',
        builder: (_, _) =>
            ShareScaffoldDialog(items: items, delivery: delivery),
      ),
      GoRoute(
        path: '/rooms',
        builder: (_, _) => const Scaffold(body: Text('chat list')),
      ),
      GoRoute(
        path: '/rooms/:roomid',
        builder: (_, state) =>
            Scaffold(body: Text('chat ${state.pathParameters['roomid']}')),
      ),
    ],
  );
  return Provider<MatrixState>.value(
    value: _FakeMatrix(client),
    child: MaterialApp.router(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

Finder _sendButton() => find.byType(FilledButton);

String _buttonLabel(WidgetTester tester) => tester
    .widget<Text>(
      find.descendant(of: _sendButton(), matching: find.byType(Text)),
    )
    .data!;

void main() {
  late Client client;
  late _FakeDelivery delivery;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await fakeMergedClient();
    delivery = _FakeDelivery(client);
    // Newest first, as the SDK sorts them.
    addDirectChat(
      client,
      id: '!payton:x',
      partner: '@payton:x',
      name: 'Payton Adams',
      lastMessage: 'I am sure we can figure it out',
      lastMessageTime: DateTime(2026, 1, 7),
    );
    addDirectChat(
      client,
      id: '!imsg:x',
      partner: '@imessage_tel=3a+14045551234:x',
      name: 'Harrison Young',
      lastMessage: 'old message',
      lastMessageTime: DateTime(2026, 1, 1),
    );
    addDirectChat(
      client,
      id: '!sms:x',
      partner: '@gmessages_1.2:x',
      name: '(404) 555-1234',
      lastMessage: 'newest message',
      lastMessageTime: DateTime(2026, 1, 6),
    );
    addDirectChat(
      client,
      id: '!drew:x',
      partner: '@drew:x',
      name: 'Drew Andersen',
      lastMessage: 'Kool, we will hang',
      lastMessageTime: DateTime(2026, 1, 5),
    );
    addDirectChat(
      client,
      id: '!maddie:x',
      partner: '@maddie:x',
      name: 'Madeline Polinski',
      lastMessage: 'Leaving tonight?',
      lastMessageTime: DateTime(2026, 1, 4),
    );
    addDirectChat(
      client,
      id: '!squad:x',
      partner: '@squad:x',
      name: 'Squad Goals',
      lastMessage: 'see you',
      lastMessageTime: DateTime(2026, 1, 3),
    );
    addDirectChat(
      client,
      id: '!zed:x',
      partner: '@zed:x',
      name: 'Zed Zulu',
      lastMessage: 'oldest',
      lastMessageTime: DateTime(2026, 1, 2),
    );
    setMergedContacts(client, {
      'c_1': {
        'rooms': ['!imsg:x', '!sms:x'],
        'send_via': '!imsg:x',
        'updated': 1,
      },
    });
  });

  tearDown(() => MergedContactsStore.disposeFor(client));

  Future<void> pump(WidgetTester tester, [List<ShareItem>? items]) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      _app(client, delivery, items ?? [TextShareItem('share-sheet-check')]),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('at rest: recent chats with previews, then A to Z', (
    tester,
  ) async {
    await pump(tester);
    expect(find.text('Recent conversations'), findsOneWidget);
    expect(find.text('I am sure we can figure it out'), findsOneWidget);
    expect(find.text('More recent conversations'), findsOneWidget);
    // Five recent chats (the merged contact counts once), so the sixth is
    // under its letter.
    expect(find.byKey(const ValueKey('share-header-Z')), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('Zed Zulu')).dy,
      greaterThan(
        tester.getTopLeft(find.byKey(const ValueKey('share-header-Z'))).dy,
      ),
    );
    // The shared text is in the message field.
    expect(find.text('share-sheet-check'), findsOneWidget);

    await tester.tap(find.text('More recent conversations'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('share-header-Z')), findsNothing);
    expect(find.text('Zed Zulu'), findsOneWidget);
  });

  testWidgets('a merged contact is one row', (tester) async {
    await pump(tester);
    expect(find.text('Harrison Young'), findsOneWidget);
    expect(find.text('(404) 555-1234'), findsNothing);
    // Its newest message across both rooms is the preview.
    expect(find.text('newest message'), findsOneWidget);
    expect(find.text('@imessage_tel=3a+14045551234:x'), findsNothing);
  });

  testWidgets('tapping rows ticks them and sends nothing', (tester) async {
    await pump(tester);
    expect(_buttonLabel(tester), 'Send');
    expect(tester.widget<FilledButton>(_sendButton()).onPressed, isNull);

    await tester.tap(find.text('Payton Adams'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(_buttonLabel(tester), 'Send to 1 chat');
    expect(tester.widget<FilledButton>(_sendButton()).onPressed, isNotNull);

    await tester.tap(find.text('Harrison Young'));
    await tester.pumpAndSettle();
    expect(_buttonLabel(tester), 'Send to 2 chats');

    await tester.tap(find.text('Payton Adams'));
    await tester.pumpAndSettle();
    expect(_buttonLabel(tester), 'Send to 1 chat');
    expect(delivery.sent, isEmpty);
  });

  testWidgets('search lists your chats and contacts, with no New badge', (
    tester,
  ) async {
    delivery.bridgeContacts = [
      BridgeContactInput(
        _bridge('gmessages', 'Google Messages'),
        const BridgeUser(
          id: '1',
          name: 'Drew Morales',
          identifiers: ['tel:+13125550188'],
        ),
      ),
    ];
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'dre');
    await tester.pumpAndSettle();
    expect(find.text('Your chats'), findsOneWidget);
    expect(find.text('Contacts'), findsOneWidget);
    expect(find.text('Drew Andersen'), findsOneWidget);
    expect(find.text('Drew Morales'), findsOneWidget);
    expect(find.text('Payton Adams'), findsNothing);
    expect(find.text('New'), findsNothing);
    expect(
      tester.getTopLeft(find.text('Drew Andersen')).dy,
      lessThan(tester.getTopLeft(find.text('Contacts')).dy),
    );
    expect(
      tester.getTopLeft(find.text('Drew Morales')).dy,
      greaterThan(tester.getTopLeft(find.text('Contacts')).dy),
    );

    await tester.enterText(find.byType(TextField).first, '404-555-0123');
    await tester.pumpAndSettle();
    expect(find.text('Typed number'), findsOneWidget);
  });

  testWidgets('a contact opens the network picker and stays unticked '
      'when it is closed', (tester) async {
    delivery.bridgeContacts = [
      BridgeContactInput(
        _bridge('gmessages', 'Google Messages'),
        const BridgeUser(
          id: '1',
          name: 'Drew Morales',
          identifiers: ['tel:+13125550188'],
        ),
      ),
    ];
    await pump(tester);
    await tester.enterText(find.byType(TextField).first, 'morales');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drew Morales'));
    await tester.pumpAndSettle();
    expect(delivery.picks, 1);
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    expect(_buttonLabel(tester), 'Send');

    delivery.choice = StartChatChoice(
      _bridge('imessage', 'iMessage'),
      '+13125550188',
      const BridgeUser(id: '+13125550188'),
    );
    await tester.tap(find.text('Drew Morales'));
    await tester.pumpAndSettle();
    expect(delivery.picks, 2);
    expect(find.byIcon(Icons.radio_button_checked), findsOneWidget);
    expect(_buttonLabel(tester), 'Send to 1 chat');
    // Nothing is started or sent until Send.
    expect(delivery.sent, isEmpty);
    expect(client.getRoomById('!new-Drew Morales:x'), isNull);
  });

  testWidgets('send goes to every target once, then to the chat list', (
    tester,
  ) async {
    delivery.bridgeContacts = [
      BridgeContactInput(
        _bridge('gmessages', 'Google Messages'),
        const BridgeUser(
          id: '1',
          name: 'Drew Morales',
          identifiers: ['tel:+13125550188'],
        ),
      ),
    ];
    delivery.choice = StartChatChoice(
      _bridge('imessage', 'iMessage'),
      '+13125550188',
      const BridgeUser(id: '+13125550188'),
    );
    await pump(tester);
    await tester.tap(find.text('Payton Adams'));
    await tester.tap(find.text('Harrison Young'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField).first, 'morales');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drew Morales'));
    await tester.pumpAndSettle();
    expect(_buttonLabel(tester), 'Send to 3 chats');

    await tester.tap(_sendButton());
    await tester.pumpAndSettle();
    expect(delivery.sent, [
      '!payton:x share-sheet-check',
      // A merged contact goes to its send_via room.
      '!imsg:x share-sheet-check',
      '!new-Drew Morales:x share-sheet-check',
    ]);
    expect(find.text('chat list'), findsOneWidget);
    expect(find.text('Sent to 3 chats'), findsOneWidget);
  });

  testWidgets('one target opens its chat', (tester) async {
    await pump(tester);
    await tester.tap(find.text('Payton Adams'));
    await tester.pumpAndSettle();
    await tester.tap(_sendButton());
    await tester.pumpAndSettle();
    expect(delivery.sent, ['!payton:x share-sheet-check']);
    expect(find.text('chat !payton:x'), findsOneWidget);
  });

  testWidgets('a failed target is named and stays ticked', (tester) async {
    delivery.failing.add('!drew:x');
    await pump(tester);
    await tester.tap(find.text('Payton Adams'));
    await tester.tap(find.text('Drew Andersen'));
    await tester.pumpAndSettle();
    await tester.tap(_sendButton());
    await tester.pumpAndSettle();
    expect(delivery.sent, ['!payton:x share-sheet-check']);
    expect(find.text('Could not send to Drew Andersen'), findsOneWidget);
    expect(_buttonLabel(tester), 'Send to 1 chat');
    expect(find.text('Share'), findsOneWidget);
  });

  testWidgets('shared files show a count and an empty message field', (
    tester,
  ) async {
    await pump(tester, [
      ContentShareItem({'msgtype': 'm.text', 'body': 'a'}),
      ContentShareItem({'msgtype': 'm.text', 'body': 'b'}),
    ]);
    expect(find.text('2 messages'), findsOneWidget);
    expect(find.text('Add a message'), findsOneWidget);
  });

  String title(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Text)),
      )
      .data!;

  testWidgets('New group creates one group on one network, then sends '
      'there once', (tester) async {
    delivery.bridgeContacts = [
      BridgeContactInput(
        _bridge('gmessages', 'Google Messages'),
        const BridgeUser(
          id: '1',
          name: 'Drew Morales',
          identifiers: ['tel:+13125550188'],
        ),
      ),
    ];
    delivery.reachable['+13125550188'] = const BridgeUser(
      id: 'tel:+13125550188',
    );
    await pump(tester);
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    expect(title(tester), 'New group');
    expect(find.text('New group'), findsOneWidget);
    expect(_buttonLabel(tester), 'Create group and send');
    expect(tester.widget<FilledButton>(_sendButton()).onPressed, isNull);

    await tester.tap(find.text('Harrison Young'));
    await tester.pumpAndSettle();
    expect(delivery.groupPicks, ['Harrison Young']);
    expect(find.byType(InputChip), findsOneWidget);
    // A Matrix chat is not on the group's network.
    expect(find.text('Not on iMessage'), findsWidgets);
    await tester.tap(find.text('Payton Adams'));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsOneWidget);

    await tester.enterText(find.byType(TextField).first, 'morales');
    await tester.pumpAndSettle();
    await tester.tap(find.text('Drew Morales'));
    await tester.pumpAndSettle();
    expect(find.byType(InputChip), findsNWidgets(2));
    expect(title(tester), 'New group chat');
    expect(tester.widget<FilledButton>(_sendButton()).onPressed, isNotNull);

    await tester.tap(_sendButton());
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('group-name')), findsOneWidget);
    await tester.tap(
      find.descendant(
        of: find.byType(NewGroupSheet),
        matching: find.widgetWithText(FilledButton, 'Create group and send'),
      ),
    );
    await tester.pumpAndSettle();
    expect(delivery.created, [
      'imessage id-Harrison Young,tel:+13125550188 ""',
    ]);
    expect(delivery.sent, ['!group:x share-sheet-check']);
    expect(find.text('chat !group:x'), findsOneWidget);
  });

  testWidgets('leaving New group keeps the ticks, which send separately', (
    tester,
  ) async {
    await pump(tester);
    await tester.tap(find.text('Payton Adams'));
    await tester.tap(find.text('Drew Andersen'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('New group'));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.radio_button_checked), findsNothing);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(title(tester), 'Share');
    expect(_buttonLabel(tester), 'Send to 2 chats');

    await tester.tap(_sendButton());
    await tester.pumpAndSettle();
    expect(delivery.created, isEmpty);
    expect(delivery.sent, [
      '!payton:x share-sheet-check',
      '!drew:x share-sheet-check',
    ]);
  });
}
