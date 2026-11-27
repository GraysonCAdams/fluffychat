// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/reader_stack.dart';
import 'package:fluffychat/pages/chat/status_mark.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The mark under the user's newest message that says it was sent and,
/// where the network reports read receipts, who has read it.
///
/// One [StatusMark] in the status line's own colour follows the message
/// from sending (beside the "Sending" label) to sent, or to failed (beside
/// "Could not be sent"). In a direct chat it turns read, two filled rings,
/// once the other person's m.read receipt reaches the message, and a tap on
/// it says when it was read. In a group the readers' faces stack left of
/// the check ([ReaderStack]), and a tap on them lists each reader with the
/// time of their receipt.
///
/// Receipts come from [event]'s own room, so in a merged contact's chat
/// they are those of the network the message went to. Networks that send
/// no receipts (iMessage, SMS) leave the mark at sent.
class ReadStatusMark extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  final Color color;

  const ReadStatusMark({
    super.key,
    required this.event,
    required this.timeline,
    required this.color,
  });

  @override
  State<ReadStatusMark> createState() => _ReadStatusMarkState();
}

class _ReadStatusMarkState extends State<ReadStatusMark> {
  // Built once per room: a stream created in build would make the
  // StreamBuilder unsubscribe and resubscribe on every timeline rebuild.
  late Stream<SyncUpdate> _receiptUpdates = _createReceiptUpdates();

  Stream<SyncUpdate> _createReceiptUpdates() {
    final room = widget.event.room;
    return room.client.onSync.stream.where(
      (syncUpdate) =>
          syncUpdate.rooms?.join?[room.id]?.ephemeral?.any(
            (ephemeral) => ephemeral.type == 'm.receipt',
          ) ??
          false,
    );
  }

  @override
  void didUpdateWidget(covariant ReadStatusMark oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.room.id != widget.event.room.id ||
        oldWidget.event.room.client != widget.event.room.client) {
      _receiptUpdates = _createReceiptUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder(
      stream: _receiptUpdates,
      builder: (context, _) {
        final event = widget.event;
        final room = event.room;
        final l10n = L10n.of(context);
        final receipts = event.status.isSent
            ? (room.readReceiptsOf(event, widget.timeline)
                ..sort((a, b) => b.time.compareTo(a.time)))
            : <Receipt>[];
        final group = room.isGroupChat;
        final state = switch (event.status) {
          EventStatus.error => StatusMarkState.failed,
          EventStatus.sending => StatusMarkState.sending,
          _ when !group && receipts.isNotEmpty => StatusMarkState.read,
          _ => StatusMarkState.sent,
        };
        final label = switch (state) {
          StatusMarkState.failed => l10n.couldNotBeSent,
          StatusMarkState.sending => l10n.sending,
          StatusMarkState.read => l10n.messageRead,
          _ => l10n.sent,
        };
        // The mark keeps its place in the tree in every state, so a change
        // of state animates it instead of building a new one.
        final mark = _Popover(
          semanticLabel: label,
          enabled: state == StatusMarkState.read,
          menuChildren: [
            if (receipts.isNotEmpty)
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                child: Text(
                  readTimeLabel(context, receipts.first.time),
                  style: Theme.of(context).textTheme.bodyMedium,
                ),
              ),
          ],
          child: Tooltip(
            message: label,
            child: StatusMark(state: state, color: widget.color),
          ),
        );
        if (!group) return mark;
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _Popover(
              semanticLabel: l10n.readByPeople(receipts.length),
              enabled: receipts.isNotEmpty,
              menuChildren: [
                for (final receipt in receipts) _readerRow(context, receipt),
              ],
              child: ReaderStack(
                color: widget.color,
                readers: [
                  for (final receipt in receipts)
                    StackedReader(
                      id: receipt.user.id,
                      name: receipt.user.calcDisplayname(),
                      avatar: receipt.user.avatarUrl,
                    ),
                ],
              ),
            ),
            mark,
          ],
        );
      },
    );
  }

  Widget _readerRow(BuildContext context, Receipt receipt) {
    final theme = Theme.of(context);
    final name = receipt.user.calcDisplayname();
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        spacing: 12,
        children: [
          Avatar(mxContent: receipt.user.avatarUrl, name: name, size: 32),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(name, style: theme.textTheme.bodyMedium),
              Text(
                readTimeLabel(context, receipt.time),
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

/// "Read 1:33 PM", "Read yesterday 9:02 PM", or with the date further back.
String readTimeLabel(BuildContext context, DateTime time) {
  final l10n = L10n.of(context);
  final daysAgo = DateTime.now().dateOnly.difference(time.dateOnly).inDays;
  return switch (daysAgo) {
    0 => l10n.readAtTime(time.localizedTimeOfDay(context)),
    1 => l10n.readYesterdayAtTime(time.localizedTimeOfDay(context)),
    _ => l10n.readAtTime(time.localizedTime(context)),
  };
}

/// [child] as a button that opens [menuChildren] in a small popover
/// anchored to it; a tap outside or another tap on [child] closes it. When
/// not [enabled] it is [child] alone, in the same place in the tree.
class _Popover extends StatelessWidget {
  final Widget child;
  final List<Widget> menuChildren;
  final String semanticLabel;
  final bool enabled;

  const _Popover({
    required this.child,
    required this.menuChildren,
    required this.semanticLabel,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: menuChildren,
      builder: (context, controller, _) => Semantics(
        button: enabled,
        label: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: !enabled
              ? null
              : () =>
                    controller.isOpen ? controller.close() : controller.open(),
          child: child,
        ),
      ),
    );
  }
}
