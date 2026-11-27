// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/group_members_collage.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_search/search_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  test('a group without a picture gets its members as the toast avatar', () async {
    final client = await createSearchTestClient();
    final room = client.rooms.firstWhere(
      (room) => !room.isSpace && !room.isDirectChat,
    );
    expect(GroupAvatar.shows(room), isTrue);

    for (final id in ['@alice:example.org', '@bob:example.org']) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          stateKey: id,
          senderId: id,
          content: {'membership': 'join', 'displayname': id.substring(1, 4)},
        ),
      );
    }
    final bytes = await groupMembersCollage(client, room);

    expect(bytes, isNotNull);
    // A PNG.
    expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4e, 0x47]);
  });

  test('a direct chat is not drawn as a collage', () async {
    final client = await createSearchTestClient();
    final dm = client.getRoomById('!726s6s6q:example.com')!;
    expect(GroupAvatar.shows(dm), isFalse);
  });
}
