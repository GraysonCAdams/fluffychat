// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/status_mark.dart';
import 'package:fluffychat/utils/room_kind.dart';
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
/// list does not show. The bridge bot and other service members (see
/// [RoomKind.serviceMembers]) do not count as readers or members,
/// so in a bridged chat only the other side's own receipts (which
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

  final readers = <String>{};
  void collect(LatestReceiptStateForTimeline? receipts) =>
      receipts?.otherUsers.forEach((user, receipt) {
        if (!room.countsAsPerson(user)) return;
        if (receipt.eventId == event.eventId ||
            receipt.timestamp.isAfter(event.originServerTs)) {
          readers.add(user);
        }
      });
  collect(room.receiptState.global);
  collect(room.receiptState.mainThread);

  final others = max(room.otherPeopleCount, readers.length);

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
/// newest message, a [StatusMark] in the preview text's [color]: a clock
/// while it is sending, one circled check once sent, two rings when some
/// members of a group have read it, and the two filled once everyone has;
/// the error icon when it failed. It follows read receipts as they arrive,
/// animating from one state to the next.
class OwnMessageStatusIcon extends StatefulWidget {
  final Event event;
  final Color? color;

  const OwnMessageStatusIcon(this.event, {this.color, super.key});

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

    final label = switch (status.state) {
      OwnMessageState.sending => l10n.sending,
      OwnMessageState.failed => l10n.failedToSend,
      OwnMessageState.sent => l10n.sent,
      OwnMessageState.readBySome => l10n.readByCount(
        status.readers,
        status.others,
      ),
      OwnMessageState.read => l10n.messageRead,
    };
    final icon = StatusMark(
      // A newer message is a new mark, not the last one's changing.
      key: ValueKey(widget.event.transactionId ?? widget.event.eventId),
      state: switch (status.state) {
        OwnMessageState.sending => StatusMarkState.sending,
        OwnMessageState.failed => StatusMarkState.failed,
        OwnMessageState.sent => StatusMarkState.sent,
        OwnMessageState.readBySome => StatusMarkState.readBySome,
        OwnMessageState.read => StatusMarkState.read,
      },
      color: color ?? theme.colorScheme.onSurfaceVariant,
      sending: StatusMarkSending.clock,
      errorIcon: Icons.error_outline,
    );
    return Padding(
      padding: const EdgeInsetsDirectional.only(end: 4),
      child: Semantics(label: label, excludeSemantics: true, child: icon),
    );
  }
}
