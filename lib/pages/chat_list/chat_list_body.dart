// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/dummy_chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/pages/chat_list/space_view.dart';
import 'package:fluffychat/utils/stream_extension.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/public_room_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';
import '../../widgets/matrix.dart';
import 'chat_list_header.dart';

class ChatListViewBody extends StatelessWidget {
  final ChatListController controller;

  const ChatListViewBody(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final client = Matrix.of(context).client;
    final activeSpace = controller.activeSpaceId;
    final spacesAsChatList = AppSettings.openSpacesAsChatList.value;
    if (activeSpace != null &&
        (controller.spaceDirectoryOpen || !spacesAsChatList)) {
      return SpaceView(
        key: ValueKey(activeSpace),
        spaceId: activeSpace,
        onBack: controller.clearActiveSpace,
        onClose: spacesAsChatList
            ? () => controller.setSpaceDirectoryOpen(false)
            : null,
        onChatTab: controller.onChatTap,
        activeChat: controller.activeChat,
      );
    }
    final activeSpaceRoom = activeSpace == null
        ? null
        : client.getRoomById(activeSpace);
    final spaces = client.rooms.where((r) => r.isSpace);
    final spaceDelegateCandidates = <String, Room>{};
    for (final space in spaces) {
      for (final spaceChild in space.spaceChildren) {
        final roomId = spaceChild.roomId;
        if (roomId == null) continue;
        spaceDelegateCandidates[roomId] = space;
      }
    }

    final publicRooms = controller.roomSearchResult?.chunk
        .where((room) => room.roomType != 'm.space')
        .toList();
    final publicSpaces = controller.roomSearchResult?.chunk
        .where((room) => room.roomType == 'm.space')
        .toList();
    final userSearchResult = controller.userSearchResult;
    const dummyChatCount = 4;
    final filter = controller.searchController.text.toLowerCase();
    return StreamBuilder(
      key: ValueKey(client.userID.toString()),
      stream: client.onSync.stream
          .where((s) => s.hasRoomUpdate)
          .rateLimit(const Duration(seconds: 1)),
      builder: (context, _) {
        final spaceRoomIds = activeSpaceRoom == null
            ? null
            : _roomIdsInSpace(client, activeSpaceRoom);
        final rooms = controller.filteredRooms
            .where(
              (room) => spaceRoomIds != null
                  ? spaceRoomIds.contains(room.id)
                  : !AppSettings.hideRoomsInSpaces.value ||
                        spaceDelegateCandidates[room.id] == null,
            )
            .toList();

        return CustomScrollView(
          controller: controller.scrollController,
          slivers: [
            if (activeSpaceRoom == null)
              ChatListHeader(controller: controller)
            else
              _SpaceChatListHeader(
                space: activeSpaceRoom,
                onBack: controller.clearActiveSpace,
                onOpenDirectory: () => controller.setSpaceDirectoryOpen(true),
              ),
            SliverList(
              delegate: SliverChildListDelegate([
                if (controller.isSearchMode) ...[
                  SearchTitle(
                    title: L10n.of(context).publicRooms,
                    icon: const Icon(Icons.explore_outlined),
                  ),
                  PublicRoomsHorizontalList(publicRooms: publicRooms),
                  SearchTitle(
                    title: L10n.of(context).publicSpaces,
                    icon: const Icon(Icons.workspaces_outlined),
                  ),
                  PublicRoomsHorizontalList(publicRooms: publicSpaces),
                  SearchTitle(
                    title: L10n.of(context).users,
                    icon: const Icon(Icons.group_outlined),
                  ),
                  AnimatedContainer(
                    clipBehavior: Clip.hardEdge,
                    decoration: const BoxDecoration(),
                    height:
                        userSearchResult == null ||
                            userSearchResult.results.isEmpty
                        ? 0
                        : 106,
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    child: userSearchResult == null
                        ? null
                        : ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: userSearchResult.results.length,
                            itemBuilder: (context, i) => _SearchItem(
                              title:
                                  userSearchResult.results[i].displayName ??
                                  userSearchResult
                                      .results[i]
                                      .userId
                                      .localpart ??
                                  L10n.of(context).unknownDevice,
                              avatar: userSearchResult.results[i].avatarUrl,
                              onPressed: () => UserDialog.show(
                                context: context,
                                profile: userSearchResult.results[i],
                              ),
                            ),
                          ),
                  ),
                ],
                if (client.rooms.isNotEmpty && !controller.isSearchMode)
                  Container(
                    height: 36 + 8 + 8,
                    padding: EdgeInsets.symmetric(vertical: 8),
                    child: ListView(
                      padding: const EdgeInsets.symmetric(horizontal: 12.0),
                      shrinkWrap: true,
                      scrollDirection: Axis.horizontal,
                      children: [
                        ...ActiveFilter.values
                            .where((filter) => filter != ActiveFilter.tag)
                            .map(
                              (filter) => Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                ),
                                child: Center(
                                  child: FilterChip(
                                    selected: filter == controller.activeFilter,
                                    onSelected: (_) => controller
                                        .setActiveFilter(filter, null),
                                    label: Text(
                                      filter.toLocalizedString(context),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                        ...controller.roomTags.entries.map(
                          (entry) => Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 4.0,
                            ),
                            child: Center(
                              child: FilterChip(
                                selected: entry.key == controller.activeTag,
                                onSelected: (_) => controller.setActiveFilter(
                                  ActiveFilter.tag,
                                  entry.key,
                                ),
                                label: Text(entry.key.replaceFirst('u.', '')),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                if (controller.isSearchMode)
                  SearchTitle(
                    title: L10n.of(context).chats,
                    icon: const Icon(Icons.forum_outlined),
                  ),
                if (client.prevBatch != null &&
                    rooms.isEmpty &&
                    !controller.isSearchMode) ...[
                  Column(
                    mainAxisAlignment: .center,
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          const Column(
                            mainAxisSize: .min,
                            children: [
                              DummyChatListItem(opacity: 0.5, animate: false),
                              DummyChatListItem(opacity: 0.3, animate: false),
                            ],
                          ),
                          Icon(
                            CupertinoIcons.chat_bubble_text_fill,
                            size: 128,
                            color: theme.colorScheme.secondary,
                          ),
                        ],
                      ),
                      Padding(
                        padding: const EdgeInsets.all(16.0),
                        child: Text(
                          client.rooms.isEmpty
                              ? L10n.of(context).noChatsFoundHere
                              : L10n.of(context).noMoreChatsFound,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 18,
                            color: theme.colorScheme.secondary,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ]),
            ),
            if (client.prevBatch == null)
              SliverList(
                delegate: SliverChildBuilderDelegate(
                  (context, i) => DummyChatListItem(
                    opacity: (dummyChatCount - i) / dummyChatCount,
                    animate: true,
                  ),
                  childCount: dummyChatCount,
                ),
              ),
            if (client.prevBatch != null)
              SliverSafeArea(
                top: false,
                sliver: SliverList.builder(
                  itemCount: rooms.length,
                  itemBuilder: (BuildContext context, int i) {
                    final room = rooms[i];
                    final space = spaceDelegateCandidates[room.id];
                    return ChatListItem(
                      room,
                      space: space,
                      key: Key('chat_list_item_${room.id}'),
                      filter: filter,
                      onTap: () => controller.onChatTap(room),
                      onLongPress: (context, [globalPosition]) =>
                          controller.chatContextAction(
                            room,
                            context,
                            space,
                            globalPosition,
                          ),
                      activeChat: controller.activeChat == room.id,
                    );
                  },
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The chats of [space] and of the spaces directly inside it, matching the
/// two levels the space's room directory shows.
Set<String> _roomIdsInSpace(Client client, Room space) {
  final roomIds = <String>{};
  for (final child in space.spaceChildren) {
    final roomId = child.roomId;
    if (roomId == null) continue;
    final room = client.getRoomById(roomId);
    if (room != null && room.isSpace) {
      roomIds.addAll(room.spaceChildren.map((child) => child.roomId).nonNulls);
    } else {
      roomIds.add(roomId);
    }
  }
  return roomIds;
}

/// Heads the chat list while it is filtered to a space: the space's name, a
/// way back to all chats, and a way into the space's room directory.
class _SpaceChatListHeader extends StatelessWidget {
  final Room space;
  final void Function() onBack;
  final void Function() onOpenDirectory;

  const _SpaceChatListHeader({
    required this.space,
    required this.onBack,
    required this.onOpenDirectory,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final displayname = space.getLocalizedDisplayname();
    return SliverAppBar(
      floating: true,
      toolbarHeight: 72,
      scrolledUnderElevation: 0,
      backgroundColor: Colors.transparent,
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: MaterialLocalizations.of(context).backButtonTooltip,
        icon: const Icon(Icons.arrow_back),
        onPressed: onBack,
      ),
      titleSpacing: 0,
      title: Row(
        children: [
          Avatar(
            size: Avatar.defaultSize / 1.5,
            mxContent: space.avatar,
            name: displayname,
            shapeBorder: RoundedSuperellipseBorder(
              side: BorderSide(width: 1, color: theme.dividerColor),
              borderRadius: BorderRadius.circular(AppConfig.spaceBorderRadius),
            ),
            borderRadius: BorderRadius.circular(AppConfig.spaceBorderRadius),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              displayname,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        ],
      ),
      actions: [
        IconButton(
          tooltip: L10n.of(context).discover,
          icon: const Icon(Icons.explore_outlined),
          onPressed: onOpenDirectory,
        ),
        const SizedBox(width: 8),
      ],
    );
  }
}

class PublicRoomsHorizontalList extends StatelessWidget {
  const PublicRoomsHorizontalList({super.key, required this.publicRooms});

  final List<PublishedRoomsChunk>? publicRooms;

  @override
  Widget build(BuildContext context) {
    final publicRooms = this.publicRooms;
    return AnimatedContainer(
      clipBehavior: Clip.hardEdge,
      decoration: const BoxDecoration(),
      height: publicRooms == null || publicRooms.isEmpty ? 0 : 106,
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: publicRooms == null
          ? null
          : ListView.builder(
              scrollDirection: Axis.horizontal,
              itemCount: publicRooms.length,
              itemBuilder: (context, i) => _SearchItem(
                title:
                    publicRooms[i].name ??
                    publicRooms[i].canonicalAlias?.localpart ??
                    L10n.of(context).group,
                avatar: publicRooms[i].avatarUrl,
                onPressed: () => showAdaptiveDialog(
                  context: context,
                  barrierDismissible: true,
                  builder: (c) => PublicRoomDialog(
                    roomAlias:
                        publicRooms[i].canonicalAlias ?? publicRooms[i].roomId,
                    chunk: publicRooms[i],
                  ),
                ),
              ),
            ),
    );
  }
}

class _SearchItem extends StatelessWidget {
  final String title;
  final Uri? avatar;
  final void Function() onPressed;

  const _SearchItem({
    required this.title,
    this.avatar,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) => InkWell(
    onTap: onPressed,
    child: SizedBox(
      width: 84,
      child: Column(
        mainAxisSize: .min,
        children: [
          const SizedBox(height: 8),
          Avatar(mxContent: avatar, name: title),
          Padding(
            padding: const EdgeInsets.all(8.0),
            child: Text(
              title,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(fontSize: 12),
            ),
          ),
        ],
      ),
    ),
  );
}
