// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/add_merged_chat.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/merged_network_menu.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
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
    final contact = controller.mergedContact;
    final title =
        contact?.displayName(MatrixLocals(L10n.of(context))) ??
        room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    // The networks this chat reaches: each of a merged contact's, or the one
    // space a single chat belongs to.
    final networkSpaces = contact != null && controller.isMerged
        ? [
            for (final network
                in controller.mergedNetworks(MatrixLocals(L10n.of(context))) ??
                    const <MergedNetwork>[])
              network.space,
          ]
        : [spacesByChild(room.client)[room.id]];
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
          : controller.openDetails,
      child: Row(
        children: [
          Stack(
            clipBehavior: Clip.none,
            children: [
              Hero(
                tag: 'content_banner',
                child: Avatar(
                  mxContent: contact?.avatar ?? room.avatar,
                  name: title,
                  size: 32,
                ),
              ),
            ],
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
                if (contact != null && controller.isMerged)
                  const SizedBox.shrink()
                else if (contact != null)
                  _MergedRoomSwitcher(room: room, contact: contact)
                else if (networkSpaces.isNotEmpty)
                  const SizedBox.shrink()
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
          // This room is shown on its own, so the other one is too.
          context.go('/rooms/$picked?single=1');
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

/// The chat's networks in the app bar, before the menu, as a Material
/// connected button group of toggle icon buttons: extra-small buttons (32
/// high, 20 icon) 2 apart, the group's outer corners fully round and its
/// inner corners 8. The selected button is the network the next message goes
/// out on and takes the brighter fill; tapping another one switches
/// to it. While replying, editing or in a thread the network is fixed by the
/// message being answered, so the buttons do not respond.
class ChatNetworkIcons extends StatelessWidget {
  final ChatController controller;

  const ChatNetworkIcons(this.controller, {super.key});

  static const _height = 32.0;
  static const _width = 40.0;
  static const _iconSize = 20.0;
  static const _outer = Radius.circular(_height / 2);
  static const _inner = Radius.circular(8);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = controller.room;
    final locals = MatrixLocals(L10n.of(context));
    final merged = controller.mergedContact != null && controller.isMerged;
    // (space, room to send to) per network.
    final entries = <(Room, String)>[];
    if (merged) {
      for (final network
          in controller.mergedNetworks(locals) ?? const <MergedNetwork>[]) {
        final space = network.space;
        if (space != null) entries.add((space, network.room.id));
      }
    } else {
      final space = spacesByChild(room.client)[room.id];
      if (space != null) entries.add((space, room.id));
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    final selectedRoomId = merged ? controller.composerTarget.roomId : room.id;
    final locked = merged && controller.composerTarget.locked;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        for (final (index, (space, roomId)) in entries.indexed)
          _button(
            context,
            theme,
            space: space,
            name: space.getLocalizedDisplayname(locals),
            selected: roomId == selectedRoomId,
            first: index == 0,
            // The add-chat plus after the networks is the group's last
            // segment.
            last: false,
            onTap: merged && roomId != selectedRoomId && !locked
                ? () {
                    controller.setMergedSendVia(roomId);
                    controller.pickSendViaRoom(roomId);
                  }
                : null,
          ),
        AddMergedChatButton(controller, width: _width, height: _height),
      ],
    );
  }

  Widget _button(
    BuildContext context,
    ThemeData theme, {
    required Room space,
    required String name,
    required bool selected,
    required bool first,
    required bool last,
    required void Function()? onTap,
  }) {
    final radius = BorderRadius.horizontal(
      left: first ? _outer : _inner,
      right: last ? _outer : _inner,
    );
    return Tooltip(
      message: name,
      child: AnimatedContainer(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        height: _height,
        width: _width,
        decoration: BoxDecoration(
          // Quieter than the spec's selected tonal color, which outshines
          // a network's own logo.
          color: selected
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: radius,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onTap,
            child: Center(
              child: Avatar(
                mxContent: space.avatar,
                name: name,
                size: _iconSize,
                borderRadius: BorderRadius.circular(5),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
