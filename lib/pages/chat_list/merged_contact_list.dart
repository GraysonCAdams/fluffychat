// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:matrix/matrix.dart';

/// The chats the chat list shows, with every merged contact collapsed into
/// one entry.
///
/// A contact is represented by the first of its rooms in [rooms] order. The
/// SDK sorts pinned rooms first and the rest newest first, so the contact
/// lands where its newest (or pinned) room would be. The contact is listed
/// when any of its rooms passes [keep]: a contact matches a filter, such as
/// unread or a source space, when any of its rooms does.
class MergedChatList {
  /// The chats to list, in order. A merged contact appears once, as its
  /// representative room.
  final List<Room> rooms;

  /// The resolved contact of each representative room in [rooms], by room
  /// ID. Rooms not in a contact are absent.
  final Map<String, MergedContact> contacts;

  const MergedChatList(this.rooms, this.contacts);

  static MergedChatList build(
    Client client,
    List<Room> rooms,
    bool Function(Room room) keep,
  ) {
    final store = MergedContactsStore.forClient(client);
    if (store.isEmpty) {
      return MergedChatList(rooms.where(keep).toList(), const {});
    }
    // Client.getRoomById walks every room, so the member lookups below use
    // one map built per pass instead.
    final byId = {for (final room in rooms) room.id: room};
    final seen = <String>{};
    final listed = <Room>[];
    final contacts = <String, MergedContact>{};
    for (final room in rooms) {
      final entry = store.contactForRoom(room.id);
      if (entry == null) {
        if (keep(room)) listed.add(room);
        continue;
      }
      if (!seen.add(entry.id)) continue;
      final members = [for (final id in entry.rooms) ?byId[id]];
      final contact = MergedContact.fromRooms(entry, members);
      if (contact == null) {
        if (keep(room)) listed.add(room);
        continue;
      }
      if (!members.any(keep)) continue;
      listed.add(room);
      contacts[room.id] = contact;
    }
    return MergedChatList(listed, contacts);
  }
}

extension MergedContactSearch on MergedContact {
  /// Whether a chat list search for [filter] (lower case) finds this
  /// contact: by its own name or the name of any of its rooms.
  bool matchesSearch(String filter, MatrixLocals locals) =>
      displayName(locals).toLowerCase().contains(filter) ||
      rooms.any(
        (room) =>
            room.getLocalizedDisplayname(locals).toLowerCase().contains(filter),
      );
}
