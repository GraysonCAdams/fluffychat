// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'fake_rooms.dart';

void main() {
  late Client client;

  setUp(() async => client = await fakeMergedClient());

  test(
    'each bridge on the server has a logo colour under its ghost prefix',
    () {
      const ghosts = {
        '@imessage_tel=3a+14045551234:x': 0xFF34C759,
        '@gmessages_1.2:x': 0xFF1A73E8,
        '@telegram_123:x': 0xFF2AABEE,
        '@discord_456:x': 0xFF5865F2,
        '@linkedin_abc:x': 0xFF0A66C2,
        '@xbox_2533274:x': 0xFF107C10,
      };
      var i = 0;
      for (final MapEntry(key: partner, value: argb) in ghosts.entries) {
        final room = addDirectChat(
          client,
          id: '!room${i++}:x',
          partner: partner,
          name: partner,
        );
        final bridgeId = NetworkColors.bridgeIdOf(room);
        expect(
          NetworkColors.defaults[bridgeId]?.toARGB32(),
          argb,
          reason: partner,
        );
      }
    },
  );

  test('a plain Matrix user has no bridge', () {
    final room = addDirectChat(
      client,
      id: '!plain:x',
      partner: '@alice:x',
      name: 'Alice',
    );
    expect(NetworkColors.bridgeIdOf(room), isNull);
  });
}
