// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat_list/push_rule_state_cache.dart';
import 'package:fluffychat/utils/room_unread.dart';
import 'package:matrix/matrix.dart';

import 'model.dart';
import 'store.dart';

/// A merged contact with its rooms resolved: everything the chat list and
/// the chat screen show about it, derived from the rooms on each read and
/// never stored.
///
/// Cheap to build (a pass over two or three rooms), so it is made fresh
/// wherever it is needed instead of being cached and going stale.
class MergedContact {
  final MergedContactEntry entry;

  /// The member rooms that exist on this client, in the stored order.
  final List<Room> rooms;

  const MergedContact._(this.entry, this.rooms);

  /// Resolves [entry] on [client]; null when fewer than two of its rooms
  /// are known to the client.
  static MergedContact? resolve(Client client, MergedContactEntry entry) {
    final rooms = [for (final id in entry.rooms) ?client.getRoomById(id)];
    if (rooms.length < 2) return null;
    return MergedContact._(entry, rooms);
  }

  /// A contact from rooms the caller already looked up, in [entry] order.
  static MergedContact? fromRooms(MergedContactEntry entry, List<Room> rooms) =>
      rooms.length < 2 ? null : MergedContact._(entry, rooms);

  /// The contact [roomId] belongs to on [client], resolved.
  static MergedContact? ofRoom(Client client, String roomId) {
    final entry = MergedContactsStore.forClient(client).contactForRoom(roomId);
    return entry == null ? null : resolve(client, entry);
  }

  String get id => entry.id;

  /// The room a new message goes to unless the user picks another.
  Room get sendViaRoom {
    final sendVia = entry.sendViaIn([for (final room in rooms) room.id]);
    return rooms.firstWhere((room) => room.id == sendVia);
  }

  Room? roomById(String roomId) {
    for (final room in rooms) {
      if (room.id == roomId) return room;
    }
    return null;
  }

  /// The name the user gave the contact, else the `send_via` room's name.
  String displayName([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) => entry.name ?? sendViaRoom.getLocalizedDisplayname(i18n);

  Uri? get avatar => sendViaRoom.avatar;

  /// The newest last event across the rooms.
  Event? get lastEvent {
    Event? newest;
    for (final room in rooms) {
      final event = room.lastEvent;
      if (event == null) continue;
      if (newest == null ||
          event.originServerTs.isAfter(newest.originServerTs)) {
        newest = event;
      }
    }
    return newest;
  }

  /// The room whose newest event the other person sent most recently, for
  /// the `last_received` send mode. Null when they never wrote.
  Room? get lastReceivedRoom {
    Room? best;
    DateTime? bestTime;
    final ownId = rooms.first.client.userID;
    for (final room in rooms) {
      final event = room.lastEvent;
      if (event == null || event.senderId == ownId) continue;
      if (bestTime == null || event.originServerTs.isAfter(bestTime)) {
        best = room;
        bestTime = event.originServerTs;
      }
    }
    return best;
  }

  DateTime get latestEventReceivedTime => rooms
      .map((room) => room.latestEventReceivedTime)
      .reduce((a, b) => a.isAfter(b) ? a : b);

  int get notificationCount =>
      rooms.fold(0, (sum, room) => sum + room.notificationCount);

  int get highlightCount =>
      rooms.fold(0, (sum, room) => sum + room.highlightCount);

  bool get isUnread => rooms.any((room) => room.countsAsUnread);

  bool get hasNewMessages => rooms.any((room) => room.hasNewMessages);

  bool get markedUnread => rooms.any((room) => room.markedUnread);

  /// Muted only when every room is, since any unmuted room still notifies.
  bool get isMuted =>
      rooms.every((room) => room.cachedPushRuleState != PushRuleState.notify);

  /// Pinned when any room is, so pinning one room before merging keeps the
  /// contact in the pinned row.
  bool get isFavourite => rooms.any((room) => room.isFavourite);

  bool get isLowPriority => rooms.every((room) => room.isLowPriority);

  /// The network of each room: the space it is a child of, which for a
  /// bridge is the bridge's own space. [spaceOf] maps room ID to that space,
  /// as the chat list already computes it.
  List<Room?> networks(Map<String, Room> spaceOf) => [
    for (final room in rooms) spaceOf[room.id],
  ];

  /// Whether the rooms are on more than one network. A contact the app made
  /// for same-people groups is on one bridge, so the chat list badges it
  /// as that network rather than as a merged contact.
  bool get spansNetworks => !entry.automatic;

  /// The ID of every member room, for checks like "is this chat open".
  Iterable<String> get roomIds => rooms.map((room) => room.id);
}
