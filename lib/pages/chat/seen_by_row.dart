// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class SeenByRow extends StatefulWidget {
  final Event event;
  final Timeline timeline;
  const SeenByRow({super.key, required this.event, required this.timeline});

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
}
