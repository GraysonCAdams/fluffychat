// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';
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

/// Everyone typing in any of [rooms], other than the user.
List<User> typingUsersIn(List<Room> rooms) => [
  for (final room in rooms)
    ...room.typingUsers.where((u) => u.id != room.client.userID),
];

/// Whether the typing dots continue the run of the sender [senderId] of the
/// newest message: exactly one person is typing and it is that sender.
/// The dots then carry the run's avatar and the newest message does not.
bool typingContinuesRun(List<User> typingUsers, String? senderId) =>
    senderId != null &&
    typingUsers.length == 1 &&
    typingUsers.single.id == senderId;

/// The avatar slot of a group message's last bubble, faded out while the
/// typing dots continue the sender's run ([isNewest]: no newer message
/// follows). The slot keeps its size, so the bubble does not move when the
/// avatar leaves or returns.
class RunAvatarSlot extends StatelessWidget {
  final Room room;
  final String senderId;
  final bool isNewest;
  final Widget child;

  const RunAvatarSlot({
    required this.room,
    required this.senderId,
    required this.isNewest,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    if (!isNewest) return child;
    return StreamBuilder<Object>(
      stream: typingUpdatesFor([room]),
      builder: (context, _) => AnimatedOpacity(
        opacity: typingContinuesRun(typingUsersIn([room]), senderId) ? 0 : 1,
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: child,
      ),
    );
  }
}
