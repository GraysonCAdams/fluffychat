// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/typing_run.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/room_kind.dart';
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
    final rooms = contact?.rooms ?? [room];
    return TypingIndicatorRow(
      rooms: rooms,
      oneToOne: TypingIndicatorRow.oneToOneFor(rooms),
      newestFromOwn:
          newest != null && newest.senderId == newest.room.client.userID,
      newestSenderId: newest?.senderId,
    );
  }
}

/// Shows who is typing in any of [rooms], other than the user.
///
/// In a group the bubble starts 8dp past the avatar column, in line with
/// the incoming message bubbles. When the one person typing sent the newest
/// message ([newestSenderId]) the dots continue that run: the bubble sits
/// 1dp under the message like the next bubble of the run, and the avatar
/// stays on the message. Anyone else typing gets their avatar beside the
/// dots, in the avatar's square (see [_TypingAvatars]), as far under the
/// newest message as a message from a new sender would be. In a one-to-one
/// conversation ([oneToOne]) there is nobody to tell apart, so the bubble
/// has no avatar and lines up with the other person's message bubbles: 8dp
/// from the edge, as close under their newest message as the next bubble of
/// their run would be, or as far as a change of sender puts it when the
/// newest message is the user's own ([newestFromOwn]).
class TypingIndicatorRow extends StatefulWidget {
  final List<Room> rooms;
  final bool oneToOne;
  final bool newestFromOwn;

  /// The sender of the newest message. When only that person is typing in a
  /// group, the dots continue their run: the bubble sits at the spacing of a
  /// run, under the avatar on their message.
  final String? newestSenderId;

  const TypingIndicatorRow({
    required this.rooms,
    required this.oneToOne,
    required this.newestFromOwn,
    this.newestSenderId,
    super.key,
  });

  /// Whether [rooms] read as a one-to-one conversation, so the typing row
  /// has no avatar: when every one of them is a direct chat. A merged
  /// contact can be a group on several networks, whose messages show their
  /// senders' avatars and line up past them (see `Message`), and the
  /// typing row lines up with those.
  static bool oneToOneFor(List<Room> rooms) =>
      rooms.every((room) => room.isOneToOne);

  @override
  State<TypingIndicatorRow> createState() => _TypingIndicatorRowState();
}

class _TypingIndicatorRowState extends State<TypingIndicatorRow> {
  // Built once per set of rooms: a stream created in build would make the
  // StreamBuilder unsubscribe and resubscribe on every timeline rebuild.
  late Stream<SyncUpdate> _typingUpdates = _createTypingUpdates();
  late List<Room> _rooms = widget.rooms;

  Stream<SyncUpdate> _createTypingUpdates() => typingUpdatesFor(widget.rooms);

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
    const avatarSize = Message.senderAvatarSize;
    // A one-to-one bubble has no avatar beside it and keeps its own height.
    const oneToOneHeight = Avatar.defaultSize / 2;

    return StreamBuilder<Object>(
      stream: _typingUpdates,
      builder: (context, _) {
        final typingUsers = typingUsersIn(widget.rooms);
        final typing = typingUsers.isNotEmpty;
        final continuesRun =
            !widget.oneToOne &&
            typingContinuesRun(typingUsers, widget.newestSenderId);

        // A message row pads 1dp next to a bubble from the same sender and
        // 8dp otherwise, and the newest message pads 1dp below itself: the
        // dots sit 2dp under it continuing a run, and 16dp where the
        // sender changes, as a new sender's message would.
        final padding = widget.oneToOne
            ? EdgeInsets.only(
                left: 8,
                right: 8,
                top: widget.newestFromOwn ? 15 : 1,
                bottom: 1,
              )
            : EdgeInsets.fromLTRB(8, continuesRun ? 1 : 15, 8, 4);
        final bubble = Material(
          color: theme.colorScheme.surfaceContainerHigh,
          borderRadius: const BorderRadius.all(
            Radius.circular(AppConfig.borderRadius),
          ),
          child: Container(
            // As tall as the avatar beside it, so the bubble's bottom edge
            // meets the avatar's as a run's last bubble does.
            height: continuesRun ? avatarSize : null,
            alignment: Alignment.center,
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
            height: typing
                ? (widget.oneToOne ? oneToOneHeight : avatarSize) +
                      padding.vertical
                : 0,
            duration: FluffyThemes.animationDuration,
            curve: FluffyThemes.animationCurve,
            alignment: Alignment.topLeft,
            clipBehavior: Clip.hardEdge,
            decoration: const BoxDecoration(),
            padding: padding,
            child: Row(
              children: [
                if (!widget.oneToOne) ...[
                  SizedBox.square(
                    key: const ValueKey('typing-avatars'),
                    dimension: avatarSize,
                    // Continuing the sender's run, the avatar stays on
                    // their message and the square stays empty.
                    child: continuesRun || typingUsers.isEmpty
                        ? null
                        : _TypingAvatars(typingUsers),
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

/// Who is typing, in the square one avatar takes: one person's avatar at
/// full size; two people's a little smaller on the diagonal; three people's
/// as three small avatars, two above and one below, the newest typer in
/// front, each ringed in the background colour; four or more as the first
/// two and a counter of the rest in the third place.
class _TypingAvatars extends StatelessWidget {
  final List<User> users;

  const _TypingAvatars(this.users);

  static const double _size = Message.senderAvatarSize;
  static const double _pairSize = 22;

  /// A small avatar with its ring: 16dp inside 1.5dp of background, so two
  /// side by side and one under them span exactly the square.
  static const double _smallSize = 16;
  static const double _ring = 1.5;
  static const double _ringed = _smallSize + 2 * _ring;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    Avatar avatar(User user, double size) => Avatar(
      size: size,
      mxContent: user.avatarUrl,
      name: user.calcDisplayname(),
    );
    if (users.length == 1) return avatar(users.single, _size);
    if (users.length == 2) {
      return Stack(
        children: [
          avatar(users.first, _pairSize),
          Positioned(right: 0, bottom: 0, child: avatar(users.last, _pairSize)),
        ],
      );
    }
    Widget ringed(Widget child, {Key? key}) => Container(
      key: key,
      width: _ringed,
      height: _ringed,
      padding: const EdgeInsets.all(_ring),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        shape: BoxShape.circle,
      ),
      child: child,
    );
    final third = users.length == 3
        ? ringed(avatar(users[2], _smallSize))
        : ringed(
            key: const ValueKey('typing-more'),
            Container(
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: theme.colorScheme.secondaryContainer,
                shape: BoxShape.circle,
              ),
              child: Text(
                '+${users.length - 2}',
                maxLines: 1,
                style: theme.textTheme.labelSmall?.copyWith(
                  fontSize: 9,
                  height: 1,
                  fontWeight: FontWeight.w700,
                  color: theme.colorScheme.onSecondaryContainer,
                ),
              ),
            ),
          );
    // Painted oldest first, so the newest typer is in front.
    return Stack(
      children: [
        Positioned(
          left: 0,
          top: 0,
          child: ringed(avatar(users[0], _smallSize)),
        ),
        Positioned(
          right: 0,
          top: 0,
          child: ringed(avatar(users[1], _smallSize)),
        ),
        Positioned(left: (_size - _ringed) / 2, bottom: 0, child: third),
      ],
    );
  }
}
