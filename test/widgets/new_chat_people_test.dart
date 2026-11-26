// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../utils/merged_contacts/fake_rooms.dart';

class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

Widget _app(Client client, Widget child) => Provider<MatrixState>.value(
  value: _FakeMatrix(client),
  child: MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(body: child),
  ),
);

BridgeInfo _bridge(String name, String displayName) => BridgeInfo(
  name: name,
  networkId: name,
  displayName: displayName,
  icon: null,
  loginId: 'login-$name',
);

void main() {
  late Client client;

  setUp(() async => client = await fakeMergedClient());

  testWidgets('a merged list shows each person once with their networks', (
    tester,
  ) async {
    final people = mergeNewChatPeople<String>(
      query: 'ali',
      bridgeContacts: [
        BridgeContactInput(
          _bridge('gmessages', 'Google Messages'),
          const BridgeUser(
            id: '1',
            name: 'Alice',
            identifiers: ['tel:+14045551234'],
          ),
        ),
        BridgeContactInput(
          _bridge('telegram', 'Telegram'),
          const BridgeUser(
            id: '2',
            name: 'Alice T',
            identifiers: ['tel:4045551234'],
          ),
        ),
      ],
      phoneBook: const [
        PhoneBookEntry(name: 'Alice Phone', phones: ['(404) 555-1234']),
      ],
    );
    final tapped = <String>[];
    await tester.pumpWidget(
      _app(
        client,
        ListView(
          children: [
            for (final person in people)
              NewChatPersonTile(
                person: person,
                onTap: () => tapped.add(person.name),
              ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(NewChatPersonTile), findsOneWidget);
    expect(find.text('Alice Phone'), findsOneWidget);
    expect(find.text('+1 404 555 1234'), findsOneWidget);
    final icons = tester.widget<MonochromeNetworkIcons>(
      find.byType(MonochromeNetworkIcons),
    );
    expect(icons.icons.map((icon) => icon.name), [
      'Google Messages',
      'Telegram',
    ]);
    await tester.tap(find.text('Alice Phone'));
    expect(tapped, ['Alice Phone']);
  });

  testWidgets('a typed number is offered as a phone number', (tester) async {
    final people = mergeNewChatPeople<String>(query: '404-555-0000');
    await tester.pumpWidget(
      _app(client, NewChatPersonTile(person: people.single, onTap: () {})),
    );
    await tester.pumpAndSettle();
    expect(find.text('+1 404 555 0000'), findsOneWidget);
    expect(find.text('Phone number'), findsOneWidget);
    expect(find.byIcon(Icons.dialpad_outlined), findsOneWidget);
  });
}
