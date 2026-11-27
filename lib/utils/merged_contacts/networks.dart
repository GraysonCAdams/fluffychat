// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/room_kind.dart';
import 'package:matrix/matrix.dart';

/// The space each room is a child of, by room ID. A bridge puts all of its
/// chats in one space of its own, so for bridged chats this is the network
/// (iMessage, SMS, Telegram). The chat list computes the same map for its
/// corner badges.
Map<String, Room> spacesByChild(Client client) {
  final spaces = <String, Room>{};
  for (final space in client.rooms) {
    if (!space.isSpace) continue;
    for (final child in space.spaceChildren) {
      final roomId = child.roomId;
      if (roomId != null) spaces[roomId] = space;
    }
  }
  return spaces;
}

/// A short name for the network [room] is on: its space's name, else a name
/// guessed from the other person's bridge user ID (`@imessage_...` gives
/// "Imessage"), else the other person's server.
String networkName(
  Room room,
  Room? space, [
  MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
]) {
  if (space != null) return space.chatDisplayname(i18n);
  final partner = room.directChatMatrixID;
  final localpart = partner?.localpart;
  if (localpart != null) {
    final underscore = localpart.indexOf('_');
    if (underscore > 0) {
      final prefix = localpart.substring(0, underscore);
      return prefix[0].toUpperCase() + prefix.substring(1);
    }
  }
  return partner?.domain ?? room.client.homeserver?.host ?? room.id;
}
