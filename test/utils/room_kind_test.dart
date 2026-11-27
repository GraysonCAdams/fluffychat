// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/typing_indicators.dart';
import 'package:fluffychat/pages/chat/typing_run.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'merged_contacts/fake_rooms.dart';

const _gloria = '@imessage_tel=3a+13125550123:x';
const _bot = '@imessagebot:x';

void main() {
  late Client client;

  setUp(() async {
    client = await fakeMergedClient();
  });

  void member(Room room, String userId, String name, {String? avatar}) =>
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          content: {
            'membership': 'join',
            'displayname': name,
            'avatar_url': ?avatar,
          },
          senderId: userId,
          stateKey: userId,
        ),
      );

  void bridge(Room room, {String? roomType}) => room.setState(
    StrippedStateEvent(
      type: 'm.bridge',
      content: {
        'bridgebot': _bot,
        'protocol': {'id': 'imessage', 'displayname': 'iMessage'},
        'com.beeper.room_type': ?roomType,
      },
      senderId: _bot,
      stateKey: 'imessage',
    ),
  );

  void functionalMembers(Room room, List<String> ids) => room.setState(
    StrippedStateEvent(
      type: RoomKind.functionalMembersType,
      content: {'service_members': ids},
      senderId: _bot,
      stateKey: '',
    ),
  );

  void markDirect(Room room, String partner) {
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        ...?client.accountData['m.direct']?.content,
        partner: [room.id],
      },
    );
  }

  /// A nameless bridged room with Gloria's ghost and the bridge bot joined,
  /// as the iMessage bridge leaves a direct chat.
  Room portal(String id) {
    final room = Room(id: id, client: client);
    member(room, _gloria, 'Gloria', avatar: 'mxc://x/gloria');
    member(room, _bot, 'iMessage bridge bot');
    room.summary
      ..mHeroes = [_gloria, _bot]
      ..mJoinedMemberCount = 3;
    client.rooms.add(room);
    return room;
  }

  group('a direct chat whose bridge bot stays joined', () {
    test('reads as one-to-one, named after the other person', () {
      final room = portal('!dm:x');
      bridge(room);
      markDirect(room, _gloria);
      expect(room.isOneToOne, isTrue);
      expect(room.isGroupChat, isFalse);
      expect(room.chatDisplayname(), 'Gloria');
      expect(TypingIndicatorRow.oneToOneFor([room]), isTrue);
    });

    test('leaves a functional member out without bridge state', () {
      final room = portal('!dm:x');
      functionalMembers(room, [_bot]);
      markDirect(room, _gloria);
      expect(room.serviceMembers, {_bot});
      expect(room.otherPeopleCount, 1);
      expect(room.chatDisplayname(), 'Gloria');
    });

    test('the bot is never typing', () {
      final room = portal('!dm:x');
      functionalMembers(room, [_bot]);
      markDirect(room, _gloria);
      room.ephemerals['m.typing'] = BasicEvent(
        type: 'm.typing',
        content: {
          'user_ids': [_bot, _gloria],
        },
      );
      expect(typingUsersIn([room]).map((u) => u.id), [_gloria]);
    });
  });

  group('the bridge room type decides', () {
    test('a dm missing from m.direct is one-to-one, with her picture', () {
      final room = portal('!dm:x');
      bridge(room, roomType: 'dm');
      expect(room.isDirectChat, isFalse);
      expect(room.isOneToOne, isTrue);
      expect(room.chatDisplayname(), 'Gloria');
      expect(room.chatAvatar, Uri.parse('mxc://x/gloria'));
    });

    test('a group listed in m.direct is a group', () {
      final room = portal('!group:x');
      bridge(room, roomType: 'group');
      markDirect(room, _gloria);
      expect(room.isOneToOne, isFalse);
      expect(room.isGroupChat, isTrue);
      expect(room.isMergeableOneToOne, isFalse);
    });
  });

  test('a room in m.direct with two other people is never mergeable', () {
    final room = portal('!group:x');
    functionalMembers(room, [_bot]);
    member(room, '@imessage_tel=3a+13125550199:x', 'Ana');
    room.summary
      ..mHeroes = [_gloria, '@imessage_tel=3a+13125550199:x', _bot]
      ..mJoinedMemberCount = 4;
    markDirect(room, _gloria);
    expect(room.otherPeopleCount, 2);
    expect(room.isMergeableOneToOne, isFalse);
  });

  test('a direct chat with its bot is mergeable', () {
    final room = portal('!dm:x');
    functionalMembers(room, [_bot]);
    markDirect(room, _gloria);
    expect(room.isMergeableOneToOne, isTrue);
  });

  test('a plain direct chat is unchanged', () {
    final room = Room(id: '!bob:x', client: client);
    member(room, '@bob:x', 'Bob');
    room.summary
      ..mHeroes = ['@bob:x']
      ..mJoinedMemberCount = 2;
    client.rooms.add(room);
    markDirect(room, '@bob:x');
    expect(room.isOneToOne, isTrue);
    expect(room.chatDisplayname(), room.getLocalizedDisplayname());
  });
}
