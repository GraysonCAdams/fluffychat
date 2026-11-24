// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// What the chat list counts as unread.
///
/// The server counts messages, not reactions, so a reaction never raises
/// [Room.notificationCount]. The client keeps reactions as a room's latest
/// event (see the client's `roomPreviewLastEvents`), which lets a reaction
/// from someone else that arrived after the last read receipt count too.
extension RoomUnread on Room {
  /// Whether the latest event is a reaction from someone else that has not
  /// been read yet.
  bool get hasUnreadReaction =>
      lastEvent?.type == EventTypes.Reaction && hasNewMessages;

  /// Unread messages, a manual unread mark, an invite, or an unread
  /// reaction.
  bool get countsAsUnread => isUnreadOrInvited || hasUnreadReaction;
}
