// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/compose.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../../pages/chat_list/chat_list_fakes.dart';

const _gmessages = BridgeInfo(
  name: 'gmessages',
  networkId: 'gmessages',
  displayName: 'Google Messages',
  icon: null,
  loginId: 'login-gmessages',
  bridgeBot: '@gmessagesbot:x',
);

const _drewGhost = '@gmessages_4.46:x';
const _harrisonGhost = '@gmessages_4.19:x';

/// Which shapes of the Google Messages group with Drew and Harrison, and of
/// the bridge's answers about them, `existingGroupOf` finds. The group is
/// shaped as it is on the server: the user, the bridge bot and the two
/// ghosts, joined.
void main() {
  late FakeChatListClient client;

  setUp(() async => client = await setUpFakeChatList('existing group test'));
  tearDown(() => tearDownFakeChatList(client));

  void member(Room room, String id) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      content: {'membership': 'join'},
      senderId: id,
      stateKey: id,
    ),
  );

  /// The group. [membersLoaded] false leaves the member events out, as a
  /// lazily loaded room has them; [heroes] is what its summary names.
  Room addGroup({
    bool bridged = true,
    bool membersLoaded = true,
    List<String>? heroes,
  }) {
    final room = Room(
      id: '!ovAjpgouxhbpKiqago:x',
      client: client,
      summary: RoomSummary.fromJson({
        'm.joined_member_count': 4,
        'm.invited_member_count': 0,
        'm.heroes': ?heroes,
      }),
    );
    if (membersLoaded) {
      for (final id in [
        client.userID!,
        _gmessages.bridgeBot!,
        _drewGhost,
        _harrisonGhost,
      ]) {
        member(room, id);
      }
    }
    if (bridged) addFakeBridge(room, bot: _gmessages.bridgeBot!);
    client.rooms.add(room);
    return room;
  }

  GroupMember drew({String? ghost = _drewGhost}) => GroupMember(
    NewChatPerson('Drew Andersen'),
    BridgeUser(id: '4.46', mxid: ghost),
  );
  GroupMember harrison({String? ghost = _harrisonGhost}) => GroupMember(
    NewChatPerson('Harrison Young'),
    BridgeUser(id: '4.19', mxid: ghost),
  );

  Room? lookup(List<GroupMember> members) =>
      existingGroupOf(client, const [_gmessages], _gmessages, members);

  test('found when the bridge names both ghosts', () {
    final room = addGroup();
    expect(lookup([drew(), harrison()]), room);
  });

  test('candidate: a resolve answer without a ghost and no contact ghost', () {
    addGroup();
    expect(lookup([drew(ghost: null), harrison()]), isNull);
  });

  test('candidate: a resolve answer naming another ghost', () {
    addGroup();
    expect(
      lookup([drew(ghost: '@gmessages_+14045550146:x'), harrison()]),
      isNull,
    );
  });

  test('candidate: members not loaded and no heroes in the summary', () {
    addGroup(membersLoaded: false);
    expect(lookup([drew(), harrison()]), isNull);
  });

  test('members not loaded but named as heroes is still found', () {
    final room = addGroup(
      membersLoaded: false,
      heroes: [_drewGhost, _harrisonGhost],
    );
    expect(lookup([drew(), harrison()]), room);
  });

  test('candidate: no m.bridge and in no bridge space', () {
    addGroup(bridged: false);
    expect(lookup([drew(), harrison()]), isNull);
  });

  test('candidate: the group is listed in m.direct', () {
    final room = addGroup();
    client.accountData['m.direct'] = BasicEvent(
      type: 'm.direct',
      content: {
        _drewGhost: [room.id],
      },
    );
    expect(room.directChatMatrixID, isNotNull);
    expect(lookup([drew(), harrison()]), isNull);
  });

  test('the log line cuts phone numbers to their last two digits', () {
    expect(
      redactDigits('@imessage_+14045550101:x'),
      '@imessage_+#########01:x',
    );
    expect(redactDigits('@gmessages_4.46:x'), '@gmessages_4.46:x');
  });
}
