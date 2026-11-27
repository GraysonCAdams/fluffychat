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

  const SameGroup(this.rooms);

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

SameGroup _sameGroup(List<Room> rooms) => SameGroup(
  rooms..sort(
    (a, b) => b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
  ),
);

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
/// in any order, and a name listing only some of them counts (see
/// [isBuiltGroupName]).
bool groupNameIsBuilt(Room room) {
  final marker = room.getState(groupNameStateType)?.content['generated'];
  if (marker is bool) return marker;
  final name = room.getState(EventTypes.RoomName)?.content['name'];
  if (name is! String || name.trim().isEmpty) return true;
  return isBuiltGroupName(name, room);
}

/// Whether [name] is one the bridge builds from [room]'s members, or the
/// [legacyBuiltGroupName], by the rules of [groupNameIsBuilt]. A name
/// listing only some of the members (two or more of them, or the three
/// before "+N more") counts too: it was built before someone joined, and
/// the bridge has not built it again yet. With [exact], only a name built
/// from the members as they are now counts.
bool isBuiltGroupName(String name, Room room, {bool exact = false}) {
  if (name.trim() == legacyBuiltGroupName) return !exact;
  final names = _memberNames(room);
  if (names == null || names.isEmpty) return false;
  final more = RegExp(r'^(.*) \+(\d+) more$').firstMatch(name);
  if (more != null) {
    final shown = more.group(1)!.split(', ');
    return shown.length == 3 &&
        shown.every(names.contains) &&
        (!exact ||
            names.length >= 5 && int.parse(more.group(2)!) == names.length - 3);
  }
  final shown = name.split(', ');
  if (shown.toSet().length != shown.length || !shown.every(names.contains)) {
    return false;
  }
  return exact
      ? names.length <= 4 && shown.length == names.length
      : shown.length == names.length || shown.length >= 2;
}

/// The display names of [room]'s people besides the user and its bridge
/// bot, or null when its member list is not all in memory.
Set<String>? _memberNames(Room room) {
  final bot = MatrixFeatures.forClient(room.client).bridgeOf(room)?.bot;
  final people = groupPeopleOf(room, bot);
  if (people == null) return null;
  return {
    for (final id in people)
      room
              .getState(EventTypes.RoomMember, id)
              ?.asUser(room)
              .calcDisplayname() ??
          id.localpart ??
          id,
  };
}

/// The name of a conversation of the group chats [rooms], as their members
/// and the group's network name it now, newest room first:
/// 1. a name given to the group on its network (see [groupNameIsBuilt]),
/// 2. else the name the bridge built for the newest room whose built name
///    still matches its members,
/// 3. else the members' names, as the bridge builds a name: joined with
///    ", " for four or fewer, "A, B, C +N more" for five or more,
/// 4. else the newest room's own display name.
String liveGroupName(
  List<Room> rooms, [
  MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
]) {
  final newest = [...rooms]
    ..sort(
      (a, b) => b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
    );
  for (final room in newest) {
    if (!groupNameIsBuilt(room)) return room.getLocalizedDisplayname(i18n);
  }
  for (final room in newest) {
    final name = room.getState(EventTypes.RoomName)?.content['name'];
    if (name is String && isBuiltGroupName(name, room, exact: true)) {
      return name;
    }
  }
  final latest = newest.first;
  final names = (_memberNames(latest)?.toList() ?? [])..sort();
  if (names.isEmpty) return latest.getLocalizedDisplayname(i18n);
  return names.length <= 4
      ? names.join(', ')
      : '${names.take(3).join(', ')} +${names.length - 3} more';
}
