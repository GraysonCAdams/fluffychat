// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/typing_animation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The typing bubble at the bottom of the chat screen. A merged contact's
/// screen watches every one of the contact's rooms: the send-via network
/// only picks where messages go, and the person may be typing on any of
/// them.
class TypingIndicators extends StatelessWidget {
  final ChatController controller;
  const TypingIndicators(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final contact = controller.isMerged ? controller.mergedContact : null;
    final room = controller.room;
    final newest = controller.timeline?.events.firstWhereOrNull(
      (event) => event.isVisibleInGui,
    );
    return TypingIndicatorRow(
      rooms: contact?.rooms ?? [room],
      oneToOne: contact != null || room.isDirectChat,
      newestFromOwn:
          newest != null && newest.senderId == newest.room.client.userID,
    );
  }
}

/// Shows who is typing in any of [rooms], other than the user.
///
/// In a group the bubble follows the typing people's avatars, 8dp past
/// them. In a one-to-one conversation ([oneToOne]) there is nobody to tell
/// apart, so the bubble has no avatar and lines up with the other person's
/// message bubbles: 8dp from the edge, as close under their newest message
/// as the next bubble of their run would be, or as far as a change of
/// sender puts it when the newest message is the user's own
/// ([newestFromOwn]).
class TypingIndicatorRow extends StatefulWidget {
  final List<Room> rooms;
  final bool oneToOne;
  final bool newestFromOwn;

  const TypingIndicatorRow({
    required this.rooms,
    required this.oneToOne,
    required this.newestFromOwn,
    super.key,
  });

  @override
  State<TypingIndicatorRow> createState() => _TypingIndicatorRowState();
}

class _TypingIndicatorRowState extends State<TypingIndicatorRow> {
  // Built once per set of rooms: a stream created in build would make the
  // StreamBuilder unsubscribe and resubscribe on every timeline rebuild.
  late Stream<SyncUpdate> _typingUpdates = _createTypingUpdates();
  late List<Room> _rooms = widget.rooms;

  Stream<SyncUpdate> _createTypingUpdates() {
    final rooms = widget.rooms;
    return rooms.first.client.onSync.stream.where(
      (syncUpdate) => rooms.any(
        (room) =>
            syncUpdate.rooms?.join?[room.id]?.ephemeral?.any(
              (ephemeral) => ephemeral.type == 'm.typing',
            ) ??
            false,
      ),
    );
  }

  @override
  void didUpdateWidget(covariant TypingIndicatorRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    // The chat screen's room can switch clients when the sending account
    // changes, so compare the rooms themselves, not only their ids.
    if (!const ListEquality<Room>(
      IdentityEquality(),
    ).equals(_rooms, widget.rooms)) {
      _rooms = widget.rooms;
      _typingUpdates = _createTypingUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const avatarSize = Avatar.defaultSize / 2;

    return StreamBuilder<Object>(
      stream: _typingUpdates,
      builder: (context, _) {
        final typingUsers = [
          for (final room in widget.rooms)
            ...room.typingUsers.where((u) => u.id != room.client.userID),
        ];
        final typing = typingUsers.isNotEmpty;

        // A message row pads 1dp next to a bubble from the same sender and
        // 8dp otherwise, and the newest message pads 1dp below itself.
        final padding = widget.oneToOne
            ? EdgeInsets.only(
                left: 8,
                right: 8,
                top: widget.newestFromOwn ? 15 : 1,
                bottom: 1,
              )
            : const EdgeInsets.symmetric(horizontal: 8.0, vertical: 4.0);
        final bubble = Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppConfig.borderRadius),
          ),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: typing ? const TypingAnimation() : null,
          ),
        );

        return Container(
          width: double.infinity,
          alignment: Alignment.center,
          child: AnimatedContainer(
            constraints: const BoxConstraints(
              maxWidth: FluffyThemes.maxTimelineWidth,
            ),
            height: typing ? avatarSize + padding.vertical : 0,
            duration: FluffyThemes.animationDuration,
            curve: FluffyThemes.animationCurve,
            alignment: Alignment.topLeft,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            padding: padding,
            child: Row(
              children: [
                if (!widget.oneToOne) ...[
                  // As wide as the avatars it holds, so the bubble sits 8dp
                  // from them; a second avatar overlaps the first by 8dp.
                  Container(
                    alignment: Alignment.center,
                    height: avatarSize,
                    width: typingUsers.length == 2
                        ? avatarSize + 16
                        : avatarSize,
                    child: Stack(
                      children: [
                        if (typingUsers.isNotEmpty)
                          Avatar(
                            size: avatarSize,
                            mxContent: typingUsers.first.avatarUrl,
                            name: typingUsers.first.calcDisplayname(),
                          ),
                        if (typingUsers.length == 2)
                          Padding(
                            padding: const EdgeInsets.only(left: 16),
                            child: Avatar(
                              size: avatarSize,
                              mxContent: typingUsers.last.avatarUrl,
                              name: typingUsers.last.calcDisplayname(),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                ],
                bubble,
              ],
            ),
          ),
        );
      },
    );
  }
}
