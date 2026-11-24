// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/android_share_targets.dart';
import 'package:fluffychat/utils/merged_contacts/conversation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // '!imsg' and '!sms' are the same person, merged as contact c_1.
  const contacts = {'!imsg:x': 'c_1', '!sms:x': 'c_1'};
  String? contactIdOf(String roomId) => contacts[roomId];

  group('conversation IDs', () {
    test('a plain room is its own conversation', () {
      expect(conversationId('!bob:x', null), '!bob:x');
      expect(contactIdOfConversation('!bob:x'), isNull);
    });

    test('a merged contact is contact_<id> and reads back', () {
      expect(conversationId('!imsg:x', 'c_1'), 'contact_c_1');
      expect(contactIdOfConversation('contact_c_1'), 'c_1');
    });
  });

  group('selectShareTargets', () {
    test('a merged contact is offered once, where its newest room is', () {
      final targets = selectShareTargets([
        '!sms:x',
        '!bob:x',
        '!imsg:x',
        '!group:x',
      ], contactIdOf);
      expect(targets, const [
        ShareTarget('contact_c_1', '!sms:x'),
        ShareTarget('!bob:x', '!bob:x'),
        ShareTarget('!group:x', '!group:x'),
      ]);
    });

    test('stops at the maximum, counting a contact once', () {
      final targets = selectShareTargets(
        ['!imsg:x', '!sms:x', '!a:x', '!b:x', '!c:x'],
        contactIdOf,
        max: 3,
      );
      expect(targets.map((t) => t.shortcutId), ['contact_c_1', '!a:x', '!b:x']);
    });
  });

  group('shareTargetRoute', () {
    String? route(
      String shortcutId, {
      Set<String> rooms = const {'!bob:x', '!imsg:x', '!sms:x'},
      Set<String> contactIds = const {'c_1'},
    }) => shareTargetRoute(
      shortcutId,
      hasRoom: rooms.contains,
      hasContact: contactIds.contains,
      contactIdOf: contactIdOf,
    );

    test('a merged contact opens its merged screen', () {
      expect(route('contact_c_1'), '/rooms/contact/c_1');
    });

    test('a plain room opens the room', () {
      expect(route('!bob:x'), '/rooms/!bob:x');
    });

    test(
      'a room merged after its shortcut was published opens the contact',
      () {
        expect(route('!sms:x'), '/rooms/contact/c_1');
      },
    );

    test('a chat that is gone opens nothing', () {
      expect(route('!gone:x'), isNull);
      expect(route('contact_c_9'), isNull);
      expect(route('contact_c_1', contactIds: const {}), isNull);
    });
  });
}
