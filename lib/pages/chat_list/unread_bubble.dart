// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/room_unread.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class UnreadBubble extends StatelessWidget {
  final Room room;

  /// When set, the bubble counts across every room of this merged contact.
  final MergedContact? contact;

  const UnreadBubble({required this.room, this.contact, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final contact = this.contact;
    final unread = contact?.isUnread ?? room.countsAsUnread;
    final notificationCount =
        contact?.notificationCount ?? room.notificationCount;
    final highlightCount = contact?.highlightCount ?? room.highlightCount;
    final hasNewMessages = contact?.hasNewMessages ?? room.hasNewMessages;
    final markedUnread = contact?.markedUnread ?? room.markedUnread;
    final hasNotifications = notificationCount > 0;
    final unreadBubbleSize = unread || hasNewMessages
        ? notificationCount > 0
              ? 20.0
              : 14.0
        : 0.0;
    final showsCount = hasNotifications || markedUnread;
    // Chat list tiles read as one screen reader node, where a bare number
    // would not say what it counts.
    final semanticsLabel = showsCount
        ? '${L10n.of(context).unread}: $notificationCount'
        : unreadBubbleSize > 0
        ? L10n.of(context).unread
        : null;
    final bubble = AnimatedContainer(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.center,
      padding: const EdgeInsets.symmetric(horizontal: 7),
      height: unreadBubbleSize,
      width: !hasNotifications && !unread && !hasNewMessages
          ? 0
          : (unreadBubbleSize - 9) * notificationCount.toString().length + 9,
      decoration: BoxDecoration(
        color: highlightCount > 0
            ? theme.colorScheme.error
            : hasNotifications || markedUnread || room.membership == .invite
            ? theme.colorScheme.primary
            : theme.colorScheme.primaryContainer,
        borderRadius: BorderRadius.circular(unreadBubbleSize),
      ),
      child: showsCount
          ? Text(
              notificationCount.toString(),
              style: TextStyle(
                color: highlightCount > 0
                    ? theme.colorScheme.onError
                    : hasNotifications
                    ? theme.colorScheme.onPrimary
                    : theme.colorScheme.onPrimaryContainer,
                fontSize: 13,
                fontWeight: FontWeight.w500,
                // The line box is the glyph height with its spare leading
                // split evenly above and below, so the digits sit in the
                // middle of the badge whatever the platform font's ascent
                // and descent (Segoe UI on Windows leaves them low).
                height: 1,
                leadingDistribution: TextLeadingDistribution.even,
              ),
              textHeightBehavior: const TextHeightBehavior(
                leadingDistribution: TextLeadingDistribution.even,
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
