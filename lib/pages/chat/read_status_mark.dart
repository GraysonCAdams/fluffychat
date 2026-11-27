// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/own_message_status.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The mark under the user's newest message that says it was sent and,
/// where the network reports read receipts, who has read it.
///
/// In a direct chat it is one mark: a circled check once sent, two filled
/// checks in the primary colour once the other person's m.read receipt
/// reaches the message, as the chat list shows them ([TwoChecks]). A tap on
/// the two checks says when it was read. In a group
/// the readers' faces sit left of the check, and a tap on them lists each
/// reader with the time of their receipt.
///
/// Receipts come from [event]'s own room, so in a merged contact's chat
/// they are those of the network the message went to. Networks that send
/// no receipts (iMessage, SMS) leave the mark at sent.
class ReadStatusMark extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  final Color color;
  final List<Shadow>? shadows;

  const ReadStatusMark({
    super.key,
    required this.event,
    required this.timeline,
    required this.color,
    this.shadows,
  });

  /// How many faces a group shows before a "+N".
  static const int maxFaces = 3;

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
        final room = widget.event.room;
        final receipts = room.readReceiptsOf(widget.event, widget.timeline)
          ..sort((a, b) => b.time.compareTo(a.time));
        if (room.isGroupChat) return _group(context, receipts);
        if (receipts.isEmpty) return _sent(context);
        return _read(context, receipts.first);
      },
    );
  }

  Widget _sent(BuildContext context) => Tooltip(
    message: L10n.of(context).sent,
    child: Icon(
      Icons.check_circle_outline,
      size: 16,
      color: widget.color,
      shadows: widget.shadows,
      semanticLabel: L10n.of(context).sent,
    ),
  );

  Widget _read(BuildContext context, Receipt receipt) {
    final theme = Theme.of(context);
    return _Popover(
      semanticLabel: L10n.of(context).messageRead,
      menuChildren: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Text(
            readTimeLabel(context, receipt.time),
            style: theme.textTheme.bodyMedium,
          ),
        ),
      ],
      child: TwoChecks(filled: true, color: theme.colorScheme.primary),
    );
  }

  Widget _group(BuildContext context, List<Receipt> receipts) {
    final extra = receipts.length - ReadStatusMark.maxFaces;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (receipts.isNotEmpty) ...[
          _Popover(
            semanticLabel: L10n.of(context).readByPeople(receipts.length),
            menuChildren: [
              for (final receipt in receipts) _readerRow(context, receipt),
            ],
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 2,
              children: [
                for (final receipt in receipts.take(ReadStatusMark.maxFaces))
                  Avatar(
                    mxContent: receipt.user.avatarUrl,
                    name: receipt.user.calcDisplayname(),
                    size: 16,
                  ),
                if (extra > 0)
                  Text(
                    '+$extra',
                    style: TextStyle(
                      fontSize: 11,
                      color: widget.color,
                      shadows: widget.shadows,
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(width: 4),
        ],
        _sent(context),
      ],
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
/// anchored to it; a tap outside or another tap on [child] closes it.
class _Popover extends StatelessWidget {
  final Widget child;
  final List<Widget> menuChildren;
  final String semanticLabel;

  const _Popover({
    required this.child,
    required this.menuChildren,
    required this.semanticLabel,
  });

  @override
  Widget build(BuildContext context) {
    return MenuAnchor(
      menuChildren: menuChildren,
      builder: (context, controller, _) => Semantics(
        button: true,
        label: semanticLabel,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () =>
              controller.isOpen ? controller.close() : controller.open(),
          child: child,
        ),
      ),
    );
  }
}
