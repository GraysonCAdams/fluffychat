// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/merged_network_menu.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:fluffychat/utils/verified_room_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class ChatAppBarTitle extends StatelessWidget {
  final ChatController controller;
  const ChatAppBarTitle(this.controller, {super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    // Merging or unmerging this chat changes its title.
    valueListenable: MergedContactsStore.forClient(
      controller.room.client,
    ).revision,
    builder: (context, _, _) => _build(context),
  );

  Widget _build(BuildContext context) {
    final room = controller.room;
    final contact = MergedContact.ofRoom(room.client, room.id);
    final title =
        contact?.displayName(MatrixLocals(L10n.of(context))) ??
        room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    if (controller.selectedEvents.isNotEmpty) {
      return Text(
        controller.selectedEvents.length.toString(),
        style: TextStyle(
          color: Theme.of(context).colorScheme.onTertiaryContainer,
        ),
      );
    }
    return InkWell(
      hoverColor: Colors.transparent,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      onTap: controller.room.membership != .join
          ? null
          : () => FluffyThemes.isThreeColumnMode(context)
                ? controller.toggleDisplayChatDetailsColumn()
                : context.go('/rooms/${room.id}/details'),
      child: Row(
        children: [
          Hero(
            tag: 'content_banner',
            child: Avatar(
              mxContent: contact?.avatar ?? room.avatar,
              name: title,
              size: 32,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                Row(
                  spacing: 4,
                  children: [
                    if (room.allUsersVerified)
                      Icon(
                        Icons.verified,
                        color: Theme.of(context).colorScheme.primary,
                        size: 16,
                      ),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontSize: 16),
                      ),
                    ),
                  ],
                ),
                if (contact != null)
                  _MergedRoomSwitcher(room: room, contact: contact)
                else
                  StreamBuilder(
                    stream: room.client.onSyncStatus.stream,
                    builder: (context, snapshot) {
                      final status =
                          room.client.onSyncStatus.value ??
                          const SyncStatusUpdate(SyncStatus.waitingForResponse);
                      final hide =
                          FluffyThemes.isColumnMode(context) ||
                          (room.client.onSync.value != null &&
                              status.status != SyncStatus.error &&
                              room.client.prevBatch != null);
                      final style = TextStyle(fontSize: 11);
                      return AnimatedSize(
                        duration: FluffyThemes.animationDuration,
                        child: hide
                            ? room.isDirectChat
                                  ? PresenceBuilder(
                                      userId: room.directChatMatrixID,
                                      builder: (context, presence) {
                                        final statusMessage = presence
                                            ?.statusMsg
                                            ?.trim();

                                        final lastActiveTimestamp =
                                            presence?.lastActiveTimestamp;

                                        final texts = [
                                          if (presence?.currentlyActive == true)
                                            L10n.of(context).currentlyActive
                                          else if (lastActiveTimestamp != null)
                                            L10n.of(context).lastActiveAgo(
                                              lastActiveTimestamp
                                                  .localizedTimeShort(context),
                                            ),
                                          ?statusMessage,
                                        ];
                                        final text = texts.join(' ◦ ');
                                        if (text.isEmpty) {
                                          return const SizedBox.shrink();
                                        }

                                        return Text(text, style: style);
                                      },
                                    )
                                  : Row(
                                      children: [
                                        if (room.summary.mJoinedMemberCount !=
                                            null)
                                          Text(
                                            L10n.of(context).countParticipants(
                                              (room
                                                          .summary
                                                          .mJoinedMemberCount ??
                                                      1) +
                                                  (room
                                                          .summary
                                                          .mInvitedMemberCount ??
                                                      0),
                                            ),
                                            maxLines: 1,
                                            style: style,
                                          ),
                                        if (room.topic.isNotEmpty) ...[
                                          Text(' ◦ ', style: style),
                                          Expanded(
                                            child: Text(
                                              room.topic,
                                              style: style,
                                              maxLines: 1,
                                            ),
                                          ),
                                        ],
                                      ],
                                    )
                            : Row(
                                children: [
                                  SizedBox.square(
                                    dimension: 10,
                                    child: CircularProgressIndicator.adaptive(
                                      strokeWidth: 1,
                                      value: status.progress,
                                    ),
                                  ),
                                  const SizedBox(width: 4),
                                  Expanded(
                                    child: Text(
                                      status.calcLocalizedString(context),
                                      style: TextStyle(fontSize: 12),
                                    ),
                                  ),
                                ],
                              ),
                      );
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Under the title of a chat that belongs to a merged contact: the network
/// shown, which opens the contact's other networks and switches to the one
/// picked.
class _MergedRoomSwitcher extends StatelessWidget {
  final Room room;
  final MergedContact contact;

  const _MergedRoomSwitcher({required this.room, required this.contact});

  @override
  Widget build(BuildContext context) {
    final networks = MergedNetwork.of(contact, MatrixLocals(L10n.of(context)));
    final current = networks.firstWhere((n) => n.room.id == room.id);
    return Builder(
      builder: (context) => InkWell(
        borderRadius: BorderRadius.circular(8),
        onTap: () async {
          final picked = await showMergedNetworkMenu(
            context,
            networks: networks,
            selectedRoomId: room.id,
            defaultRoomId: contact.sendViaRoom.id,
          );
          if (picked == null || picked == room.id || !context.mounted) return;
          context.go('/rooms/$picked');
        },
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 4,
          children: [
            current.icon(size: 14),
            Flexible(
              child: Text(
                current.name,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: 11),
              ),
            ),
            const Icon(Icons.arrow_drop_down, size: 16),
          ],
        ),
      ),
    );
  }
}
