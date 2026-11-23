// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: deprecated_member_use

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../utils/merged_contacts/fake_rooms.dart';

/// Stands in for the app's Matrix widget, which widgets only ask for its
/// client.
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

void main() {
  late Client client;
  late Room imessage, sms, imessageSpace, smsSpace;

  setUp(() async {
    client = await fakeMergedClient();
    imessage = addDirectChat(
      client,
      id: '!imsg:x',
      partner: '@imessage_tel=3a+14045551234:x',
      name: 'Harrison Young',
      lastMessage: 'old message',
      lastMessageTime: DateTime(2026, 1, 1),
    );
    sms = addDirectChat(
      client,
      id: '!sms:x',
      partner: '@gmessages_1.2:x',
      name: '(404) 555-1234',
      notificationCount: 2,
      lastMessage: 'newest message',
      lastMessageTime: DateTime(2026, 1, 3),
    );
    imessageSpace = Room(id: '!imsgspace:x', client: client);
    smsSpace = Room(id: '!smsspace:x', client: client);
    for (final room in [imessage, sms]) {
      client.presences[room.directChatMatrixID!] = CachedPresence.neverSeen(
        room.directChatMatrixID!,
      );
    }
    setMergedContacts(client, {
      'c_1': {
        'rooms': ['!imsg:x', '!sms:x'],
        'send_via': '!imsg:x',
        'updated': 1,
      },
    });
  });

  tearDown(() => MergedContactsStore.disposeFor(client));

  testWidgets('a merged tile shows the contact across its rooms', (
    tester,
  ) async {
    final contact = MergedContact.ofRoom(client, '!sms:x')!;
    await tester.pumpWidget(
      _app(
        client,
        // The tile stands on the read iMessage room; only the SMS room is
        // unread, which must still make the whole contact unread.
        ChatListItem(
          imessage,
          contact: contact,
          networks: [imessageSpace, smsSpace],
          onTap: () {},
        ),
      ),
    );
    // Localizations load asynchronously before the first real frame.
    await tester.pumpAndSettle();

    // The contact's name (from the send_via room), not the SMS room's.
    expect(find.text('Harrison Young'), findsOneWidget);
    expect(find.text('(404) 555-1234'), findsNothing);
    // The newest message of all rooms is the preview.
    expect(find.text('newest message'), findsOneWidget);
    // Unread in one room makes the whole contact unread: bold name.
    final name = tester.widget<Text>(find.text('Harrison Young'));
    expect(name.style?.fontWeight, FontWeight.w700);
    // One badge per network.
    final badges = tester.widget<NetworkBadges>(find.byType(NetworkBadges));
    expect(badges.distinct.length, 2);
  });

  testWidgets('a read contact is not bold', (tester) async {
    sms.notificationCount = 0;
    final contact = MergedContact.ofRoom(client, '!sms:x')!;
    await tester.pumpWidget(
      _app(
        client,
        ChatListItem(
          imessage,
          contact: contact,
          networks: [imessageSpace, smsSpace],
          onTap: () {},
        ),
      ),
    );
    // Localizations load asynchronously before the first real frame.
    await tester.pumpAndSettle();
    final name = tester.widget<Text>(find.text('Harrison Young'));
    expect(name.style?.fontWeight, isNot(FontWeight.w700));
  });

  testWidgets('more than two networks show a +N pill', (tester) async {
    final third = Room(id: '!tgspace:x', client: client);
    await tester.pumpWidget(
      _app(
        client,
        Center(
          child: NetworkBadges(
            networks: [imessageSpace, smsSpace, third, null, smsSpace],
            size: 20,
            outlineColor: Colors.white,
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('+1'), findsOneWidget);
  });
}
