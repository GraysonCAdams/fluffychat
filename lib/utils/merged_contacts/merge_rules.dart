// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/contact_identifiers.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:matrix/matrix.dart';

/// Tells whether a chat may be merged into the conversation made of
/// [current] (one room, or the rooms of a merged contact).
///
/// A one-to-one conversation takes one-to-one chats whose other person has
/// the same phone number; a shared name alone does not count. A group
/// conversation takes group chats with the same name. Either way the chat
/// must be joined and on a network the conversation does not span yet,
/// since a merged conversation holds one room per network.
///
/// [spaces] is [spacesByChild] of [client], for callers that already have it.
bool Function(Room room) mergeCandidateTest(
  Client client,
  List<Room> current, {
  Map<String, Room>? spaces,
}) {
  if (current.isEmpty) return (_) => false;
  final spaceOf = spaces ?? spacesByChild(client);
  final currentIds = {for (final room in current) room.id};
  final networks = {for (final room in current) spaceOf[room.id]?.id};
  final isGroup = current.first.isGroupChat;

  String? Function(Room room) keyOf;
  if (isGroup) {
    keyOf = (room) {
      final name = normalizeName(room.chatDisplayname());
      return name.isEmpty ? null : name;
    };
  } else {
    final service = MergeSuggestionService.forClient(client);
    keyOf = (room) => service.phoneOf(room)?.value;
  }
  final keys = {for (final room in current) ?keyOf(room)};
  if (keys.isEmpty) return (_) => false;

  return (room) =>
      room.membership == Membership.join &&
      room.isGroupChat == isGroup &&
      !currentIds.contains(room.id) &&
      spaceOf[room.id] != null &&
      !networks.contains(spaceOf[room.id]!.id) &&
      keys.contains(keyOf(room));
}

/// The chats of [client] that may be merged into the conversation made of
/// [current], by the rules of [mergeCandidateTest].
List<Room> mergeCandidates(Client client, List<Room> current) {
  final accepts = mergeCandidateTest(client, current);
  return [
    for (final room in client.rooms)
      if (accepts(room)) room,
  ];
}

/// Whether the chats in [chats] can be merged into one conversation. Each
/// entry is the rooms of one chat: a single room, or every room of a merged
/// contact.
///
/// The first merged contact among them, else the first chat, is the
/// conversation the others join, and each further room must pass
/// [mergeCandidateTest] against everything taken in before it. So the rules
/// are those of adding chats to a conversation one by one: one-to-one chats
/// with the same phone number or groups with the same name, never both
/// kinds, and no two rooms on the same network.
bool canMergeTogether(Client client, List<List<Room>> chats) {
  if (chats.length < 2) return false;
  final anchor = mergeAnchor(chats);
  if (anchor.length == 1 &&
      (anchor.single.membership != Membership.join || anchor.single.isSpace)) {
    return false;
  }
  final spaces = spacesByChild(client);
  final merged = List.of(anchor);
  for (final chat in chats) {
    if (identical(chat, anchor)) continue;
    for (final room in chat) {
      if (!mergeCandidateTest(client, merged, spaces: spaces)(room)) {
        return false;
      }
      merged.add(room);
    }
  }
  return true;
}

/// The chat of [chats] the others are merged into by [canMergeTogether]:
/// the first with more than one room (a merged contact), else the first.
List<Room> mergeAnchor(List<List<Room>> chats) =>
    chats.firstWhere((chat) => chat.length > 1, orElse: () => chats.first);
