// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/merged_contact_list.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'fake_rooms.dart';

void main() {
  late Client client;
  late Room imessage, sms, telegram, other;

  setUp(() async {
    client = await fakeMergedClient();
    imessage = addDirectChat(
      client,
      id: '!imsg:x',
      partner: '@imessage_tel=3a+14045551234:x',
      name: 'Harrison Young',
      lastMessage: 'old',
      lastMessageTime: DateTime(2026, 1, 1),
    );
    other = addDirectChat(
      client,
      id: '!other:x',
      partner: '@bob:x',
      name: 'Bob',
      lastMessage: 'hi',
      lastMessageTime: DateTime(2026, 1, 2),
    );
    sms = addDirectChat(
      client,
      id: '!sms:x',
      partner: '@gmessages_1.2:x',
      name: '(404) 555-1234',
      notificationCount: 2,
      highlightCount: 1,
      lastMessage: 'newest',
      lastMessageTime: DateTime(2026, 1, 3),
    );
    telegram = addDirectChat(
      client,
      id: '!tg:x',
      partner: '@telegram_9:x',
      name: 'Harrison',
      notificationCount: 1,
    );
    setMergedContacts(client, {
      'c_1': {
        'rooms': ['!imsg:x', '!sms:x', '!tg:x'],
        'send_via': '!imsg:x',
        'updated': 1,
      },
    });
  });

  tearDown(() => MergedContactsStore.disposeFor(client));

  /// The rooms in the order the SDK sorts them: newest first.
  List<Room> sorted() => [sms, other, imessage, telegram];

  test('a contact is listed once, where its newest room is', () {
    final list = MergedChatList.build(client, sorted(), (_) => true);
    expect(list.rooms, [sms, other]);
    final contact = list.contacts[sms.id]!;
    expect(contact.id, 'c_1');
    expect(contact.roomIds, ['!imsg:x', '!sms:x', '!tg:x']);
    expect(list.contacts[other.id], isNull);
  });

  test('a contact passes a filter when any of its rooms does', () {
    // Only the Telegram room passes, yet the contact is listed, at the
    // place of its newest room.
    final list = MergedChatList.build(
      client,
      sorted(),
      (room) => room == telegram || room == other,
    );
    expect(list.rooms, [sms, other]);
    final none = MergedChatList.build(
      client,
      sorted(),
      (room) => room == other,
    );
    expect(none.rooms, [other]);
  });

  test('the contact sums unread state and shows the newest message', () {
    final contact = MergedChatList.build(
      client,
      sorted(),
      (_) => true,
    ).contacts[sms.id]!;
    expect(contact.notificationCount, 3);
    expect(contact.highlightCount, 1);
    expect(contact.isUnread, isTrue);
    expect(contact.lastEvent?.body, 'newest');
    // Name and avatar come from the send_via room.
    expect(contact.displayName(), 'Harrison Young');
    expect(contact.sendViaRoom, imessage);
  });

  test('search finds a contact by any of its rooms\' names', () async {
    final contact = MergedContact.ofRoom(client, '!tg:x')!;
    final locals = MatrixLocals(await lookupL10n(const Locale('en')));
    expect(contact.matchesSearch('harrison y', locals), isTrue);
    expect(contact.matchesSearch('555-1234', locals), isTrue);
    expect(contact.matchesSearch('bob', locals), isFalse);
  });

  test('without contacts the list is the filtered rooms', () {
    setMergedContacts(client, {});
    MergedContactsStore.disposeFor(client);
    final list = MergedChatList.build(
      client,
      sorted(),
      (room) => room != telegram,
    );
    expect(list.rooms, [sms, other, imessage]);
    expect(list.contacts, isEmpty);
  });
}
