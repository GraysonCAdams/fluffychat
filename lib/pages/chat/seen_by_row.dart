// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The faces of the members whose read receipt is at or after [event].
///
/// Under the newest message of a direct chat these are bare faces on a row
/// of their own. With [label], as under the user's newest message in a
/// group, they follow "Seen by" at the end of the bubble.
class SeenByRow extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  final bool label;
  const SeenByRow({
    super.key,
    required this.event,
    required this.timeline,
    this.label = false,
  });

  @override
  State<SeenByRow> createState() => _SeenByRowState();
}

class _SeenByRowState extends State<SeenByRow> {
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
  void didUpdateWidget(covariant SeenByRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.event.room.id != widget.event.room.id ||
        oldWidget.event.room.client != widget.event.room.client) {
      _receiptUpdates = _createReceiptUpdates();
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = widget.event;
    final timeline = widget.timeline;

    const maxAvatars = 7;
    return StreamBuilder(
      stream: _receiptUpdates,
      builder: (context, asyncSnapshot) {
        final seenByUsers = event.room.getSeenByUsers(
          timeline,
          eventId: event.eventId,
        );
        if (widget.label) return _labelled(context, seenByUsers);
        return Container(
          width: double.infinity,
          alignment: Alignment.center,
          child: AnimatedContainer(
            constraints: const BoxConstraints(
              maxWidth: FluffyThemes.maxTimelineWidth,
            ),
            height: seenByUsers.isEmpty ? 0 : 24,
            duration: seenByUsers.isEmpty
                ? Duration.zero
                : FluffyThemes.animationDuration,
            curve: FluffyThemes.animationCurve,
            alignment: event.senderId == Matrix.of(context).client.userID
                ? Alignment.topRight
                : Alignment.topLeft,
            padding: const EdgeInsets.only(
              bottom: 4,
              top: 1,
              left: 8,
              right: 8,
            ),
            child: Wrap(
              spacing: 4,
              children: [
                ...(seenByUsers.length > maxAvatars
                        ? seenByUsers.sublist(0, maxAvatars)
                        : seenByUsers)
                    .map(
                      (user) => Avatar(
                        mxContent: user.avatarUrl,
                        name: user.calcDisplayname(),
                        size: 16,
                      ),
                    ),
                if (seenByUsers.length > maxAvatars)
                  SizedBox(
                    width: 16,
                    height: 16,
                    child: Material(
                      color: theme.colorScheme.surface,
                      borderRadius: BorderRadius.circular(32),
                      child: Center(
                        child: Text(
                          '+${seenByUsers.length - maxAvatars}',
                          style: const TextStyle(fontSize: 9),
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _labelled(BuildContext context, List<User> seenByUsers) {
    const maxAvatars = 7;
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    final extra = seenByUsers.length - maxAvatars;
    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.topRight,
      child: seenByUsers.isEmpty
          ? const SizedBox(width: double.infinity)
          : Container(
              width: double.infinity,
              alignment: Alignment.centerRight,
              padding: const EdgeInsets.only(top: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 2,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(right: 2),
                    child: Text(
                      L10n.of(context).seenBy,
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                  ),
                  for (final user in seenByUsers.take(maxAvatars))
                    Tooltip(
                      message: user.calcDisplayname(),
                      child: Avatar(
                        mxContent: user.avatarUrl,
                        name: user.calcDisplayname(),
                        size: 16,
                      ),
                    ),
                  if (extra > 0)
                    Text(
                      '+$extra',
                      style: TextStyle(fontSize: 11, color: color),
                    ),
                ],
              ),
            ),
    );
  }
}
