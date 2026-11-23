// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/contact_identifiers.dart';
import 'package:fluffychat/utils/merged_contacts/suggester.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = ContactIdentifier(IdentifierType.phone, '+14045551234');
const _otherPhone = ContactIdentifier(IdentifierType.phone, '+18664054049');
const _email = ContactIdentifier(IdentifierType.email, 'alice@example.com');
const _name = ContactIdentifier(IdentifierType.name, 'harrison young');

const _imessage = '!imessage-space';
const _gmessages = '!gmessages-space';
const _whatsapp = '!whatsapp-space';

SuggesterChat _chat(
  String roomId, {
  String? network,
  ContactIdentifier? id,
  String? contact,
  bool named = true,
  ContactIdentifier? name,
}) => SuggesterChat(
  roomId: roomId,
  networkId: network,
  identifier: id,
  name: name,
  contactId: contact,
  named: named,
);

void main() {
  test('strong phone match across iMessage and Google Messages', () {
    final result = suggestMerges([
      _chat('!b', network: _gmessages, id: _phone),
      _chat('!a', network: _imessage, id: _phone),
      _chat('!c', network: _imessage, id: _otherPhone),
    ]);
    expect(result, hasLength(1));
    expect(result.single.roomIds, ['!a', '!b']);
    expect(result.single.matchedOn, _phone);
    expect(result.single.strong, isTrue);
    expect(result.single.existingContactId, isNull);
  });

  test('phone match with two rooms on the same network is rejected', () {
    final result = suggestMerges([
      _chat('!a', network: _gmessages, id: _phone),
      _chat('!b', network: _gmessages, id: _phone),
      _chat('!c', network: _imessage, id: _phone),
    ]);
    expect(result, isEmpty);
  });

  test('a chat known by phone matches one known only by the same name', () {
    final result = suggestMerges([
      _chat('!a', network: _imessage, id: _phone, name: _name),
      _chat('!b', network: _gmessages, id: _name, name: _name),
    ]);
    expect(result.single.roomIds, ['!a', '!b']);
    expect(result.single.matchedOn, _name);
    expect(result.single.strong, isFalse);
  });

  test('a shared phone is reported ahead of a shared name', () {
    final result = suggestMerges([
      _chat('!a', network: _imessage, id: _phone, name: _name),
      _chat('!b', network: _gmessages, id: _phone, name: _name),
    ]);
    expect(result.single.matchedOn, _phone);
    expect(result.single.strong, isTrue);
  });

  test('unnamed chats are never suggested', () {
    final result = suggestMerges([
      _chat('!a', network: _gmessages, id: _phone, named: false),
      _chat('!b', network: _imessage, id: _phone),
    ]);
    expect(result, isEmpty);
  });

  test('isContactName rejects numbers, short codes and email addresses', () {
    expect(isContactName('(844) 764-0222'), isFalse);
    expect(isContactName('83356'), isFalse);
    expect(isContactName('someone@example.org'), isFalse);
    expect(isContactName('Harrison Young'), isTrue);
  });

  test('email match is strong', () {
    final result = suggestMerges([
      _chat('!a', network: _imessage, id: _email),
      _chat('!b', network: _whatsapp, id: _email),
    ]);
    expect(result.single.matchedOn, _email);
    expect(result.single.strong, isTrue);
  });

  test('phone and email with the same text do not match each other', () {
    const phoneLike = ContactIdentifier(IdentifierType.email, '+14045551234');
    expect(
      suggestMerges([
        _chat('!a', network: _imessage, id: _phone),
        _chat('!b', network: _whatsapp, id: phoneLike),
      ]),
      isEmpty,
    );
  });

  test('weak name match across different networks', () {
    final result = suggestMerges([
      _chat('!a', network: _whatsapp, id: _name),
      _chat('!b', network: _gmessages, id: _name),
    ]);
    expect(result.single.roomIds, ['!a', '!b']);
    expect(result.single.strong, isFalse);
  });

  test('name match with two rooms on the same network is rejected', () {
    expect(
      suggestMerges([
        _chat('!a', network: _whatsapp, id: _name),
        _chat('!b', network: _whatsapp, id: _name),
        _chat('!c', network: _gmessages, id: _name),
      ]),
      isEmpty,
    );
  });

  test('null networks count as distinct for name matches', () {
    final result = suggestMerges([
      _chat('!a', id: _name),
      _chat('!b', id: _name),
      _chat('!c', network: _whatsapp, id: _name),
    ]);
    expect(result.single.roomIds, ['!a', '!b', '!c']);
  });

  test('chats without an identifier or alone in a group are ignored', () {
    expect(
      suggestMerges([
        _chat('!a', network: _imessage),
        _chat('!b', network: _gmessages),
        _chat('!c', network: _gmessages, id: _phone),
      ]),
      isEmpty,
    );
  });

  test('a room listed twice is counted once', () {
    expect(
      suggestMerges([
        _chat('!a', network: _imessage, id: _phone),
        _chat('!a', network: _imessage, id: _phone),
      ]),
      isEmpty,
    );
  });

  group('dismissals', () {
    test('dismissed pair drops the suggestion', () {
      expect(
        suggestMerges(
          [
            _chat('!a', network: _imessage, id: _phone),
            _chat('!b', network: _gmessages, id: _phone),
          ],
          dismissedPairs: {dismissedPairKey('!b', '!a')},
        ),
        isEmpty,
      );
    });

    test('a room is dropped only when dismissed with every other room', () {
      final chats = [
        _chat('!a', network: _imessage, id: _phone),
        _chat('!b', network: _gmessages, id: _phone),
        _chat('!c', network: _whatsapp, id: _phone),
      ];
      expect(
        suggestMerges(
          chats,
          dismissedPairs: {
            dismissedPairKey('!a', '!b'),
            dismissedPairKey('!a', '!c'),
          },
        ).single.roomIds,
        ['!b', '!c'],
      );
      expect(
        suggestMerges(
          chats,
          dismissedPairs: {dismissedPairKey('!a', '!b')},
        ).single.roomIds,
        ['!a', '!b', '!c'],
      );
    });

    test('existing contact with its only new room dismissed', () {
      expect(
        suggestMerges(
          [
            _chat('!a', network: _imessage, id: _phone, contact: 'x'),
            _chat('!b', network: _whatsapp, id: _phone, contact: 'x'),
            _chat('!n', network: _gmessages, id: _phone),
          ],
          dismissedPairs: {
            dismissedPairKey('!a', '!n'),
            dismissedPairKey('!b', '!n'),
          },
        ),
        isEmpty,
      );
    });

    test('dismissedPairKey is order-independent', () {
      expect(dismissedPairKey('!a', '!b'), dismissedPairKey('!b', '!a'));
    });

    test('dismissedPairKeysFromJson ignores malformed entries', () {
      expect(
        dismissedPairKeysFromJson([
          ['!b', '!a'],
          ['!c', '!d'],
          ['!e'],
          ['!f', '!g', '!h'],
          ['!i', 3],
          ['!j', '!j'],
          'nope',
          null,
        ]),
        {dismissedPairKey('!a', '!b'), dismissedPairKey('!c', '!d')},
      );
      expect(dismissedPairKeysFromJson(null), isEmpty);
      expect(dismissedPairKeysFromJson({'a': 'b'}), isEmpty);
    });
  });

  group('existing contacts', () {
    test('new room is offered for the existing contact', () {
      final result = suggestMerges([
        _chat('!a', network: _imessage, id: _phone, contact: 'x'),
        _chat('!n', network: _gmessages, id: _phone),
      ]);
      expect(result.single.roomIds, ['!a', '!n']);
      expect(result.single.existingContactId, 'x');
    });

    test('rooms already all in one contact give no suggestion', () {
      expect(
        suggestMerges([
          _chat('!a', network: _imessage, id: _phone, contact: 'x'),
          _chat('!b', network: _gmessages, id: _phone, contact: 'x'),
        ]),
        isEmpty,
      );
    });

    test('rooms in two different contacts are skipped', () {
      expect(
        suggestMerges([
          _chat('!a', network: _imessage, id: _phone, contact: 'x'),
          _chat('!b', network: _gmessages, id: _phone, contact: 'y'),
          _chat('!n', network: _whatsapp, id: _phone),
        ]),
        isEmpty,
      );
    });
  });

  test('order is strong first, then by first room ID', () {
    final chats = [
      _chat('!a', network: _whatsapp, id: _name),
      _chat('!b', network: _gmessages, id: _name),
      _chat('!z', network: _imessage, id: _phone),
      _chat('!y', network: _gmessages, id: _phone),
      _chat('!m', network: _imessage, id: _email),
      _chat('!n', network: _gmessages, id: _email),
    ];
    List<List<String>> ids(List<MergeSuggestion> s) =>
        s.map((suggestion) => suggestion.roomIds).toList();
    final expected = [
      ['!m', '!n'],
      ['!y', '!z'],
      ['!a', '!b'],
    ];
    expect(ids(suggestMerges(chats)), expected);
    expect(ids(suggestMerges(chats.reversed.toList())), expected);
  });
}
