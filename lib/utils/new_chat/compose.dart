// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The compose screen's lookups: the chat the user already has with the
/// people in the To field, so it shows above the composer and the first
/// message goes there.
library;

import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/add_people.dart' as add_people;
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:matrix/matrix.dart';

/// Whether [person] is someone only Matrix reaches: a user from the
/// directory or a typed Matrix ID, with no number, email or network.
bool isMatrixOnlyPerson(NewChatPerson person) =>
    person.chat == null &&
    person.userIds.isNotEmpty &&
    person.phones.isEmpty &&
    person.emails.isEmpty &&
    person.bridgeUsers.isEmpty &&
    person.networks.isEmpty;

/// The direct chat the user already has with [person], newest first as the
/// chat list orders them, a merged contact as one chat: the chat the search
/// found for them, else a direct room a bridge named for them, one with any
/// of their Matrix IDs or ghosts, or one whose number is theirs. Null when
/// there is none, or when [person] is a group chat.
ExistingChat? existingDirectChatOf(Client client, NewChatPerson person) {
  if (person.group) return null;
  final found = person.chat;
  if (found is ExistingChat) return found;
  final userIds = {
    ...person.userIds,
    for (final user in person.bridgeUsers.values) ?user.mxid,
  };
  final roomIds = {
    for (final user in person.bridgeUsers.values) ?user.dmRoomId,
  };
  final chats = existingChatsOf(
    client,
    client.rooms
        .where((room) => room.membership == Membership.join && !room.isSpace)
        .toList(),
    (room) => room.directChatMatrixID != null,
  );
  bool matches(ExistingChat chat) {
    final rooms = chat.contact?.rooms ?? [chat.room];
    return rooms.any(
      (room) =>
          roomIds.contains(room.id) ||
          userIds.contains(room.directChatMatrixID),
    );
  }

  final byId = chats.where(matches).firstOrNull;
  if (byId != null) return byId;
  if (person.phones.isEmpty) return null;
  return chats
      .where((chat) => person.phones.contains(phoneOfChat(chat)))
      .firstOrNull;
}

/// The Matrix IDs of [room]'s people besides the user and [bridge]'s bot,
/// joined or invited, from its member events and its summary's heroes.
/// Null when the summary counts more members than those and the user and
/// bot, so the list is known to be incomplete.
Set<String>? _othersOf(Room room, BridgeInfo bridge) {
  final own = room.client.userID;
  final others = {
    for (final user in room.getParticipants([
      Membership.join,
      Membership.invite,
    ]))
      user.id,
    ...?room.summary.mHeroes,
  }..removeWhere((id) => id == own || id == bridge.bridgeBot);
  final counted =
      (room.summary.mJoinedMemberCount ?? 0) +
      (room.summary.mInvitedMemberCount ?? 0);
  if (counted > others.length + 2) return null;
  return others;
}

/// The most recent group on [bridge] whose people are exactly [members]:
/// one of [bridges]' portals that is not a direct chat, whose other members
/// besides the user and the bridge bot are the members' ghosts. Null when
/// there is none, or when a member's ghost is not known.
Room? existingGroupOf(
  Client client,
  List<BridgeInfo> bridges,
  BridgeInfo bridge,
  List<GroupMember> members,
) {
  final wanted = <String>{};
  for (final member in members) {
    final ghost =
        member.user.mxid ?? member.person.bridgeUsers[bridge.name]?.mxid;
    if (ghost == null) return null;
    wanted.add(ghost);
  }
  final matches = client.rooms.where((room) {
    if (room.membership != Membership.join ||
        room.isSpace ||
        room.directChatMatrixID != null) {
      return false;
    }
    if (add_people.bridgeOfRoom(bridges, room)?.name != bridge.name) {
      return false;
    }
    final others = _othersOf(room, bridge);
    return others != null &&
        others.length == wanted.length &&
        others.containsAll(wanted);
  }).toList();
  if (matches.isEmpty) return null;
  matches.sort(
    (a, b) => b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
  );
  return matches.first;
}
