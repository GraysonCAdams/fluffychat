// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/add_merged_chat.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/merged_network_menu.dart';
import 'package:fluffychat/pages/chat/network_switcher_chips.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:fluffychat/utils/verified_room_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
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
                child: ChatHeaderAvatar(
                  room: room,
                  contact: contact,
                  name: title,
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
                else if (room.isGroupChat)
                  GroupMembersLine(room: room)
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

/// Under a group's title: who is in it, the user first and the others by
/// name, as "You, Drew Andersen, Harrison Young", cut off with an ellipsis.
/// The full member list is asked for once per room; until it arrives the
/// members in memory are shown.
class GroupMembersLine extends StatefulWidget {
  final Room room;

  const GroupMembersLine({required this.room, super.key});

  @override
  State<GroupMembersLine> createState() => _GroupMembersLineState();
}

class _GroupMembersLineState extends State<GroupMembersLine> {
  static const _memberships = [Membership.join, Membership.invite];

  /// Members the server listed that memory may lack, by user ID.
  Map<String, User> _requested = const {};

  @override
  void initState() {
    super.initState();
    _request();
  }

  @override
  void didUpdateWidget(covariant GroupMembersLine oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.room.id != widget.room.id) {
      _requested = const {};
      _request();
    }
  }

  Future<void> _request() async {
    final room = widget.room;
    try {
      final members = await room.requestParticipants(_memberships, true);
      if (!mounted || widget.room.id != room.id) return;
      setState(() => _requested = {for (final m in members) m.id: m});
    } catch (e, s) {
      Logs().w('Unable to load the members of ${room.id}', e, s);
    }
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final skip = {
      room.client.userID,
      MatrixFeatures.forClient(room.client).bridgeOf(room)?.bot,
    };
    // Memory is current; the server's list fills in who memory lacks.
    final members =
        {
          ..._requested,
          for (final m in room.getParticipants(_memberships)) m.id: m,
        }.values.where(
          (m) => !skip.contains(m.id) && _memberships.contains(m.membership),
        );
    final names = members.map((m) => m.calcDisplayname()).toList()..sort();
    return Text(
      [L10n.of(context).you, ...names].join(', '),
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        fontSize: 12,
        color: Theme.of(context).colorScheme.onSurfaceVariant,
      ),
    );
  }
}

/// The picture beside a chat's title: a group without one, merged or not,
/// shows its members, as in the chat list; anything else its avatar. A
/// merged chat shows the room messages go to.
class ChatHeaderAvatar extends StatelessWidget {
  final Room room;
  final MergedContact? contact;
  final String name;

  const ChatHeaderAvatar({
    required this.room,
    required this.contact,
    required this.name,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final shown = contact?.sendViaRoom ?? room;
    return GroupAvatar.shows(shown)
        ? GroupAvatar(room: shown, name: name, size: 32)
        : Avatar(
            mxContent: contact?.avatar ?? room.avatar,
            name: name,
            size: 32,
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

  @override
  Widget build(BuildContext context) {
    final room = controller.room;
    final locals = MatrixLocals(L10n.of(context));
    final merged = controller.mergedContact != null && controller.isMerged;
    // One button per bridge space, picking the room to send to.
    NetworkSwitcherOption option(Room space, String roomId) =>
        NetworkSwitcherOption(
          id: roomId,
          name: space.getLocalizedDisplayname(locals),
          avatar: space.avatar,
        );
    final entries = <NetworkSwitcherOption>[];
    if (merged) {
      // Same-people groups on one bridge are one network: one button, for
      // the room the next message goes to.
      final target = controller.composerTarget.roomId;
      final bySpace = <String, (Room, String)>{};
      for (final network
          in controller.mergedNetworks(locals) ?? const <MergedNetwork>[]) {
        final space = network.space;
        if (space == null) continue;
        if (!bySpace.containsKey(space.id) || network.room.id == target) {
          bySpace[space.id] = (space, network.room.id);
        }
      }
      for (final (space, roomId) in bySpace.values) {
        entries.add(option(space, roomId));
      }
    } else {
      final space = spacesByChild(room.client)[room.id];
      if (space != null) entries.add(option(space, room.id));
    }
    if (entries.isEmpty) return const SizedBox.shrink();
    final locked = merged && controller.composerTarget.locked;
    return NetworkSwitcherChips(
      networks: entries,
      selectedId: merged ? controller.composerTarget.roomId : room.id,
      onPick: merged && !locked
          ? (roomId) {
              controller.setMergedSendVia(roomId);
              controller.pickSendViaRoom(roomId);
            }
          : null,
      trailing: AddMergedChatButton(
        controller,
        width: NetworkSwitcherChips.width,
        height: NetworkSwitcherChips.height,
      ),
    );
  }
}
