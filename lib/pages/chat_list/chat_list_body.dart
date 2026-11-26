// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/pages/chat_list/dummy_chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/hold_then_drag.dart';
import 'package:fluffychat/pages/chat_list/message_search_results.dart';
import 'package:fluffychat/pages/chat_list/pinned_order.dart';
import 'package:fluffychat/pages/chat_list/room_updates_builder.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/pages/chat_list/space_view.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/room_unread.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/public_room_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:fluffychat/widgets/merged_contacts/merge_suggestion_banner.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../widgets/adaptive_dialogs/user_dialog.dart';
import '../../widgets/matrix.dart';

class ChatListViewBody extends StatelessWidget {
  final ChatListController controller;

  const ChatListViewBody(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
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

    final publicRooms = controller.roomSearchResult?.chunk
        .where((room) => room.roomType != 'm.space')
        .toList();
    final publicSpaces = controller.roomSearchResult?.chunk
        .where((room) => room.roomType == 'm.space')
        .toList();
    final userSearchResult = controller.userSearchResult;
    final filter = controller.searchController.text.toLowerCase();
    // Only the parts that show room data listen to the sync, each through
    // its own RoomUpdatesBuilder. The header and the search results depend on
    // the controller alone, which rebuilds this whole widget when they change.
    return Stack(
      children: [
        _buildScrollView(
          context,
          client,
          activeSpaceRoom,
          publicRooms,
          publicSpaces,
          userSearchResult,
          filter,
        ),
        if (!controller.isSearchMode)
          Positioned(
            left: 0,
            right: 0,
            // Clear of the system gesture bar.
            bottom: MediaQuery.viewPaddingOf(context).bottom + 16,
            child: Center(child: _UnreadBelowChip(controller)),
          ),
        // Over the list, above New chat and the unread chip, while the app is
        // out of step with the server.
        Positioned(
          left: 0,
          right: 0,
          bottom: MediaQuery.viewPaddingOf(context).bottom + 16 + 56 + 12,
          child: const Center(child: SyncStatusToast()),
        ),
      ],
    );
  }

  Widget _buildScrollView(
    BuildContext context,
    Client client,
    Room? activeSpaceRoom,
    List<PublishedRoomsChunk>? publicRooms,
    List<PublishedRoomsChunk>? publicSpaces,
    SearchUserDirectoryResponse? userSearchResult,
    String filter,
  ) {
    final theme = Theme.of(context);
    const dummyChatCount = 4;
    final explore = MatrixFeatures.forClient(
      client,
    ).isRelevant(MatrixFeature.explore);
    final scrollView = CustomScrollView(
      // A different account starts from fresh tile state.
      key: ValueKey(client.userID.toString()),
      controller: controller.scrollController,
      slivers: [
        if (activeSpaceRoom == null || controller.selectionMode)
          ?controller.header
        else
          RoomUpdatesBuilder(
            client: client,
            builder: (context) => _SpaceChatListHeader(
              space: activeSpaceRoom,
              onBack: controller.clearActiveSpace,
              onOpenDirectory: () => controller.setSpaceDirectoryOpen(true),
            ),
          ),
        SliverList(
          delegate: SliverChildListDelegate([
            if (controller.isSearchMode) ...[
              if (explore || (publicRooms?.isNotEmpty ?? false)) ...[
                SearchTitle(
                  title: L10n.of(context).publicRooms,
                  icon: const Icon(Icons.explore_outlined),
                ),
                PublicRoomsHorizontalList(publicRooms: publicRooms),
              ],
              if (explore || (publicSpaces?.isNotEmpty ?? false)) ...[
                SearchTitle(
                  title: L10n.of(context).publicSpaces,
                  icon: const Icon(Icons.workspaces_outlined),
                ),
                PublicRoomsHorizontalList(publicRooms: publicSpaces),
              ],
              SearchTitle(
                title: L10n.of(context).users,
                icon: const Icon(Icons.group_outlined),
              ),
              AnimatedContainer(
                clipBehavior: Clip.hardEdge,
                decoration: const BoxDecoration(),
                height:
                    userSearchResult == null || userSearchResult.results.isEmpty
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
                              userSearchResult.results[i].userId.localpart ??
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
            // Under a title bar the selection bar takes the chip row's place
            // while chats are selected.
            if (!controller.isSearchMode &&
                !(controller.selectionMode &&
                    controller.titleBarSearch != null))
              // Shown once the account has any chat, which only a sync changes.
              RoomUpdatesBuilder(
                client: client,
                builder: (context) => client.rooms.isEmpty
                    ? const SizedBox.shrink()
                    : _ChipRow(
                        titleBar: controller.titleBarSearch != null,
                        child: ListView(
                          padding: const EdgeInsets.symmetric(horizontal: 12.0),
                          shrinkWrap: true,
                          scrollDirection: Axis.horizontal,
                          children: [
                            if (activeSpaceRoom == null)
                              Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 4.0,
                                ),
                                child: Center(
                                  child: _SourceFilterChip(controller),
                                ),
                              ),
                            ...ActiveFilter.values
                                .where(
                                  (filter) =>
                                      filter != ActiveFilter.tag &&
                                      // The first chip stands for all chats.
                                      (filter != ActiveFilter.allChats ||
                                          activeSpaceRoom != null),
                                )
                                .map(
                                  (filter) => Padding(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 4.0,
                                    ),
                                    child: Center(
                                      child: FilterChip(
                                        selected:
                                            filter == controller.activeFilter,
                                        onSelected: (_) => controller
                                            .setActiveFilter(filter, null),
                                        showCheckmark: false,
                                        onDeleted:
                                            filter == controller.activeFilter &&
                                                filter != ActiveFilter.allChats
                                            ? () => controller.setActiveFilter(
                                                ActiveFilter.allChats,
                                                null,
                                              )
                                            : null,
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
                                    showCheckmark: false,
                                    onDeleted: entry.key == controller.activeTag
                                        ? () => controller.setActiveFilter(
                                            ActiveFilter.allChats,
                                            null,
                                          )
                                        : null,
                                    onSelected: (_) =>
                                        controller.setActiveFilter(
                                          ActiveFilter.tag,
                                          entry.key,
                                        ),
                                    label: Text(
                                      entry.key.replaceFirst('u.', ''),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
              ),
            // Offers chats that look like the same person for merging.
            if (!controller.isSearchMode && activeSpaceRoom == null)
              MergeSuggestionBanner(client: client),
            if (controller.isSearchMode)
              SearchTitle(
                title: L10n.of(context).chats,
                icon: const Icon(Icons.forum_outlined),
              ),
          ]),
        ),
        RoomUpdatesBuilder(
          client: client,
          onUpdate: controller.markRoomsUpdated,
          builder: (context) {
            final spaceDelegateCandidates = <String, Room>{};
            for (final space in client.rooms.where((r) => r.isSpace)) {
              for (final spaceChild in space.spaceChildren) {
                final roomId = spaceChild.roomId;
                if (roomId == null) continue;
                spaceDelegateCandidates[roomId] = space;
              }
            }
            final sourceSpaceId = controller.sourceSpaceId;
            final sourceSpace = sourceSpaceId == null
                ? null
                : client.getRoomById(sourceSpaceId);
            final filterSpace = activeSpaceRoom ?? sourceSpace;
            final spaceRoomIds = filterSpace == null
                ? null
                : _roomIdsInSpace(client, filterSpace);
            final hideRoomsInSpaces = AppSettings.hideRoomsInSpaces.value;
            // A merged contact is listed once and passes when any of its
            // rooms does (see MergedChatList).
            final rooms = controller.listedChats(
              (room) => spaceRoomIds != null
                  ? spaceRoomIds.contains(room.id)
                  : !hideRoomsInSpaces ||
                        spaceDelegateCandidates[room.id] == null,
            );

            // Rooms the search hides are left out here instead of being
            // built as empty tiles, so the list only builds what it shows.
            final matrixLocals = MatrixLocals(L10n.of(context));
            final shownRooms = filter.isEmpty
                ? List.of(rooms)
                : rooms
                      .where(
                        (room) => controller.listedChatMatches(
                          room,
                          filter,
                          matrixLocals,
                        ),
                      )
                      .toList();
            // Pinned chats sit in a row of large avatars above the list,
            // and are left out of the list itself. A search shows them as
            // normal rows so results stay in one place.
            final pinnedRooms = filter.isEmpty
                ? rooms.where(controller.listedChatIsPinned).toList()
                : const <Room>[];
            if (pinnedRooms.isNotEmpty) {
              shownRooms.removeWhere(controller.listedChatIsPinned);
            }
            // Lets the list find a tile's new index when its chat moves,
            // so the tile keeps its State instead of being rebuilt.
            // The unread chip reads the listed rooms after this frame.
            final listed = List<Room>.of(shownRooms);
            final hasPins = pinnedRooms.isNotEmpty;
            WidgetsBinding.instance.addPostFrameCallback((_) {
              controller.listedRooms.value = (rooms: listed, pins: hasPins);
              // A selected chat that left the list is no longer selected.
              controller.keepSelectedOnly([...listed, ...pinnedRooms]);
            });
            final roomIndexes = <String, int>{
              for (var i = 0; i < shownRooms.length; i++) shownRooms[i].id: i,
            };

            return SliverMainAxisGroup(
              slivers: [
                if (client.prevBatch != null &&
                    rooms.isEmpty &&
                    !controller.isSearchMode)
                  SliverToBoxAdapter(
                    child: Column(
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
                if (client.prevBatch != null && pinnedRooms.isNotEmpty)
                  SliverToBoxAdapter(
                    child: _PinnedRow(
                      rooms: pinnedRooms,
                      spaces: spaceDelegateCandidates,
                      controller: controller,
                    ),
                  ),
                if (client.prevBatch != null)
                  SliverSafeArea(
                    top: false,
                    sliver: SliverList.builder(
                      itemCount: shownRooms.length,
                      findChildIndexCallback: (key) => key is ValueKey<String>
                          ? roomIndexes[key.value]
                          : null,
                      itemBuilder: (BuildContext context, int i) {
                        final room = shownRooms[i];
                        return controller.chatListTile(
                          room,
                          spaceDelegateCandidates[room.id],
                          spaces: spaceDelegateCandidates,
                        );
                      },
                    ),
                  ),
                // Room past the last chat for the New chat button, which
                // floats over the bottom of the list: its 56 plus 16 on
                // either side, so the last row scrolls clear of it.
                if (client.prevBatch != null)
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 16 + 56 + 16),
                  ),
              ],
            );
          },
        ),
        if (controller.isSearchMode)
          MessageSearchResults(
            client: client,
            searchField: controller.searchController,
          ),
      ],
    );
    if (!FluffyThemes.isColumnMode(context)) return scrollView;
    // With a mouse the list has a scrollbar. It starts below the header,
    // which stays pinned in this layout, so the thumb never sits beside the
    // search field and account button.
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(context).copyWith(scrollbars: false),
      child: RawScrollbar(
        controller: controller.scrollController,
        thickness: 6,
        radius: const Radius.circular(3),
        thumbColor: theme.colorScheme.onSurface.withAlpha(70),
        padding: const EdgeInsets.only(top: 72 + 4, bottom: 4, right: 2),
        child: scrollView,
      ),
    );
  }
}

/// A chip at the bottom of the chat list that counts the unread chats below
/// the visible rows and scrolls to the next one when tapped. Row positions
/// are estimated from the two row heights the list uses, plus the copy code
/// button where a row shows one, which is close enough to count rows and to
/// land the next unread chat on screen.
class _UnreadBelowChip extends StatelessWidget {
  final ChatListController controller;

  const _UnreadBelowChip(this.controller);

  static const double _rowHeight = 68;
  static const double _unreadRowHeight = 89;
  static const double _headerHeight = 72 + 39;
  static const double _pinsHeight = 146;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: Listenable.merge([
        controller.scrollController,
        controller.listedRooms,
      ]),
      builder: (context, _) {
        final scroll = controller.scrollController;
        // The list reports no size until its first layout.
        if (!scroll.hasClients || !scroll.position.hasViewportDimension) {
          return const SizedBox.shrink();
        }
        final listed = controller.listedRooms.value;
        final bottom = scroll.offset + scroll.position.viewportDimension;
        var top = _headerHeight + (listed.pins ? _pinsHeight : 0);
        var below = 0;
        double? firstTop;
        for (final room in listed.rooms) {
          final contact = controller.mergedContactFor(room);
          final unread = contact?.isUnread ?? room.countsAsUnread;
          final height =
              ((contact?.notificationCount ?? room.notificationCount) >= 1
                  ? _unreadRowHeight
                  : _rowHeight) +
              controller.extraRowHeight(room);
          if (unread && top + height / 2 > bottom) {
            below++;
            firstTop ??= top;
          }
          top += height;
        }
        final target = firstTop;
        if (below == 0 || target == null) return const SizedBox.shrink();
        return ActionChip(
          avatar: Icon(
            Icons.arrow_downward,
            size: 16,
            color: theme.colorScheme.onPrimary,
          ),
          label: Text('$below ${L10n.of(context).unread.toLowerCase()}'),
          labelStyle: theme.textTheme.labelLarge?.copyWith(
            color: theme.colorScheme.onPrimary,
          ),
          backgroundColor: theme.colorScheme.primary,
          side: BorderSide.none,
          shape: const StadiumBorder(),
          elevation: 3,
          onPressed: () => scroll.animateTo(
            // Leaves the unread chat a third of the way down the screen.
            (target - scroll.position.viewportDimension / 3).clamp(
              0.0,
              scroll.position.maxScrollExtent,
            ),
            duration: FluffyThemes.animationDuration,
            curve: FluffyThemes.animationCurve,
          ),
        );
      },
    );
  }
}

/// The pinned chats as one row that scrolls sideways, in the order the user
/// gave them (see `pinned_order.dart`). Holding a pin still selects it;
/// moving it after the hold drags it to a new place in the row. While
/// unread pins lie beyond the right edge, a count on that edge says so and
/// scrolls to the next one when tapped.
class _PinnedRow extends StatefulWidget {
  final List<Room> rooms;
  final Map<String, Room> spaces;
  final ChatListController controller;

  const _PinnedRow({
    required this.rooms,
    required this.spaces,
    required this.controller,
  });

  @override
  State<_PinnedRow> createState() => _PinnedRowState();
}

class _PinnedRowState extends State<_PinnedRow> {
  static const double _itemWidth = 104;

  /// How far the avatars of the chat list below start from the edge: the
  /// tile's 8dp margin plus its 8dp content padding (see `ChatListItem`).
  static const double _listAvatarInset = 16;

  /// Lines the first avatar up with the list avatars below. Each avatar is
  /// centred in its item, so the padding is the inset less the space beside
  /// the avatar.
  static const double _sidePadding =
      _listAvatarInset - (_itemWidth - _PinnedChat._avatarSize) / 2;

  final _scrollController = ScrollController();

  /// The width each pin takes and the padding at either end, as laid out
  /// last. Pins that fit share the row's width evenly, so they sit centred;
  /// pins that do not fit take [_itemWidth] each and start level with the
  /// list avatars below, scrolling sideways.
  double _extent = _itemWidth;
  double _padding = _sidePadding;

  /// How many unread pins are fully or partly past the right edge.
  final _hiddenUnread = ValueNotifier<int>(0);

  /// The row positions of the unread pins, in row order.
  List<int> _unreadIndexes = const [];

  /// Whether a pin is being dragged, which hides the unread count.
  bool _dragging = false;

  /// Orders written by a drop but not yet back from the server, by room
  /// ID, with the order the room had before. One is dropped as soon as the
  /// room's stored order differs from that earlier order, whichever device
  /// changed it.
  final Map<String, ({double? before, double order})> _sentOrders = {};

  late final AppLifecycleListener _lifecycle;
  GoRouterDelegate? _router;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_updateHiddenUnread);
    _lifecycle = AppLifecycleListener(onResume: _scrollToStart);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final router = GoRouter.of(context).routerDelegate;
    if (router == _router) return;
    _router?.removeListener(_scrollToStart);
    _router = router..addListener(_scrollToStart);
  }

  /// The row starts over from its first pin whenever the user comes back to
  /// it: on every navigation and when the app returns to the foreground.
  void _scrollToStart() {
    if (_scrollController.hasClients) _scrollController.jumpTo(0);
  }

  @override
  void dispose() {
    _router?.removeListener(_scrollToStart);
    _lifecycle.dispose();
    _scrollController.dispose();
    _hiddenUnread.dispose();
    super.dispose();
  }

  /// The first row position that is not fully on screen.
  int _firstCutOff() {
    final position = _scrollController.position;
    final rightEdge = position.pixels + position.viewportDimension;
    return ((rightEdge - _padding) / _extent).floor();
  }

  void _updateHiddenUnread() {
    if (!_scrollController.hasClients) return;
    final cutOff = _firstCutOff();
    _hiddenUnread.value = _unreadIndexes.where((i) => i >= cutOff).length;
  }

  /// Scrolls the next unread pin past the right edge fully into view.
  void _showNextHiddenUnread() {
    final cutOff = _firstCutOff();
    final next = _unreadIndexes.firstWhere(
      (i) => i >= cutOff,
      orElse: () => -1,
    );
    if (next == -1) return;
    final position = _scrollController.position;
    _scrollController.animateTo(
      (2 * _padding + (next + 1) * _extent - position.viewportDimension).clamp(
        0.0,
        position.maxScrollExtent,
      ),
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
    );
  }

  /// The order a pinned room has in the row: one this row sent while the
  /// server has not answered, else the stored one.
  double? _roomOrder(Room room) =>
      _sentOrders[room.id]?.order ?? storedPinOrder(room);

  /// The order of a listed chat: the lowest of its pinned rooms' orders.
  double? _chatOrder(Room room) => lowestPinOrder(
    pinnedRoomsOf(
      room,
      widget.controller.mergedContactFor(room),
    ).map(_roomOrder),
  );

  /// Stores the order of the row after a pin moved from [from] to [to], on
  /// every pinned room of each chat whose order changes.
  void _onReorder(List<Room> sorted, int from, int to) {
    final orders = sorted.map(_chatOrder).toList();
    final moved = List.of(sorted);
    moved.insert(to, moved.removeAt(from));
    final writes = pinOrdersAfterMove(orders, from, to);
    final sent = <Room>[];
    final futures = <Future<void>>[];
    for (final MapEntry(key: index, value: order) in writes.entries) {
      final chat = moved[index];
      for (final room in pinnedRoomsOf(
        chat,
        widget.controller.mergedContactFor(chat),
      )) {
        _sentOrders[room.id] = (before: storedPinOrder(room), order: order);
        sent.add(room);
        futures.add(room.addTag(TagType.favourite, order: order));
      }
    }
    setState(() {});
    Future.wait(futures).catchError((Object e, StackTrace s) {
      Logs().w('Could not store the order of the pinned chats', e, s);
      if (!mounted) return const <void>[];
      setState(() {
        for (final room in sent) {
          _sentOrders.remove(room.id);
        }
      });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).oopsSomethingWentWrong)),
      );
      return const <void>[];
    });
  }

  /// The dragged pin, lifted a little off the row.
  Widget _decorateDragged(Widget child, int index, Animation<double> lift) =>
      AnimatedBuilder(
        animation: lift,
        builder: (context, child) => Transform.scale(
          scale: 1 + 0.1 * Curves.easeOut.transform(lift.value),
          child: child,
        ),
        child: Material(type: MaterialType.transparency, child: child),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final controller = widget.controller;
    for (final room in widget.rooms) {
      for (final pinned in pinnedRoomsOf(
        room,
        controller.mergedContactFor(room),
      )) {
        final sent = _sentOrders[pinned.id];
        if (sent != null && storedPinOrder(pinned) != sent.before) {
          _sentOrders.remove(pinned.id);
        }
      }
    }
    final sorted = sortPins(widget.rooms, _chatOrder);
    _unreadIndexes = [
      for (var i = 0; i < sorted.length; i++)
        if (controller.listedChatIsUnread(sorted[i])) i,
    ];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _updateHiddenUnread();
    });

    return SizedBox(
      height: 146,
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final fits =
                  sorted.isNotEmpty &&
                  2 * _sidePadding + sorted.length * _itemWidth <=
                      constraints.maxWidth;
              _extent = fits
                  ? constraints.maxWidth / sorted.length
                  : _itemWidth;
              _padding = fits ? 0 : _sidePadding;
              return ReorderableList(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                // Extra room above for the unread preview bubbles.
                padding: EdgeInsets.fromLTRB(_padding, 26, _padding, 8),
                itemExtent: _extent,
                itemCount: sorted.length,
                onReorderStart: (_) => setState(() => _dragging = true),
                onReorderEnd: (_) => setState(() => _dragging = false),
                onReorderItem: (from, to) => _onReorder(sorted, from, to),
                proxyDecorator: _decorateDragged,
                itemBuilder: (context, i) => _PinnedChat(
                  key: ValueKey(sorted[i].id),
                  index: i,
                  room: sorted[i],
                  space: widget.spaces[sorted[i].id],
                  spaces: widget.spaces,
                  contact: controller.mergedContactFor(sorted[i]),
                  controller: controller,
                ),
              );
            },
          ),
          Positioned(
            right: 0,
            top: 0,
            bottom: 0,
            child: ValueListenableBuilder(
              valueListenable: _hiddenUnread,
              builder: (context, hidden, _) => hidden == 0 || _dragging
                  ? const SizedBox.shrink()
                  : GestureDetector(
                      onTap: _showNextHiddenUnread,
                      child: Container(
                        width: 44,
                        alignment: Alignment.centerRight,
                        // Level with the middle of the avatars, which sit above
                        // their names.
                        padding: const EdgeInsets.only(right: 8, bottom: 4),
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            colors: [
                              theme.colorScheme.surface.withAlpha(0),
                              theme.colorScheme.surface,
                            ],
                          ),
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            borderRadius: BorderRadius.circular(99),
                          ),
                          child: Text(
                            '$hidden',
                            style: theme.textTheme.labelSmall?.copyWith(
                              color: theme.colorScheme.onPrimary,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ],
      ),
    );
  }
}

/// A pinned chat in the row above the list: a large avatar with the chat's
/// name under it, and a dot before the name while it has unread messages.
class _PinnedChat extends StatelessWidget {
  final Room room;
  final Room? space;

  /// Set when [room] stands for a merged contact, which then shows with its
  /// own name and avatar and a badge per network from [spaces].
  final MergedContact? contact;
  final Map<String, Room> spaces;
  final ChatListController controller;

  /// The chat's position in the row, for dragging it.
  final int index;

  const _PinnedChat({
    required this.index,
    required this.room,
    required this.space,
    required this.controller,
    this.contact,
    this.spaces = const {},
    super.key,
  });

  static const double _avatarSize = 76;

  /// Hands a press to the row's reordering: a hold selects the chat as a
  /// long press does, and moving after it lifts the chat to drag it, with
  /// the selection put back as it was.
  void _startDrag(BuildContext context, PointerDownEvent event) {
    final list = SliverReorderableList.maybeOf(context);
    if (list == null) return;
    list.startItemDragReorder(
      index: index,
      event: event,
      recognizer: HoldThenDragGestureRecognizer(
        debugOwner: this,
        onHold: () {
          Feedback.forLongPress(context);
          controller.toggleSelection(room);
        },
        onLift: () {
          controller.toggleSelection(room);
          HapticFeedback.selectionClick();
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locals = MatrixLocals(L10n.of(context));
    final contact = this.contact;
    final name =
        contact?.displayName(locals) ?? room.getLocalizedDisplayname(locals);
    final unread = contact?.isUnread ?? room.countsAsUnread;
    final space = this.space;
    final selected = controller.isSelected(room);
    final preview = unread
        ? (contact?.lastEvent ?? room.lastEvent)
              ?.calcLocalizedBody(
                locals,
                hideReply: true,
                hideEdit: true,
                plaintextBody: true,
                removeMarkdown: true,
              )
              .trim()
              .replaceAll('\n', ' ')
        : null;
    return Center(
      child: Semantics(
        onLongPress: () => controller.toggleSelection(room),
        child: Listener(
          onPointerDown: (event) => _startDrag(context, event),
          child: InkWell(
            borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            onTap: () => controller.onListedChatTap(room),
            onSecondaryTap: () => controller.toggleSelection(room),
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 4),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SelectableAvatar(
                        selected: selected,
                        size: _avatarSize,
                        // A group without a picture shows its members.
                        child: contact == null && GroupAvatar.shows(room)
                            ? GroupAvatar(
                                room: room,
                                name: name,
                                size: _avatarSize,
                              )
                            : Avatar(
                                mxContent: contact?.avatar ?? room.avatar,
                                name: name,
                                size: _avatarSize,
                                presenceUserId: (contact?.sendViaRoom ?? room)
                                    .directChatMatrixID,
                              ),
                      ),
                      // An unread pin shows its newest message in a small speech
                      // bubble over the top of the avatar.
                      if (preview != null)
                        Positioned(
                          top: -14,
                          left: -10,
                          right: -10,
                          child: Center(
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color:
                                    theme.colorScheme.surfaceContainerHighest,
                                borderRadius: BorderRadius.circular(12),
                                boxShadow: [
                                  BoxShadow(
                                    color: theme.colorScheme.shadow.withAlpha(
                                      60,
                                    ),
                                    blurRadius: 4,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Text(
                                preview,
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                textAlign: TextAlign.center,
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: theme.colorScheme.onSurface,
                                  height: 1.15,
                                ),
                              ),
                            ),
                          ),
                        ),
                      // A selected chat shows only the check, without badges.
                      if (selected || !AppSettings.chatListNetworkBadges.value)
                        const SizedBox.shrink()
                      else if (contact != null)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: MergedBadge(
                            contact: contact,
                            size: 24,
                            outlineColor: theme.colorScheme.surface,
                          ),
                        )
                      else if (space != null)
                        Positioned(
                          right: -2,
                          bottom: -2,
                          child: Avatar(
                            shapeBorder: RoundedSuperellipseBorder(
                              side: BorderSide(
                                width: 2,
                                color: theme.colorScheme.surface,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.spaceBorderRadius * 0.5,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(
                              AppConfig.spaceBorderRadius * 0.5,
                            ),
                            mxContent: space.avatar,
                            size: 24,
                            name: space.getLocalizedDisplayname(locals),
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (unread)
                        Container(
                          width: 8,
                          height: 8,
                          margin: const EdgeInsets.only(right: 4),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.primary,
                            shape: BoxShape.circle,
                          ),
                        ),
                      Flexible(
                        child: Text(
                          name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontWeight: unread ? FontWeight.w700 : null,
                            color: unread ? theme.colorScheme.onSurface : null,
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The first filter chip. It reads "All" with a dropdown arrow and opens the
/// list of sources: spaces, which for bridged networks are the networks
/// themselves. With a source chosen it shows that source's icon and name and
/// a clear button.
/// The row of filter chips above the chats. Under a title bar that holds
/// the search field it is the list's first row: 48 high, with 32 high chips
/// 16 in from the edge, 8 apart and 8 from the corner of each.
class _ChipRow extends StatelessWidget {
  final bool titleBar;
  final Widget child;

  const _ChipRow({required this.titleBar, required this.child});

  @override
  Widget build(BuildContext context) {
    if (!titleBar) {
      return Container(
        // 1 above and 2 below leaves the same 16 between the search field,
        // the chips and the first chat, given the padding those two already
        // carry.
        height: 36 + 1 + 2,
        padding: const EdgeInsets.only(top: 1, bottom: 2),
        child: child,
      );
    }
    final theme = Theme.of(context);
    return Theme(
      data: theme.copyWith(
        materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
        chipTheme: theme.chipTheme.copyWith(
          // 6 above and below a 20 high label makes the chip 32 high; 8
          // more to the side than the label's own 8 puts the label 16 in.
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        ),
      ),
      child: Container(
        height: 48,
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: child,
      ),
    );
  }
}

class _SourceFilterChip extends StatelessWidget {
  final ChatListController controller;

  const _SourceFilterChip(this.controller);

  Future<void> _openMenu(BuildContext context, Room? selected) async {
    final client = Matrix.of(context).client;
    final locals = MatrixLocals(L10n.of(context));
    final box = context.findRenderObject()! as RenderBox;
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final origin = box.localToGlobal(
      Offset(0, box.size.height + 4),
      ancestor: overlay,
    );
    final picked = await showMenu<String>(
      context: context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy,
        overlay.size.width - origin.dx,
        0,
      ),
      // Material menu metrics: 48 high rows, 12 side padding, and a width
      // that follows the longest row between 112 and 280.
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
      items: [
        _sourceItem(
          value: '',
          leading: const Icon(Icons.forum_outlined, size: 24),
          label: L10n.of(context).all,
          selected: selected == null,
        ),
        for (final space in controller.spaces)
          _sourceItem(
            value: space.id,
            leading: _spaceAvatar(space, locals, 24),
            label: space.getLocalizedDisplayname(locals),
            selected: space.id == selected?.id,
          ),
      ],
    );
    if (picked == null) return;
    controller.setSourceSpace(
      picked.isEmpty ? null : client.getRoomById(picked)?.id,
    );
  }

  static PopupMenuItem<String> _sourceItem({
    required String value,
    required Widget leading,
    required String label,
    required bool selected,
  }) => PopupMenuItem(
    value: value,
    height: 48,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Row(
      children: [
        leading,
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 12),
        // Keeps every row the same width whether or not it is checked.
        SizedBox(
          width: 24,
          child: selected ? const Icon(Icons.check, size: 20) : null,
        ),
      ],
    ),
  );

  static Widget _spaceAvatar(Room space, MatrixLocals locals, double size) =>
      Avatar(
        mxContent: space.avatar,
        name: space.getLocalizedDisplayname(locals),
        size: size,
        borderRadius: BorderRadius.circular(size / 4),
      );

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final selectedId = controller.sourceSpaceId;
    final selected = selectedId == null ? null : client.getRoomById(selectedId);
    final locals = MatrixLocals(L10n.of(context));
    final hasSources = controller.spaces.isNotEmpty;

    return FilterChip(
      // Lit while nothing narrows the list further, or a source is chosen.
      selected:
          selected != null || controller.activeFilter == ActiveFilter.allChats,
      showCheckmark: false,
      onSelected: (_) {
        if (controller.activeFilter != ActiveFilter.allChats &&
            selected == null) {
          controller.setActiveFilter(ActiveFilter.allChats, null);
          return;
        }
        if (hasSources) _openMenu(context, selected);
      },
      onDeleted: selected == null
          ? null
          : () => controller.setSourceSpace(null),
      avatar: selected == null ? null : _spaceAvatar(selected, locals, 20),
      label: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Text(
              selected?.getLocalizedDisplayname(locals) ?? L10n.of(context).all,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          if (selected == null && hasSources)
            const Icon(Icons.arrow_drop_down, size: 18),
        ],
      ),
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
        // A bridge's space holds only its own chats: nothing to discover.
        if (MatrixFeatures.forClient(
          space.client,
        ).isRelevant(MatrixFeature.spaces))
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
