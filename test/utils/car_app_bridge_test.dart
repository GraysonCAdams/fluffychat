// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/car_app_bridge.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('groupCarConversations', () {
    test('a merged contact lists once, at its newest room', () {
      final groups = groupCarConversations([
        ('!imsg', 'contact_c1'),
        ('!bob', '!bob'),
        ('!sms', 'contact_c1'),
      ], 10);
      expect(groups.map((g) => g.id), ['contact_c1', '!bob']);
      expect(groups.first.roomIds, ['!imsg', '!sms']);
    });

    test('stops at the limit but keeps rooms of listed conversations', () {
      final groups = groupCarConversations([
        ('!a', '!a'),
        ('!imsg', 'contact_c1'),
        ('!b', '!b'),
        ('!sms', 'contact_c1'),
      ], 2);
      expect(groups.map((g) => g.id), ['!a', 'contact_c1']);
      expect(groups.last.roomIds, ['!imsg', '!sms']);
    });
  });

  group('carReplyRoom', () {
    test('answers the room the other side wrote in last', () {
      expect(
        carReplyRoom(
          ['!imsg', '!sms'],
          {'!imsg': DateTime(2026, 1, 1), '!sms': DateTime(2026, 1, 2)},
          sendVia: '!imsg',
        ),
        '!sms',
      );
    });

    test('falls back to send-via when they never wrote', () {
      expect(carReplyRoom(['!imsg', '!sms'], {}, sendVia: '!sms'), '!sms');
      expect(carReplyRoom(['!only'], {'!only': null}), '!only');
    });
  });
}
