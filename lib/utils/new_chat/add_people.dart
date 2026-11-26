// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Adding people to a chat that exists: which entry a room offers, and
/// which of the user's bridges owns a bridged room.
library;

import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/room_features.dart';
import 'package:matrix/matrix.dart';

/// How the user adds someone to a room.
enum AddMembersEntry {
  /// The Matrix invite page, which searches the user directory.
  invite,

  /// The Add people page, which finds people on the room's own network and
  /// invites their bridge ghosts.
  addPeople,
}

/// The entry [room] offers for adding someone, or null when the user
/// cannot add anyone. A plain Matrix room offers [AddMembersEntry.invite]
/// when the user's power level allows invites. A bridged room offers
/// [AddMembersEntry.addPeople] when the power level allows invites and its
/// `com.beeper.room_features` say the network takes them.
AddMembersEntry? addMembersEntryOf(Room room) {
  if (!room.canInvite) return null;
  if (!MatrixFeatures.forClient(room.client).isBridged(room)) {
    return AddMembersEntry.invite;
  }
  return RoomFeatures.of(room).allowsMemberAction(MemberAction.invite)
      ? AddMembersEntry.addPeople
      : null;
}

/// The bridge among [bridges] that [room] is a portal of: the one whose
/// bot the room's `m.bridge` state names, else the one whose space holds
/// the room. Null when none matches, such as a bridge the user is not
/// logged in to.
BridgeInfo? bridgeOfRoom(List<BridgeInfo> bridges, Room room) {
  final bot = MatrixFeatures.forClient(room.client).bridgeOf(room)?.bot;
  if (bot != null) {
    final byBot = bridges.where((bridge) => bridge.bridgeBot == bot);
    if (byBot.isNotEmpty) return byBot.first;
  }
  final space = spacesByChild(room.client)[room.id]?.id;
  if (space == null) return null;
  return bridges.where((bridge) => bridge.spaceRoomId == space).firstOrNull;
}
