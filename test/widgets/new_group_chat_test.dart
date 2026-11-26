// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/merged_contacts/fake_rooms.dart';

/// A client with rooms set by hand, like [fakeMergedClient], that reports
/// a user ID for the page's own-address line. It has no homeserver, so the
/// user directory search fails and the page shows only the people rows.
class _LoggedInClient extends Client {
  _LoggedInClient(super.clientName, {required super.database});

  @override
  String? get userID => ownUserId;
}

Future<Client> _client() async {
  sqfliteFfiInit();
  return _LoggedInClient(
    'new group test',
    database: await MatrixSdkDatabase.init(
      'new group test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );
}

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

final _imessage = _bridge('imessage', 'iMessage');
final _gmessages = _bridge('gmessages', 'Google Messages');
final _telegram = _bridge('telegram', 'Telegram');

const _imessageGroup = BridgeGroupType(id: 'group', nameAllowed: true);
const _smsGroup = BridgeGroupType(id: 'group', minParticipants: 2);

/// Records what New Chat asks the bridges for instead of reaching them.
class _FakeDelivery extends NewChatDelivery {
  final Client client;

  _FakeDelivery(this.client);

  List<BridgeContactInput> bridgeContacts = const [];

  /// What the group network picker answers; null is the user closing it.
  GroupNetwork? groupNetwork = const GroupNetwork(
    BridgeInfo(
      name: 'imessage',
      networkId: 'imessage',
      displayName: 'iMessage',
      icon: null,
      loginId: 'login-imessage',
    ),
    _imessageGroup,
  );
  final List<String> groupPicks = [];

  /// What `resolve_identifier` knows, by identifier.
  final Map<String, BridgeUser> reachable = {};
  final List<String> resolved = [];

  /// One entry per `create_group`: network, participants and name.
  final List<String> created = [];

  @override
  Future<void> loadSources(Client client, NewChatSources sources) async {
    sources.bridgeContacts = bridgeContacts;
  }

  @override
  Future<(GroupNetwork, BridgeUser)?> pickGroupNetwork(
    BuildContext context,
    Client client,
    NewChatPerson person,
  ) async {
    groupPicks.add(person.name);
    final network = groupNetwork;
    if (network == null) return null;
    return (network, BridgeUser(id: 'id-${person.name}'));
  }

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
    addDirectChat(client, id: '!group:x', partner: '@group:x', name: 'G');
    return const CreatedGroup('!group:x');
  }
}

Widget _app(Client client, _FakeDelivery delivery, {bool startGroup = false}) {
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
  return Provider<MatrixState>.value(
    value: _FakeMatrix(client),
    child: MaterialApp.router(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      routerConfig: router,
    ),
  );
}

void main() {
  late Client client;
  late _FakeDelivery delivery;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await _client();
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
    addDirectChat(
      client,
      id: '!quade:x',
      partner: '@quade:x',
      name: 'Quade Matrix',
    );
  });

  Future<void> pump(WidgetTester tester, {bool startGroup = false}) async {
    tester.view.physicalSize = const Size(1200, 3000);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(_app(client, delivery, startGroup: startGroup));
    await tester.pumpAndSettle();
  }

  Future<void> search(WidgetTester tester, String text) async {
    await tester.enterText(find.byType(TextField).first, text);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();
  }

  String title(WidgetTester tester) => tester
      .widget<Text>(
        find.descendant(of: find.byType(AppBar), matching: find.byType(Text)),
      )
      .data!;

  Finder chip(String key) => find.byKey(ValueKey('group-chip-$key'));

  ListTile tileOf(WidgetTester tester, String name) => tester.widget<ListTile>(
    find.ancestor(of: find.text(name), matching: find.byType(ListTile)).first,
  );

  testWidgets('a tap opens the one-to-one chat', (tester) async {
    await pump(tester);
    await search(tester, 'quade');
    await tester.tap(find.text('Quade Matrix'));
    await tester.pumpAndSettle();
    expect(find.text('chat !quade:x'), findsOneWidget);
    expect(delivery.groupPicks, isEmpty);
  });

  testWidgets('Create group picks people with a tap from the start', (
    tester,
  ) async {
    await pump(tester, startGroup: true);
    expect(title(tester), 'New group chat');
    await search(tester, 'quinn');
    await tester.tap(find.text('Quinn Imsg'));
    await tester.pumpAndSettle();
    expect(delivery.groupPicks, ['Quinn Imsg']);
    expect(chip('+14045550101'), findsOneWidget);
    expect(find.text('chat !quinn:x'), findsNothing);
  });

  testWidgets('a long-press adds a chip; at two the title and Next change', (
    tester,
  ) async {
    await pump(tester);
    expect(title(tester), 'New chat');
    await search(tester, 'quinn');
    await tester.longPress(find.text('Quinn Imsg'));
    await tester.pumpAndSettle();
    expect(delivery.groupPicks, ['Quinn Imsg']);
    expect(chip('+14045550101'), findsOneWidget);
    expect(find.byKey(const ValueKey('group-network')), findsOneWidget);
    expect(find.text('Anyone else?'), findsOneWidget);
    expect(title(tester), 'New chat');
    expect(find.text('Next'), findsNothing);

    // With someone picked, a tap adds rather than opening a chat. The
    // network already lists this person, so nothing is resolved.
    await search(tester, 'quinby');
    await tester.tap(find.text('Quinby Imsg'));
    await tester.pumpAndSettle();
    expect(delivery.resolved, isEmpty);
    expect(chip('+14045550102'), findsOneWidget);
    expect(title(tester), 'New group chat');
    expect(find.text('Next'), findsOneWidget);
    expect(delivery.groupPicks, hasLength(1));
  });

  testWidgets('the first pick fixes the network for everyone after', (
    tester,
  ) async {
    await pump(tester);
    await search(tester, 'quinn');
    await tester.longPress(find.text('Quinn Imsg'));
    await tester.pumpAndSettle();

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
    expect(tileOf(tester, 'Quill Sms').enabled, isFalse);
  });

  testWidgets('a typed number is added with Enter', (tester) async {
    delivery.reachable['+14045550199'] = const BridgeUser(
      id: 'tel:+14045550199',
    );
    await pump(tester);
    await search(tester, 'quinn');
    await tester.longPress(find.text('Quinn Imsg'));
    await tester.pumpAndSettle();
    await search(tester, '404-555-0199');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(chip('+14045550199'), findsOneWidget);
    expect(title(tester), 'New group chat');
  });

  testWidgets('removing every chip resets the network', (tester) async {
    await pump(tester);
    await search(tester, 'quinn');
    await tester.longPress(find.text('Quinn Imsg'));
    await tester.pumpAndSettle();
    await tester.tap(
      find.descendant(
        of: chip('+14045550101'),
        matching: find.byTooltip('Remove'),
      ),
    );
    await tester.pumpAndSettle();
    expect(chip('+14045550101'), findsNothing);
    expect(find.byKey(const ValueKey('group-network')), findsNothing);

    await search(tester, 'quentin');
    expect(tileOf(tester, 'Quentin Tg').enabled, isTrue);
    expect(find.text('Not on iMessage'), findsNothing);
  });

  Future<void> pickTwo(WidgetTester tester) async {
    await pump(tester);
    await search(tester, 'quinn');
    await tester.longPress(find.text('Quinn Imsg'));
    await tester.pumpAndSettle();
    await search(tester, 'quinby');
    await tester.tap(find.text('Quinby Imsg'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Next'));
    await tester.pumpAndSettle();
  }

  testWidgets('Create group names it on iMessage and opens the room', (
    tester,
  ) async {
    await pickTwo(tester);
    expect(find.text('Group name (optional)'), findsOneWidget);
    expect(find.text('Quinn Imsg, Quinby Imsg'), findsOneWidget);
    await tester.enterText(find.byKey(const ValueKey('group-name')), 'Trip');
    await tester.tap(find.widgetWithText(FilledButton, 'Create group'));
    await tester.pumpAndSettle();
    expect(delivery.created, [
      'imessage/group id-Quinn Imsg,tel:+14045550102 "Trip"',
    ]);
    expect(find.text('chat !group:x'), findsOneWidget);
  });

  testWidgets('a network without group names shows no name field', (
    tester,
  ) async {
    delivery.groupNetwork = GroupNetwork(_gmessages, _smsGroup);
    delivery.bridgeContacts = [
      for (final contact in delivery.bridgeContacts)
        BridgeContactInput(_gmessages, contact.user),
    ];
    await pickTwo(tester);
    expect(find.byKey(const ValueKey('group-name')), findsNothing);
    await tester.tap(find.widgetWithText(FilledButton, 'Create group'));
    await tester.pumpAndSettle();
    expect(delivery.created, [
      'gmessages/group id-Quinn Imsg,tel:+14045550102 ""',
    ]);
  });
}
