// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// How far the user's own message has got, as the chat list shows it.
///
/// There is no "delivered": none of the bridges reports delivery to the
/// other side's device, and the server taking the message is "sent".
enum OwnMessageState { sending, sent, readBySome, read, failed }

@immutable
class OwnMessageStatus {
  final OwnMessageState state;

  /// The other members who have read it, and how many there are. Both 0
  /// until it is sent.
  final int readers;
  final int others;

  const OwnMessageStatus(this.state, {this.readers = 0, this.others = 0});
}

/// The status of [event] when the user sent it, or null for someone else's
/// message.
///
/// A member has read it when their newest receipt is on it, or on anything
/// they read after it was sent: a receipt can sit on a later event the chat
/// list does not show. The bridge bot does not count as a reader or a
/// member, so in a bridged chat only the other side's own receipts (which
/// Google Messages over RCS and Telegram send, and iMessage and SMS never
/// do) turn it read.
OwnMessageStatus? ownMessageStatusOf(Event event) {
  final room = event.room;
  final me = room.client.userID;
  if (me == null || event.senderId != me) return null;
  if (event.status == EventStatus.error) {
    return const OwnMessageStatus(OwnMessageState.failed);
  }
  if (!event.status.isSent) {
    return const OwnMessageStatus(OwnMessageState.sending);
  }

  final bot = RoomBridge.fromState(room)?.bot;
  final readers = <String>{};
  void collect(LatestReceiptStateForTimeline? receipts) =>
      receipts?.otherUsers.forEach((user, receipt) {
        if (user == me || user == bot) return;
        if (receipt.eventId == event.eventId ||
            receipt.timestamp.isAfter(event.originServerTs)) {
          readers.add(user);
        }
      });
  collect(room.receiptState.global);
  collect(room.receiptState.mainThread);

  // The joined count takes in the user and, while it is in the room, the
  // bridge bot.
  final botMembership = bot == null
      ? null
      : room
            .getState(EventTypes.RoomMember, bot)
            ?.content
            .tryGet<String>('membership');
  final botJoined = bot != null && (botMembership ?? 'join') == 'join';
  final joined = room.summary.mJoinedMemberCount ?? 0;
  final others = max(joined - 1 - (botJoined ? 1 : 0), readers.length);

  if (readers.isEmpty) {
    return OwnMessageStatus(OwnMessageState.sent, others: others);
  }
  return OwnMessageStatus(
    readers.length >= others
        ? OwnMessageState.read
        : OwnMessageState.readBySome,
    readers: readers.length,
    others: others,
  );
}

/// The icon in front of "You:" in the chat list for [event], the user's
/// newest message: a clock while it is sending, one circled check once
/// sent, two when some members of a group have read it, and two filled in
/// the primary color once everyone has; the error icon when it failed.
/// [color] is the preview text's color. It follows read receipts as they
/// arrive.
class OwnMessageStatusIcon extends StatefulWidget {
  final Event event;
  final Color? color;

  const OwnMessageStatusIcon(this.event, {this.color, super.key});

  static const double size = 16;

  /// How far the front check sits from the back one.
  static const double overlap = 7;

  @override
  State<OwnMessageStatusIcon> createState() => _OwnMessageStatusIconState();
}

class _OwnMessageStatusIconState extends State<OwnMessageStatusIcon> {
  StreamSubscription<SyncUpdate>? _receipts;

  void _listen() {
    _receipts?.cancel();
    final room = widget.event.room;
    _receipts = room.client.onSync.stream
        .where(
          (update) =>
              update.rooms?.join?[room.id]?.ephemeral?.any(
                (event) => event.type == 'm.receipt',
              ) ??
              false,
        )
        .listen((_) {
          if (mounted) setState(() {});
        });
  }

  @override
  void initState() {
    super.initState();
    _listen();
  }

  @override
  void didUpdateWidget(OwnMessageStatusIcon oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.room != widget.event.room) _listen();
  }

  @override
  void dispose() {
    _receipts?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final status = ownMessageStatusOf(widget.event);
    if (status == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final color = widget.color ?? DefaultTextStyle.of(context).style.color;
    const size = OwnMessageStatusIcon.size;

    final (label, icon) = switch (status.state) {
      OwnMessageState.sending => (
        l10n.sending,
        Icon(Icons.schedule, size: size, color: color),
      ),
      OwnMessageState.failed => (
        l10n.failedToSend,
        Icon(Icons.error_outline, size: size, color: theme.colorScheme.error),
      ),
      OwnMessageState.sent => (
        l10n.sent,
        Icon(Icons.check_circle_outline, size: size, color: color),
      ),
      OwnMessageState.readBySome => (
        l10n.readByCount(status.readers, status.others),
        TwoChecks(filled: false, color: color),
      ),
      OwnMessageState.read => (
        l10n.messageRead,
        TwoChecks(filled: true, color: theme.colorScheme.primary),
      ),
    };
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Semantics(label: label, excludeSemantics: true, child: icon),
    );
  }
}

/// Two circled checks, the front one over the back one with a ring of the
/// background between them. Filled in the primary colour they are the read
/// mark, here and under the user's newest message in a chat.
class TwoChecks extends StatelessWidget {
  final bool filled;
  final Color? color;

  const TwoChecks({super.key, required this.filled, required this.color});

  @override
  Widget build(BuildContext context) {
    const size = OwnMessageStatusIcon.size;
    const ring = 1.5;
    final check = Icon(
      filled ? Icons.check_circle : Icons.check_circle_outline,
      size: size,
      color: color,
    );
    return SizedBox(
      width: size + OwnMessageStatusIcon.overlap,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          // The back check is cut where the front one covers it, leaving a
          // ring of whatever is behind the row between them.
          PositionedDirectional(
            start: 0,
            top: 0,
            child: ClipPath(
              clipper: _BehindFront(
                ring,
                rtl: Directionality.of(context) == TextDirection.rtl,
              ),
              child: check,
            ),
          ),
          PositionedDirectional(
            start: OwnMessageStatusIcon.overlap,
            top: 0,
            child: check,
          ),
        ],
      ),
    );
  }
}

/// The back check's area less the front check's circle, grown by [ring].
/// The front check sits after the back one in the reading direction.
class _BehindFront extends CustomClipper<Path> {
  final double ring;
  final bool rtl;

  const _BehindFront(this.ring, {required this.rtl});

  @override
  Path getClip(Size size) {
    final front = Offset(
      (rtl ? -1 : 1) * OwnMessageStatusIcon.overlap + size.width / 2,
      size.height / 2,
    );
    return Path.combine(
      PathOperation.difference,
      Path()..addRect(Offset.zero & size),
      Path()..addOval(
        Rect.fromCircle(center: front, radius: size.width / 2 + ring),
      ),
    );
  }

  @override
  bool shouldReclip(_BehindFront oldClipper) =>
      oldClipper.ring != ring || oldClipper.rtl != rtl;
}
