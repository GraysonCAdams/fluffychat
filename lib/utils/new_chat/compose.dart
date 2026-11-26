// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The compose screen's lookups: the networks that reach the people in the
/// To field, and the chat the user already has with them, so it shows above
/// the composer and the first message goes there.
library;

import 'dart:ui';

import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
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

/// What the user's networks answered about one person in the compose
/// screen's To field, by bridge name.
class PersonReach {
  /// The person on each network that answered: as it knows them, or null
  /// when it does not reach them. A network still being asked, or one that
  /// failed to answer, has no entry.
  final Map<String, BridgeUser?> users = {};

  /// Why each network that failed to answer did.
  final Map<String, String> errors = {};

  /// What each network was asked about the person, which a new direct chat
  /// there starts with.
  final Map<String, String> identifiers = {};

  final Map<String, Future<void>> _asking = {};

  /// Whether [bridge] answered, failed to, or is being asked.
  bool handled(String bridge) =>
      users.containsKey(bridge) ||
      errors.containsKey(bridge) ||
      _asking.containsKey(bridge);

  /// Whether any network is still being asked.
  bool get asking => _asking.isNotEmpty;

  /// Asks [bridge] about the person with [resolve] and records the answer,
  /// or the reason when it fails. A bridge that rejects the identifier
  /// itself counts as one that does not reach them. Completes either way.
  Future<void> ask(String bridge, Future<BridgeUser?> Function() resolve) {
    errors.remove(bridge);
    final future = () async {
      try {
        users[bridge] = await resolve();
      } catch (e, s) {
        Logs().w('$bridge could not resolve a person in the To field', e, s);
        // A bridge that cannot take this kind of identifier does not reach
        // the person; anything else is a failure to answer.
        if (bridgeRejectsIdentifier(e)) {
          users[bridge] = null;
        } else {
          errors[bridge] = bridgeErrorReason(e);
        }
      }
    }();
    _asking[bridge] = future;
    future.whenComplete(() => _asking.remove(bridge));
    return future;
  }

  /// Completes once no network is being asked.
  Future<void> settled() => Future.wait(_asking.values.toList());
}

/// A network the first person in the compose screen's To field is on, as
/// its network switcher offers it: the direct chat the user has with them
/// there ([room]), or a bridge that reaches them with no chat yet.
class ComposeNetwork {
  /// The user's bridge for the network; null for a chat on none of them,
  /// such as one with a Matrix user.
  final BridgeInfo? bridge;
  final Room? room;

  /// The person as [bridge] knows them, once it answered.
  final BridgeUser? user;

  /// The bridge space the network's chats are in.
  final Room? space;
  final String name;
  final Uri? avatar;

  const ComposeNetwork({
    required this.bridge,
    required this.room,
    required this.user,
    required this.space,
    required this.name,
    required this.avatar,
  });

  String get id => room?.id ?? 'bridge:${bridge?.name}';

  /// Whether the network is one of the user's networks rather than plain
  /// Matrix, so the composer names it.
  bool get isNetwork => bridge != null || space != null;

  /// The network's bubble colour, which the send button takes as in a
  /// merged chat.
  Color? get color => NetworkColors.colorFor(
    room == null ? bridge?.networkId : NetworkColors.bridgeIdOf(room!),
  );
}

/// The space [bridge] puts its chats in: the one its `whoami` names, else
/// the space of any of its chats. Null when there is none.
Room? bridgeSpace(Client client, BridgeInfo bridge) {
  final spaceId = bridge.spaceRoomId;
  final named = spaceId == null ? null : client.getRoomById(spaceId);
  if (named != null) return named;
  final spaces = spacesByChild(client);
  for (final room in client.rooms) {
    if (room.isSpace) continue;
    final space = spaces[room.id];
    if (space == null) continue;
    if (add_people.bridgeOfRoom([bridge], room) != null) return space;
  }
  return null;
}

/// The logo of [bridge]'s network: its space's avatar, as the network
/// switcher shows it, else the bridge's own icon.
Uri? bridgeLogo(Client client, BridgeInfo bridge) =>
    bridgeSpace(client, bridge)?.avatar ?? bridge.icon;

/// The rooms of [chat]: every room of a merged contact, newest first, else
/// the chat's room.
List<Room> _roomsOf(ExistingChat? chat) {
  if (chat == null) return const [];
  final contact = chat.contact;
  if (contact == null) return [chat.room];
  return [...contact.rooms]..sort(
    (a, b) => b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
  );
}

/// The other person's ghost in [chat]'s room on [bridge], which that bridge
/// can be asked about when nothing else identifies the person. Null when
/// [chat] has no room there.
String? ghostOnBridge(
  List<BridgeInfo> bridges,
  ExistingChat? chat,
  BridgeInfo bridge,
) => _roomsOf(chat)
    .where(
      (room) => add_people.bridgeOfRoom(bridges, room)?.name == bridge.name,
    )
    .firstOrNull
    ?.directChatMatrixID;

/// The networks of [chat] and [reach] for the compose screen's network
/// switcher: one per bridge with a room of [chat] on it or that answered it
/// reaches the person, in the order of [orderBridgesForSwitcher], then each
/// room of [chat] on none of [bridges]. A network's room is [chat]'s room
/// there, else the direct chat its bridge names for the person.
List<ComposeNetwork> composeNetworksOf(
  Client client,
  List<BridgeInfo> bridges,
  ExistingChat? chat,
  PersonReach reach,
  MatrixLocalizations locals,
) {
  final spaces = spacesByChild(client);
  final rooms = _roomsOf(chat);
  final placed = <String>{};
  final networks = <ComposeNetwork>[];
  for (final bridge in orderBridgesForSwitcher(bridges)) {
    final user = reach.users[bridge.name];
    final dmRoomId = user?.dmRoomId;
    final dmRoom = dmRoomId == null ? null : client.getRoomById(dmRoomId);
    // A chat the bridge names for the person counts too, merged or not.
    final room =
        rooms
            .where(
              (room) =>
                  add_people.bridgeOfRoom(bridges, room)?.name == bridge.name,
            )
            .firstOrNull ??
        (dmRoom?.membership == Membership.join ? dmRoom : null);
    if (room == null && user == null) continue;
    if (room != null) placed.add(room.id);
    final space = room != null ? spaces[room.id] : bridgeSpace(client, bridge);
    networks.add(
      ComposeNetwork(
        bridge: bridge,
        room: room,
        user: user,
        space: space,
        name: space?.getLocalizedDisplayname(locals) ?? bridge.displayName,
        avatar: space?.avatar ?? bridge.icon,
      ),
    );
  }
  for (final room in rooms) {
    if (placed.contains(room.id)) continue;
    final space = spaces[room.id];
    networks.add(
      ComposeNetwork(
        bridge: null,
        room: room,
        user: null,
        space: space,
        name: networkName(room, space, locals),
        avatar: space?.avatar,
      ),
    );
  }
  return networks;
}

/// The network a conversation with the first person starts on: the one
/// whose chat had the last message, else the first of [networks].
ComposeNetwork? defaultComposeNetwork(List<ComposeNetwork> networks) {
  final withRooms = networks.where((network) => network.room != null).toList()
    ..sort(
      (a, b) => b.room!.latestEventReceivedTime.compareTo(
        a.room!.latestEventReceivedTime,
      ),
    );
  return withRooms.firstOrNull ?? networks.firstOrNull;
}
