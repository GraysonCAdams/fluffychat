// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:matrix/matrix.dart';

/// Whether the user has read [event] in its room: the read marker or the
/// user's own receipt is on it, or the receipt came after it arrived (the
/// same timestamp comparison as [Room.hasNewMessages]).
bool isReadUpTo(Event event) {
  final room = event.room;
  final ownId = room.client.userID;
  if (event.senderId == ownId) return true;
  if (room.fullyRead == event.eventId) return true;
  if (event.receipts.any((receipt) => receipt.user.senderId == ownId)) {
    return true;
  }
  final readAt = room.receiptState.global.latestOwnReceipt?.ts ?? 0;
  return readAt >= event.originServerTs.millisecondsSinceEpoch;
}

/// Marks [event]'s room read up to [event] (`m.fully_read` and a read
/// receipt), after the user did something with the message that shows they
/// read it, such as copying it. In a merged contact that is the network room
/// the message came in, as [Event.room] is.
///
/// The marker only moves forward: an older message than the one already
/// read changes nothing. The room's newest message also clears a manual
/// unread mark. A message still being sent has no ID to mark yet.
Future<void> markReadUpTo(Event event) async {
  final room = event.room;
  if (room.membership != Membership.join) return;
  if (!event.eventId.isValidMatrixIdStrict()) return;
  final isNewest = event.eventId == room.lastEvent?.eventId;
  if (isNewest && room.markedUnread) await room.markUnread(false);
  // Nothing to mark in a read room. The newest message cannot be behind the
  // marker; an older one is marked only when it is unread itself.
  if (room.notificationCount == 0 && !room.hasNewMessages) return;
  if (!isNewest && isReadUpTo(event)) return;
  await room.setReadMarker(
    event.eventId,
    mRead: event.eventId,
    public: AppSettings.sendPublicReadReceipts.value,
  );
}
