// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:flutter_test/flutter_test.dart';

BridgeInfo _bridge(String name, {String? space}) => BridgeInfo(
  name: name,
  networkId: name,
  displayName: name.toUpperCase(),
  icon: null,
  loginId: 'login-$name',
  spaceRoomId: space,
);

void main() {
  group('typedPhoneNumber', () {
    test('accepts the ways people type a number', () {
      expect(typedPhoneNumber('404 555 1234'), '+14045551234');
      expect(typedPhoneNumber('(404) 555-1234'), '+14045551234');
      expect(typedPhoneNumber('+1 404.555.1234'), '+14045551234');
      expect(typedPhoneNumber('+44 20 7946 0958'), '+442079460958');
      expect(typedPhoneNumber(' 14045551234 '), '+14045551234');
    });

    test('rejects names, IDs, short codes and partial numbers', () {
      expect(typedPhoneNumber('alice'), isNull);
      expect(typedPhoneNumber('@alice:example.com'), isNull);
      expect(typedPhoneNumber('83356'), isNull);
      expect(typedPhoneNumber('404 555'), isNull);
      expect(typedPhoneNumber('404555123'), isNull);
      expect(typedPhoneNumber('call 4045551234'), isNull);
      expect(typedPhoneNumber(''), isNull);
    });

    test('needs a + outside the US and Canada', () {
      expect(typedPhoneNumber('4045551234', defaultRegion: 'other'), isNull);
      expect(
        typedPhoneNumber('+4045551234', defaultRegion: 'other'),
        '+4045551234',
      );
    });
  });

  group('matchesPersonQuery', () {
    test('matches the name, an email or the digits of a number', () {
      expect(matchesPersonQuery('ali', name: 'Alice'), isTrue);
      expect(
        matchesPersonQuery('bob@', name: 'X', emails: ['bob@example.com']),
        isTrue,
      );
      expect(
        matchesPersonQuery('555-12', name: 'X', phones: ['+14045551234']),
        isTrue,
      );
      expect(matchesPersonQuery('99', name: 'X', phones: ['+199']), isFalse);
      expect(matchesPersonQuery('', name: 'Alice'), isFalse);
    });
  });

  group('mergeNewChatPeople', () {
    final gmessages = _bridge('gmessages', space: '!gm-space:hs');

    test('one row per person across chats, bridges and the phone', () {
      final people = mergeNewChatPeople<String>(
        query: 'ali',
        chats: [
          const ChatPersonInput(
            chat: '!alice-imessage:hs',
            name: 'Alice',
            phone: '+14045551234',
            userIds: ['@imessage_tel=3a+14045551234:hs'],
            networks: [NetworkRef(key: '!imsg-space:hs', name: 'iMessage')],
          ),
        ],
        bridgeContacts: [
          BridgeContactInput(
            gmessages,
            const BridgeUser(
              id: 'c1',
              name: 'Alice Smith',
              identifiers: ['tel:(404) 555-1234'],
              mxid: '@gmessages_1.1:hs',
            ),
          ),
          BridgeContactInput(
            gmessages,
            const BridgeUser(
              id: 'c2',
              name: 'Alina',
              identifiers: ['tel:+15551230000'],
            ),
          ),
        ],
        phoneBook: const [
          PhoneBookEntry(name: 'Alice S', phones: ['404-555-1234']),
          PhoneBookEntry(
            name: 'Alina Phone',
            phones: ['+1 555 123 0000'],
            emails: ['ALINA@example.com'],
          ),
          PhoneBookEntry(name: 'Alix', emails: ['alix@example.com']),
          PhoneBookEntry(name: 'Alvin'),
        ],
      );

      expect(people.map((p) => p.name), ['Alice', 'Alina Phone', 'Alix']);
      final alice = people[0];
      expect(alice.chat, '!alice-imessage:hs');
      expect(alice.inPhoneBook, isTrue);
      expect(alice.networks.map((n) => n.key), [
        '!imsg-space:hs',
        '!gm-space:hs',
      ]);
      expect(alice.bridgeUsers.keys, ['gmessages']);
      final alina = people[1];
      expect(alina.chat, isNull);
      expect(alina.phones, ['+15551230000']);
      expect(alina.emails, ['alina@example.com']);
      expect(alina.networks.map((n) => n.name), ['GMESSAGES']);
    });

    test('a bridge contact joins a chat by ghost ID without a number', () {
      final people = mergeNewChatPeople<String>(
        query: 'bob',
        chats: [
          const ChatPersonInput(
            chat: '!bob:hs',
            name: 'Bob',
            userIds: ['@telegram_42:hs'],
          ),
        ],
        bridgeContacts: [
          BridgeContactInput(
            _bridge('telegram'),
            const BridgeUser(id: '42', name: 'Bob', mxid: '@telegram_42:hs'),
          ),
        ],
      );
      expect(people, hasLength(1));
      expect(people.single.networks.single.key, 'bridge:telegram');
    });

    test('two chats with the same number stay separate', () {
      final people = mergeNewChatPeople<String>(
        query: 'carol',
        chats: const [
          ChatPersonInput(chat: '!a', name: 'Carol', phone: '+14045550000'),
          ChatPersonInput(chat: '!b', name: 'Carol', phone: '+14045550000'),
        ],
      );
      expect(people.map((p) => p.chat), ['!a', '!b']);
    });

    test('a typed number gets its own row unless someone has it', () {
      final unknown = mergeNewChatPeople<String>(query: '404 555 9999');
      expect(unknown.single.typed, isTrue);
      expect(unknown.single.phone, '+14045559999');
      expect(unknown.single.name, '+1 404 555 9999');

      final known = mergeNewChatPeople<String>(
        query: '(404) 555-1234',
        phoneBook: const [
          PhoneBookEntry(name: 'Dana', phones: ['+14045551234']),
        ],
      );
      expect(known.single.name, 'Dana');
      expect(known.single.typed, isFalse);
    });

    test('an unnamed phone book entry is shown by its number', () {
      final people = mergeNewChatPeople<String>(
        query: '555',
        phoneBook: const [
          PhoneBookEntry(name: '', phones: ['4045551234']),
        ],
      );
      expect(people.single.name, '+1 404 555 1234');
    });

    test('rows without a chat are sorted by name', () {
      final people = mergeNewChatPeople<String>(
        query: 'e',
        phoneBook: const [
          PhoneBookEntry(name: 'zed', phones: ['+14045550001']),
          PhoneBookEntry(name: 'Eve', phones: ['+14045550002']),
        ],
      );
      expect(people.map((p) => p.name), ['Eve', 'zed']);
    });
  });

  test('picker order is iMessage, Google Messages, then the rest', () {
    final ordered = orderBridgesForSwitcher([
      _bridge('telegram'),
      _bridge('gmessages'),
      _bridge('linkedin'),
      _bridge('imessage'),
    ]);
    expect(ordered.map((b) => b.name), [
      'imessage',
      'gmessages',
      'telegram',
      'linkedin',
    ]);
  });

  test('identifierForBridge prefers the ghost, then phone, then email', () {
    final person = NewChatPerson<String>('Eve');
    expect(identifierForBridge(person, _bridge('imessage')), isNull);
    person.emails.add('eve@example.com');
    expect(identifierForBridge(person, _bridge('imessage')), 'eve@example.com');
    person.phones.add('+14045551234');
    expect(identifierForBridge(person, _bridge('imessage')), '+14045551234');
    person.bridgeUsers['gmessages'] = const BridgeUser(
      id: '1',
      mxid: '@gmessages_1:hs',
    );
    expect(
      identifierForBridge(person, _bridge('gmessages')),
      '@gmessages_1:hs',
    );
    expect(identifierForBridge(person, _bridge('imessage')), '+14045551234');
  });
}
