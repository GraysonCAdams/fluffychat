// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/room_kind.dart';
import 'package:matrix/matrix.dart';

/// Syncs that carry a typing update for any of [rooms].
Stream<SyncUpdate> typingUpdatesFor(List<Room> rooms) =>
    rooms.first.client.onSync.stream.where(
      (syncUpdate) => rooms.any(
        (room) =>
            syncUpdate.rooms?.join?[room.id]?.ephemeral?.any(
              (ephemeral) => ephemeral.type == 'm.typing',
            ) ??
            false,
      ),
    );

/// Everyone typing in any of [rooms], other than the user and the rooms'
/// service members, such as a bridge bot.
List<User> typingUsersIn(List<Room> rooms) => [
  for (final room in rooms)
    ...room.typingUsers.where((u) => room.countsAsPerson(u.id)),
];

/// Whether the typing dots continue the run of the sender [senderId] of the
/// newest message: exactly one person is typing and it is that sender.
/// The dots then sit as the run's next bubble, under the avatar on the
/// newest message.
bool typingContinuesRun(List<User> typingUsers, String? senderId) =>
    senderId != null &&
    typingUsers.length == 1 &&
    typingUsers.single.id == senderId;
