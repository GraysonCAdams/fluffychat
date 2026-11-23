// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class UnreadBubble extends StatelessWidget {
  final Room room;
  const UnreadBubble({required this.room, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final unread = room.isUnreadOrInvited;
    final hasNotifications = room.notificationCount > 0;
    final unreadBubbleSize = unread || room.hasNewMessages
        ? room.notificationCount > 0
              ? 20.0
              : 14.0
        : 0.0;
    final showsCount = hasNotifications || room.markedUnread;
    // Chat list tiles read as one screen reader node, where a bare number
    // would not say what it counts.
    final semanticsLabel = showsCount
        ? '${L10n.of(context).unread}: ${room.notificationCount}'
        : unreadBubbleSize > 0
        ? L10n.of(context).unread
        : null;
    final bubble = AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      height: unreadBubbleSize,
      width: !hasNotifications && !unread && !room.hasNewMessages
          ? 0
          : (unreadBubbleSize - 9) * room.notificationCount.toString().length +
                9,
      decoration: BoxDecoration(
        color: room.highlightCount > 0
            ? theme.colorScheme.error
            : hasNotifications ||
                  room.markedUnread ||
                  room.membership == .invite
            ? theme.colorScheme.primary
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(unreadBubbleSize),
      ),
      child: showsCount
          ? Text(
              room.notificationCount.toString(),
              style: TextStyle(
                color: room.highlightCount > 0
                    ? theme.colorScheme.onError
                    : hasNotifications
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onPrimaryContainer,
                fontSize: 13,
                fontWeight: FontWeight.w500,
              ),
              textAlign: .center,
            )
          : const SizedBox.shrink(),
    );
    if (semanticsLabel == null) return bubble;
    return Semantics(
      label: semanticsLabel,
      excludeSemantics: true,
      child: bubble,
    );
  }
}
