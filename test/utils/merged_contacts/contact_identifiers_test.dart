// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/contact_identifiers.dart';
import 'package:flutter_test/flutter_test.dart';

const _phone = ContactIdentifier(IdentifierType.phone, '+14045551234');
const _alice = ContactIdentifier(IdentifierType.email, 'alice@example.com');
const _bob = ContactIdentifier(IdentifierType.email, 'bob@example.com');

void main() {
  group('ContactIdentifier JSON', () {
    test('round trips', () {
      expect(_phone.toJson(), {'type': 'phone', 'value': '+14045551234'});
      expect(ContactIdentifier.fromJson(_phone.toJson()), _phone);
      expect(ContactIdentifier.fromJson(_alice.toJson()), _alice);
      const name = ContactIdentifier(IdentifierType.name, 'zoë');
      expect(ContactIdentifier.fromJson(name.toJson()), name);
    });

    test('rejects malformed input', () {
      expect(ContactIdentifier.fromJson(null), isNull);
      expect(ContactIdentifier.fromJson('phone'), isNull);
      expect(ContactIdentifier.fromJson({'type': 'fax', 'value': '1'}), isNull);
      expect(ContactIdentifier.fromJson({'type': 'phone'}), isNull);
      expect(ContactIdentifier.fromJson({'type': 'phone', 'value': 1}), isNull);
      expect(
        ContactIdentifier.fromJson({'type': 'phone', 'value': ''}),
        isNull,
      );
    });
  });

  group('identifiersFromUserId', () {
    test('iMessage phone ghost', () {
      expect(
        identifiersFromUserId(
          '@imessage_tel=3a+14045551234:d.graysons.network',
        ),
        [_phone],
      );
    });

    test('iMessage email ghost', () {
      expect(
        identifiersFromUserId(
          '@imessage_mailto=3aalice=40example.com:d.graysons.network',
        ),
        [_alice],
      );
    });

    test('decodes mautrix upper-case and underscore escapes', () {
      expect(
        identifiersFromUserId(
          '@imessage_mailto=3a_alice__smith=40example.com:server',
        ),
        [
          const ContactIdentifier(
            IdentifierType.email,
            'alice_smith@example.com',
          ),
        ],
      );
    });

    test('escaped plus sign', () {
      expect(identifiersFromUserId('@imessage_tel=3a=2b14045551234:server'), [
        _phone,
      ]);
    });

    test('other bridge prefixes with the same shape', () {
      expect(identifiersFromUserId('@sms_tel=3a+14045551234:server'), [_phone]);
    });

    test('Google Messages ghost carries no handle', () {
      expect(
        identifiersFromUserId('@gmessages_1.42:d.graysons.network'),
        isEmpty,
      );
    });

    test('ordinary user has no handle', () {
      expect(identifiersFromUserId('@alice:matrix.org'), isEmpty);
      expect(identifiersFromUserId('@tel:matrix.org'), isEmpty);
    });

    test('short code in a tel handle is not a phone', () {
      expect(identifiersFromUserId('@imessage_tel=3a83356:server'), isEmpty);
    });
  });

  group('identifiersFromProfileList', () {
    test('tel and mailto entries', () {
      expect(
        identifiersFromProfileList([
          'tel:+14045551234',
          'mailto:Bob@Example.com',
        ]),
        [_phone, _bob],
      );
    });

    test('ignores junk and duplicates', () {
      expect(
        identifiersFromProfileList([
          42,
          null,
          'nonsense',
          'fax:+14045551234',
          'tel:83356',
          'mailto:not-an-email',
          'tel:+1 404 555 1234',
          'tel:+14045551234',
        ]),
        [_phone],
      );
    });

    test('non-list values give nothing', () {
      expect(identifiersFromProfileList(null), isEmpty);
      expect(identifiersFromProfileList('tel:+14045551234'), isEmpty);
      expect(identifiersFromProfileList({'tel': '+14045551234'}), isEmpty);
    });
  });

  group('normalizeName', () {
    test('case, whitespace and punctuation', () {
      expect(normalizeName('Harrison  Young!'), 'harrison young');
      expect(normalizeName('  Dr. J.  R.  Smith-Jones '), 'dr j r smithjones');
      expect(normalizeName('Line\tbreak\nname'), 'line break name');
    });

    test('keeps non-ASCII letters', () {
      expect(normalizeName('Zoë'), 'zoë');
      expect(normalizeName('Søren Ørsted'), 'søren ørsted');
    });

    test('punctuation only becomes empty', () {
      expect(normalizeName(' ?! '), '');
    });
  });

  group('primaryIdentifier', () {
    test('user ID phone beats profile email', () {
      expect(
        primaryIdentifier(
          userId: '@imessage_tel=3a+14045551234:server',
          profileIdentifiers: ['mailto:bob@example.com'],
        ),
        _phone,
      );
    });

    test('profile phone beats user ID email', () {
      expect(
        primaryIdentifier(
          userId: '@imessage_mailto=3aalice=40example.com:server',
          profileIdentifiers: ['tel:+14045551234'],
        ),
        _phone,
      );
    });

    test('profile phone beats display name phone', () {
      expect(
        primaryIdentifier(
          userId: '@gmessages_1.42:server',
          profileIdentifiers: ['tel:+14045551234'],
          displayName: '(866) 405-4049',
        ),
        _phone,
      );
    });

    test('display name phone for an unnamed SMS contact', () {
      expect(
        primaryIdentifier(
          userId: '@gmessages_1.42:server',
          displayName: '(866) 405-4049',
        ),
        const ContactIdentifier(IdentifierType.phone, '+18664054049'),
      );
    });

    test('display name phone beats email', () {
      expect(
        primaryIdentifier(
          userId: '@gmessages_1.42:server',
          profileIdentifiers: ['mailto:bob@example.com'],
          displayName: '(866) 405-4049',
        ),
        const ContactIdentifier(IdentifierType.phone, '+18664054049'),
      );
    });

    test('user ID email beats profile email', () {
      expect(
        primaryIdentifier(
          userId: '@imessage_mailto=3aalice=40example.com:server',
          profileIdentifiers: ['mailto:bob@example.com'],
          displayName: 'Alice',
        ),
        _alice,
      );
    });

    test('email beats name', () {
      expect(
        primaryIdentifier(
          userId: '@gmessages_1.42:server',
          profileIdentifiers: ['mailto:Bob@Example.com'],
          displayName: 'Bob',
        ),
        _bob,
      );
    });

    test('falls back to the normalised name', () {
      expect(
        primaryIdentifier(
          userId: '@gmessages_1.42:server',
          displayName: 'Harrison  Young!',
        ),
        const ContactIdentifier(IdentifierType.name, 'harrison young'),
      );
    });

    test('short code and alphanumeric senders fall through to name', () {
      expect(
        primaryIdentifier(
          userId: '@gmessages_1.1:server',
          displayName: '83356',
        ),
        const ContactIdentifier(IdentifierType.name, '83356'),
      );
      expect(
        primaryIdentifier(
          userId: '@gmessages_1.2:server',
          displayName: 'AMAZON',
        ),
        const ContactIdentifier(IdentifierType.name, 'amazon'),
      );
    });

    test('null when nothing is usable', () {
      expect(primaryIdentifier(userId: '@gmessages_1.42:server'), isNull);
      expect(
        primaryIdentifier(userId: '@gmessages_1.42:server', displayName: '!!'),
        isNull,
      );
    });
  });
}
