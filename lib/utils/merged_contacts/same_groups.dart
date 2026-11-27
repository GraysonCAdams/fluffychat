// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Group chats on one bridge with exactly the same people, which the chat
/// list shows as one conversation. A network can keep several threads with
/// the same people (iMessage does), and its bridge makes a room for each.
library;

import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:matrix/matrix.dart';

/// Group rooms on one bridge whose people are the same.
class SameGroup {
  /// The rooms, most recently active first.
  final List<Room> rooms;

  /// The group's name: the newest room's name that the bridge did not
  /// build from the members (see [groupNameIsBuilt]), else the newest
  /// built name other than the [legacyBuiltGroupName]. Null when there is
  /// neither.
  final String? name;

  const SameGroup(this.rooms, this.name);

  List<String> get roomIds => [for (final room in rooms) room.id];
}

/// The groups of [client]'s joined group chats that share a bridge and the
/// same people: their members besides the user and the bridge bot, joined
/// or invited. Rooms on no bridge, or whose member list is not all in
/// memory, are left out; [onIncomplete] is called with each of the latter
/// so its members can be loaded.
List<SameGroup> findSameGroups(
  Client client, {
  void Function(Room room)? onIncomplete,
}) {
  final features = MatrixFeatures.forClient(client);
  Map<String, Room>? spaces;
  final byKey = <String, List<Room>>{};
  for (final room in client.rooms) {
    if (room.membership != Membership.join ||
        room.isSpace ||
        room.isDirectChat) {
      continue;
    }
    final bot = features.bridgeOf(room)?.bot;
    final bridge = bot ?? (spaces ??= spacesByChild(client))[room.id]?.id;
    if (bridge == null) continue;
    final people = groupPeopleOf(room, bot);
    if (people == null) {
      onIncomplete?.call(room);
      continue;
    }
    if (people.isEmpty) continue;
    final key = '$bridge\n${(people.toList()..sort()).join('\n')}';
    (byKey[key] ??= []).add(room);
  }
  return [
    for (final rooms in byKey.values)
      if (rooms.length >= 2) _sameGroup(rooms),
  ];
}

SameGroup _sameGroup(List<Room> rooms) {
  rooms.sort(
    (a, b) => b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
  );
  String? given;
  String? built;
  for (final room in rooms) {
    if (!groupNameIsBuilt(room)) {
      given = room.getLocalizedDisplayname();
      break;
    }
    final name = room.getState(EventTypes.RoomName)?.content['name'];
    if (built == null &&
        name is String &&
        name.trim() != legacyBuiltGroupName) {
      built = room.getLocalizedDisplayname();
    }
  }
  return SameGroup(rooms, given ?? built);
}

/// The people of [room] besides the user and the bridge [bot], joined or
/// invited; null when the room counts more members than are in memory.
Set<String>? groupPeopleOf(Room room, String? bot) {
  final own = room.client.userID;
  final members = {
    for (final user in room.getParticipants([
      Membership.join,
      Membership.invite,
    ]))
      user.id,
  };
  final counted =
      (room.summary.mJoinedMemberCount ?? 0) +
      (room.summary.mInvitedMemberCount ?? 0);
  if (counted > members.length) return null;
  return members..removeWhere((id) => id == own || id == bot);
}

/// The state event a bridge may set to say whether it built a group's name
/// from the members.
const groupNameStateType = 'dev.macoun.group_name';

/// The name the iMessage bridge gave groups without a name before it built
/// one from the members.
const legacyBuiltGroupName = 'Group Chat';

/// Whether [room]'s name was built by its bridge from the members rather
/// than given to the group on its network. The bridge's
/// [groupNameStateType] event decides when there is one. Otherwise a room
/// with no name, the [legacyBuiltGroupName], or a name made as the
/// iMessage bridge makes one counts as built: the other members' names
/// joined with ", " for four or fewer, and "A, B, C +N more" for five or
/// more, where N is the members past the third. The members may be listed
/// in any order.
bool groupNameIsBuilt(Room room) {
  final marker = room.getState(groupNameStateType)?.content['generated'];
  if (marker is bool) return marker;
  final name = room.getState(EventTypes.RoomName)?.content['name'];
  if (name is! String || name.trim().isEmpty) return true;
  if (name.trim() == legacyBuiltGroupName) return true;
  final bot = MatrixFeatures.forClient(room.client).bridgeOf(room)?.bot;
  final people = groupPeopleOf(room, bot);
  if (people == null || people.isEmpty) return false;
  final names = {
    for (final id in people)
      room
              .getState(EventTypes.RoomMember, id)
              ?.asUser(room)
              .calcDisplayname() ??
          id.localpart ??
          id,
  };
  final more = RegExp(r'^(.*) \+(\d+) more$').firstMatch(name);
  if (more != null) {
    final shown = more.group(1)!.split(', ');
    return people.length >= 5 &&
        shown.length == 3 &&
        int.parse(more.group(2)!) == people.length - 3 &&
        shown.every(names.contains);
  }
  final shown = name.split(', ');
  return people.length <= 4 &&
      shown.length == people.length &&
      shown.toSet().length == names.length &&
      shown.every(names.contains);
}
