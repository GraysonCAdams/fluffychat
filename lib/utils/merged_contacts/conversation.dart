// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

import 'store.dart';

/// The value that stands for a merged contact's screen wherever the app
/// keeps "the chat that is open" as a string, such as the chat list's active
/// chat and the notification code's active room. It cannot clash with a
/// room ID, which starts with "!".
String mergedContactActiveChat(String contactId) => 'contact:$contactId';

/// The active chat for the route [path]: a room ID, or for a merged
/// contact's screen [mergedContactActiveChat].
String? activeChatOfPath(String path) {
  if (!path.startsWith('/rooms/')) return null;
  final parts = path.split('/');
  if (parts.length > 3 && parts[2] == 'contact') {
    return mergedContactActiveChat(parts[3]);
  }
  return parts[2];
}

/// Whether [roomId] is on screen when [activeChat] is open: it is that room,
/// or a room of that merged contact. Notifications for it are then left out.
bool isChatActive(String? activeChat, Client client, String roomId) {
  if (activeChat == null) return false;
  if (activeChat == roomId) return true;
  final contact = MergedContactsStore.forClient(client).contactForRoom(roomId);
  return contact != null && activeChat == mergedContactActiveChat(contact.id);
}

const _contactConversationPrefix = 'contact_';

/// The Android conversation (shortcut, channel, notification key) of
/// [roomId]: the room ID, or `contact_<id>` when the room is part of the
/// merged contact [contactId].
String conversationId(String roomId, String? contactId) =>
    contactId == null ? roomId : '$_contactConversationPrefix$contactId';

/// The merged contact a [conversationId] stands for, or null when it is a
/// room ID.
String? contactIdOfConversation(String conversationId) =>
    conversationId.startsWith(_contactConversationPrefix)
    ? conversationId.substring(_contactConversationPrefix.length)
    : null;

/// The conversation a notification for [roomId] belongs to: the room, or the
/// merged contact it is part of, so one contact gets one Android
/// conversation, shortcut and notification however many networks write.
String notificationConversation(Client client, String roomId) {
  final contact = MergedContactsStore.forClient(client).contactForRoom(roomId);
  return conversationId(roomId, contact?.id);
}

/// The display name of [roomId]'s conversation: the merged contact's name,
/// or null to use the room's own.
String? notificationConversationName(
  Client client,
  String roomId,
  MatrixLocalizations i18n,
) {
  final contact = MergedContactsStore.forClient(client).contactForRoom(roomId);
  if (contact == null) return null;
  final name = contact.name;
  if (name != null) return name;
  final sendVia = client.getRoomById(contact.sendViaIn(contact.rooms) ?? '');
  return sendVia?.getLocalizedDisplayname(i18n);
}

/// Whether the notification of [roomId]'s conversation can go: every room
/// of its merged contact has been read, not just this one.
bool notificationConversationRead(Client client, String roomId) {
  final contact = MergedContactsStore.forClient(client).contactForRoom(roomId);
  if (contact == null) return true;
  return contact.rooms.every(
    (id) => (client.getRoomById(id)?.notificationCount ?? 0) == 0,
  );
}
