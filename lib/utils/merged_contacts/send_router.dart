// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'model.dart';

/// Everything the chat screen can send, grouped by how its room is chosen.
enum SendAction {
  // Something new. Goes to the composer's target network.
  message,
  attachment,
  voiceMessage,
  sticker,
  location,
  poll,
  typing,

  // Something that acts on an existing message. Goes to that message's
  // room, whatever the target network is.
  reply,
  threadReply,
  reaction,
  edit,
  redaction,
  pin,

  // A read receipt marks a message as read in the room it is in.
  readReceipt;

  /// Whether this action belongs to an existing message and must go to that
  /// message's room.
  bool get actsOnEvent => switch (this) {
    reply || threadReply || reaction || edit || redaction || pin => true,
    readReceipt => true,
    message || attachment || voiceMessage || sticker || location => false,
    poll || typing => false,
  };
}

/// Where the composer sends and whether the user may change it.
class SendTarget {
  final String roomId;

  /// True while replying, editing or in a thread: the message answers an
  /// existing one, so it goes to that message's room and the send-via button
  /// cannot switch it.
  final bool locked;

  const SendTarget(this.roomId, {this.locked = false});

  @override
  bool operator ==(Object other) =>
      other is SendTarget && other.roomId == roomId && other.locked == locked;

  @override
  int get hashCode => Object.hash(roomId, locked);

  @override
  String toString() => 'SendTarget($roomId, locked: $locked)';
}

/// Decides which room of a merged contact everything goes to. Every send in
/// the chat screen asks this one class, so the rule that a reply, reaction,
/// edit, redaction or thread reply stays on the network of the message it
/// belongs to cannot be skipped by one call site.
///
/// Works on room IDs only, so it is unit tested without a client.
class SendRouter {
  /// The rooms new messages can go to, in the contact's order. A chat that
  /// is not merged has just its own room.
  final List<String> roomIds;

  /// The contact's default network.
  final String sendVia;

  final SendMode sendMode;

  /// The room of the newest message the other person sent, for
  /// [SendMode.lastReceived]. Null when they never wrote.
  final String? lastReceivedRoomId;

  /// A network the user picked on the send-via button for the next message
  /// only. Cleared after that message is sent.
  final String? oneOffRoomId;

  SendRouter({
    required this.roomIds,
    required this.sendVia,
    this.sendMode = SendMode.preferred,
    this.lastReceivedRoomId,
    this.oneOffRoomId,
  }) : assert(roomIds.isNotEmpty);

  /// A chat that is not merged, or one room of a contact shown on its own:
  /// everything new goes to [roomId].
  factory SendRouter.single(String roomId) =>
      SendRouter(roomIds: [roomId], sendVia: roomId);

  /// A merged contact's router.
  factory SendRouter.contact(
    MergedContactEntry contact, {
    String? lastReceivedRoomId,
    String? oneOffRoomId,
  }) => SendRouter(
    roomIds: contact.rooms,
    sendVia: contact.sendViaIn(contact.rooms)!,
    sendMode: contact.sendMode,
    lastReceivedRoomId: lastReceivedRoomId,
    oneOffRoomId: oneOffRoomId,
  );

  bool get isMerged => roomIds.length > 1;

  /// The room a message that starts something new goes to:
  /// 1. a one-off pick from the send-via button,
  /// 2. in [SendMode.lastReceived], the room they last wrote from,
  /// 3. the contact's `send_via` room.
  String get newMessageRoomId {
    final oneOff = oneOffRoomId;
    if (oneOff != null && roomIds.contains(oneOff)) return oneOff;
    final lastReceived = lastReceivedRoomId;
    if (sendMode == SendMode.lastReceived &&
        lastReceived != null &&
        roomIds.contains(lastReceived)) {
      return lastReceived;
    }
    return roomIds.contains(sendVia) ? sendVia : roomIds.first;
  }

  /// The room [action] goes to. An action on an existing message needs the
  /// room that message is in as [eventRoomId], and always goes there.
  String route(SendAction action, {String? eventRoomId}) {
    if (action.actsOnEvent) {
      if (eventRoomId == null) {
        throw ArgumentError.value(
          eventRoomId,
          'eventRoomId',
          '$action acts on an existing message and needs its room',
        );
      }
      return eventRoomId;
    }
    return newMessageRoomId;
  }

  /// Where the composer's send button goes. Editing, replying and writing
  /// in a thread all answer an existing message, so the message goes to
  /// that message's room and the target is locked; otherwise it is
  /// [newMessageRoomId].
  SendTarget composerTarget({
    String? editRoomId,
    String? replyRoomId,
    String? threadRoomId,
  }) {
    if (editRoomId != null) {
      return SendTarget(
        route(SendAction.edit, eventRoomId: editRoomId),
        locked: true,
      );
    }
    if (replyRoomId != null) {
      return SendTarget(
        route(SendAction.reply, eventRoomId: replyRoomId),
        locked: true,
      );
    }
    if (threadRoomId != null) {
      return SendTarget(
        route(SendAction.threadReply, eventRoomId: threadRoomId),
        locked: true,
      );
    }
    return SendTarget(newMessageRoomId);
  }

  /// Whether a message with [content] starts something new, rather than
  /// replying to, editing or threading under another message. Only such a
  /// message may move to another network.
  static bool startsSomethingNew(Map<String, Object?> content) =>
      content['m.relates_to'] == null && content['m.new_content'] == null;

  /// Where a message that failed to send in [failedRoomId] can be offered
  /// again, or null for no offer. Only with the contact's fallback turned on
  /// ([enabled]) and only for a message that starts something new: an
  /// answer to a message belongs to that message's network, so it is never
  /// moved. Never automatic, since a silent move to SMS could leak a message
  /// meant for an encrypted network.
  String? fallbackRoomFor({
    required String failedRoomId,
    required Map<String, Object?> content,
    required bool enabled,
  }) {
    if (!enabled || !isMerged || !startsSomethingNew(content)) return null;
    return nextRoomAfter(failedRoomId);
  }

  /// The next room after [roomId] in the contact's order, for offering to
  /// resend a failed message through another network. Null when there is
  /// no other room.
  String? nextRoomAfter(String roomId) {
    if (roomIds.length < 2) return null;
    final index = roomIds.indexOf(roomId);
    return roomIds[(index + 1) % roomIds.length];
  }

  SendRouter copyWith({String? Function()? oneOffRoomId}) => SendRouter(
    roomIds: roomIds,
    sendVia: sendVia,
    sendMode: sendMode,
    lastReceivedRoomId: lastReceivedRoomId,
    oneOffRoomId: oneOffRoomId == null ? this.oneOffRoomId : oneOffRoomId(),
  );
}
