// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/contact_identifiers.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'fake_rooms.dart';

void main() {
  late Client client;
  late MergeSuggestionService service;
  late List<String> fetched;
  late Map<String, Object?> profiles;

  setUp(() async {
    client = await fakeMergedClient();
    // Harrison: iMessage encodes the number in the user ID; the SMS chat
    // has no number in its ID and is titled with the formatted number, which
    // makes it an unnamed chat that is never suggested.
    addDirectChat(
      client,
      id: '!imsg-h:x',
      partner: '@imessage_tel=3a+14045551234:x',
      name: 'Harrison Young',
    );
    addDirectChat(
      client,
      id: '!sms-h:x',
      partner: '@gmessages_1.1:x',
      name: '(404) 555-1234',
    );
    // Parla: the SMS chat is named, and only the bridge's profile field
    // carries her number.
    addDirectChat(
      client,
      id: '!imsg-p:x',
      partner: '@imessage_tel=3a+13125550100:x',
      name: 'Parla',
    );
    addDirectChat(
      client,
      id: '!sms-p:x',
      partner: '@gmessages_1.2:x',
      name: 'Parla H',
    );
    // A plain Matrix user, never asked for bridge identifiers.
    addDirectChat(client, id: '!bob:x', partner: '@bob:x', name: 'Bob');
    fetched = [];
    profiles = {
      '@gmessages_1.2:x': ['tel:+13125550100'],
    };
    service = MergeSuggestionService(
      client,
      isEnabled: () => true,
      phoneRegion: () => 'US',
      fetchProfileIdentifiers: (userId) async {
        fetched.add(userId);
        return profiles[userId];
      },
    );
  });

  tearDown(() {
    service.dispose();
    MergedContactsStore.disposeFor(client);
  });

  test(
    'finds the same number across bridges from profile fields, named only',
    () async {
      await service.refresh();
      final suggestions = service.suggestions.value;
      expect(suggestions.every((s) => s.strong), isTrue);
      expect(suggestions.map((s) => s.roomIds), [
        ['!imsg-p:x', '!sms-p:x'],
      ]);
      expect(
        suggestions.map((s) => s.matchedOn),
        contains(const ContactIdentifier(IdentifierType.phone, '+13125550100')),
      );
      // Only bridge ghosts without a number in their ID are asked.
      expect(fetched.toSet(), {'@gmessages_1.1:x', '@gmessages_1.2:x'});
    },
  );

  test('profile answers are not fetched twice', () async {
    await service.refresh();
    final first = fetched.length;
    await service.refresh();
    expect(fetched.length, first);
  });

  test('a failed fetch is retried on the next pass', () async {
    var fail = true;
    final flaky = MergeSuggestionService(
      client,
      isEnabled: () => true,
      phoneRegion: () => 'US',
      fetchProfileIdentifiers: (userId) async {
        fetched.add(userId);
        if (fail) throw Exception('offline');
        return profiles[userId];
      },
    );
    await flaky.refresh();
    expect(
      flaky.suggestions.value.map((s) => s.roomIds),
      isNot(contains(equals(['!imsg-p:x', '!sms-p:x']))),
    );
    fail = false;
    await flaky.refresh();
    expect(
      flaky.suggestions.value.map((s) => s.roomIds),
      contains(equals(['!imsg-p:x', '!sms-p:x'])),
    );
    flaky.dispose();
  });

  test('merged and dismissed chats are no longer suggested', () async {
    // As another device would have written it (the test client cannot
    // reach a server).
    client.accountData['im.fluffychat.merged_contacts'] = BasicEvent(
      type: 'im.fluffychat.merged_contacts',
      content: {
        'version': 1,
        'contacts': {
          'c_1': {
            'rooms': ['!imsg-h:x', '!sms-h:x'],
            'updated': 1,
          },
        },
        'dismissed_suggestions': [
          ['!imsg-p:x', '!sms-p:x'],
        ],
      },
    );
    await service.refresh();
    expect(service.suggestions.value, isEmpty);
  });

  test('a group listed in m.direct is never suggested', () async {
    // Parla's iMessage chat gains another person: it is a group now, even
    // though m.direct still lists it.
    final group = client.getRoomById('!imsg-p:x')!;
    group.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'displayname': 'Ana'},
        senderId: '@imessage_tel=3a+13125550199:x',
        stateKey: '@imessage_tel=3a+13125550199:x',
      ),
    );
    group.summary
      ..mHeroes = [
        '@imessage_tel=3a+13125550100:x',
        '@imessage_tel=3a+13125550199:x',
      ]
      ..mJoinedMemberCount = 3;
    await service.refresh();
    expect(service.suggestions.value, isEmpty);
  });

  test('a bridge group room is never suggested', () async {
    client
        .getRoomById('!sms-p:x')!
        .setState(
          StrippedStateEvent(
            type: 'm.bridge',
            content: {
              'bridgebot': '@gmessagesbot:x',
              'com.beeper.room_type': 'group',
            },
            senderId: '@gmessagesbot:x',
            stateKey: 'gmessages',
          ),
        );
    await service.refresh();
    expect(service.suggestions.value, isEmpty);
  });

  test('a direct chat that keeps its bridge bot is still suggested', () async {
    final dm = client.getRoomById('!imsg-p:x')!;
    dm.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'displayname': 'iMessage bridge bot'},
        senderId: '@imessagebot:x',
        stateKey: '@imessagebot:x',
      ),
    );
    dm.setState(
      StrippedStateEvent(
        type: 'io.element.functional_members',
        content: {
          'service_members': ['@imessagebot:x'],
        },
        senderId: '@imessagebot:x',
        stateKey: '',
      ),
    );
    dm.summary
      ..mHeroes = ['@imessage_tel=3a+13125550100:x', '@imessagebot:x']
      ..mJoinedMemberCount = 3;
    await service.refresh();
    expect(service.suggestions.value.map((s) => s.roomIds), [
      ['!imsg-p:x', '!sms-p:x'],
    ]);
  });

  test('a chat its bridge calls a dm is suggested without m.direct', () async {
    // The SMS chat with Parla drops out of m.direct; its bridge state still
    // says it is a one-to-one chat with her.
    final direct = Map<String, Object?>.from(
      client.accountData['m.direct']!.content,
    )..remove('@gmessages_1.2:x');
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: direct,
    );
    final sms = client.getRoomById('!sms-p:x')!;
    sms.setState(
      StrippedStateEvent(
        type: 'm.bridge',
        content: {'bridgebot': '@gmessagesbot:x', 'com.beeper.room_type': 'dm'},
        senderId: '@gmessagesbot:x',
        stateKey: 'gmessages',
      ),
    );
    sms.summary
      ..mHeroes = ['@gmessages_1.2:x', '@gmessagesbot:x']
      ..mJoinedMemberCount = 3;
    await service.refresh();
    expect(service.suggestions.value.map((s) => s.roomIds), [
      ['!imsg-p:x', '!sms-p:x'],
    ]);
  });

  test('turned off, nothing is suggested', () async {
    final off = MergeSuggestionService(
      client,
      isEnabled: () => false,
      fetchProfileIdentifiers: (userId) async => null,
    );
    await off.refresh();
    expect(off.suggestions.value, isEmpty);
    off.dispose();
  });
}
