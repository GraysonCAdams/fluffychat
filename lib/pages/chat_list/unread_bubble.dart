// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/room_unread.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

const double _fontSize = 13;

/// How far to lift the count's digits so they sit in the middle of the badge.
///
/// Segoe UI, the Windows system font, keeps much more room above its digits
/// than below, so evenly split leading leaves them 0.067 of the font size
/// low in all three Segoe UI faces Windows uses (measured in
/// test/pages/chat_list/unread_bubble_font_test.dart). Elsewhere the digits
/// already sit centred.
double unreadDigitNudge(double fontSize, [TargetPlatform? platform]) =>
    (platform ?? defaultTargetPlatform) == TargetPlatform.windows
    ? fontSize * 0.067
    : 0;

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
          ? Transform.translate(
              offset: Offset(0, -unreadDigitNudge(_fontSize)),
              child: Text(
                notificationCount.toString(),
                style: TextStyle(
                  color: highlightCount > 0
                      ? theme.colorScheme.onError
                      : hasNotifications
                      ? theme.colorScheme.onPrimary
                      : theme.colorScheme.onPrimaryContainer,
                  fontSize: _fontSize,
                  fontWeight: FontWeight.w500,
                  // The line box is the font size with its spare leading split
                  // evenly above and below. That centres Roboto's digits on
                  // Android; unreadDigitNudge corrects Segoe UI on Windows.
                  height: 1,
                  leadingDistribution: TextLeadingDistribution.even,
                ),
                textHeightBehavior: const TextHeightBehavior(
                  leadingDistribution: TextLeadingDistribution.even,
                ),
                textAlign: .center,
              ),
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
