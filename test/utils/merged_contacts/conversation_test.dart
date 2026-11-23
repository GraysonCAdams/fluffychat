// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/conversation.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'fake_rooms.dart';

void main() {
  late Client client;

  setUp(() async {
    client = await fakeMergedClient();
    final imessage = addDirectChat(
      client,
      id: '!imsg:x',
      partner: '@imessage_tel=3a+1:x',
      name: 'Harrison',
      notificationCount: 1,
    );
    addDirectChat(client, id: '!sms:x', partner: '@gmessages_1.2:x', name: 'H');
    addDirectChat(client, id: '!bob:x', partner: '@bob:x', name: 'Bob');
    setMergedContacts(client, {
      'c_1': {
        'rooms': ['!imsg:x', '!sms:x'],
        'send_via': '!imsg:x',
        'updated': 1,
      },
    });
    expect(imessage.notificationCount, 1);
  });

  tearDown(() => MergedContactsStore.disposeFor(client));

  test('the active chat of a route', () {
    expect(activeChatOfPath('/rooms/!a:x'), '!a:x');
    expect(activeChatOfPath('/rooms/contact/c_1'), 'contact:c_1');
    expect(activeChatOfPath('/rooms/!a:x/details'), '!a:x');
    expect(activeChatOfPath('/settings'), isNull);
  });

  test('a room of the open merged contact counts as on screen', () {
    expect(isChatActive('contact:c_1', client, '!sms:x'), isTrue);
    expect(isChatActive('!imsg:x', client, '!imsg:x'), isTrue);
    expect(isChatActive('contact:c_1', client, '!bob:x'), isFalse);
    expect(isChatActive('!imsg:x', client, '!sms:x'), isFalse);
    expect(isChatActive(null, client, '!bob:x'), isFalse);
  });

  test('a merged contact\'s rooms share one notification conversation', () {
    expect(notificationConversation(client, '!imsg:x'), 'contact_c_1');
    expect(notificationConversation(client, '!sms:x'), 'contact_c_1');
    expect(notificationConversation(client, '!bob:x'), '!bob:x');
    expect(
      notificationConversationName(
        client,
        '!sms:x',
        const MatrixDefaultLocalizations(),
      ),
      'Harrison',
    );
  });

  test('the contact\'s notification stays until all its rooms are read', () {
    // Reading the SMS room leaves iMessage unread.
    expect(notificationConversationRead(client, '!sms:x'), isFalse);
    client.getRoomById('!imsg:x')!.notificationCount = 0;
    expect(notificationConversationRead(client, '!sms:x'), isTrue);
    expect(notificationConversationRead(client, '!bob:x'), isTrue);
  });
}
