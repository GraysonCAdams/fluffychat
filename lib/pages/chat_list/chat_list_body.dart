// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_filter_menu.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/pages/chat_list/chat_list_swipe.dart';
import 'package:fluffychat/pages/chat_list/dummy_chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/floating_control_transition.dart';
import 'package:fluffychat/pages/chat_list/hold_then_drag.dart';
import 'package:fluffychat/pages/chat_list/message_search_results.dart';
import 'package:fluffychat/pages/chat_list/pinned_order.dart';
import 'package:fluffychat/pages/chat_list/room_updates_builder.dart';
import 'package:fluffychat/pages/chat_list/scroll_to_top_button.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/pages/chat_list/space_view.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/room_unread.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/public_room_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:fluffychat/widgets/merged_contacts/merge_suggestion_banner.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:flutter/rendering.dart';
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
        // Near the top, 8 below the bar that heads the list (the button
        // has 4 of room for its shadow), and so well away from New chat,
        // the unread chip and the sync toast at the bottom.
        Positioned.fill(
          child: _BelowHeader(
            headerKey: controller.headerKey,
            scrollController: controller.scrollController,
            minTop: MediaQuery.paddingOf(context).top,
            gap: 4,
            child: ScrollToTopButton(controller: controller.scrollController),
          ),
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
    final header = activeSpaceRoom == null || controller.selectionMode
        ? controller.header
        : RoomUpdatesBuilder(
            client: client,
            builder: (context) => _SpaceChatListHeader(
              controller: controller,
              space: activeSpaceRoom,
              onBack: controller.clearActiveSpace,
              onOpenDirectory: () => controller.setSpaceDirectoryOpen(true),
            ),
          );
    final scrollView = CustomScrollView(
      // A different account starts from fresh tile state.
      key: ValueKey(client.userID.toString()),
      controller: controller.scrollController,
      slivers: [
        // Keyed so the back to top button can follow the bar's height on
        // screen (see _BelowHeader).
        if (header != null)
          KeyedSubtree(key: controller.headerKey, child: header),
        _SearchFade(
          searching: controller.isSearchMode,
          slivers: [
            SliverList(
              delegate: SliverChildListDelegate([
                // Offers chats that look like the same person for merging.
                if (!controller.isSearchMode && activeSpaceRoom == null)
                  MergeSuggestionBanner(client: client),
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
                  for (var i = 0; i < shownRooms.length; i++)
                    shownRooms[i].id: i,
                };

                return SliverMainAxisGroup(
                  slivers: [
                    if (controller.isSearchMode &&
                        (shownRooms.isNotEmpty || pinnedRooms.isNotEmpty))
                      SliverToBoxAdapter(
                        child: SearchTitle(title: L10n.of(context).chats),
                      ),
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
                                    DummyChatListItem(
                                      opacity: 0.5,
                                      animate: false,
                                    ),
                                    DummyChatListItem(
                                      opacity: 0.3,
                                      animate: false,
                                    ),
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
                          findChildIndexCallback: (key) =>
                              key is ValueKey<String>
                              ? roomIndexes[key.value]
                              : null,
                          itemBuilder: (BuildContext context, int i) {
                            final room = shownRooms[i];
                            final tile = controller.chatListTile(
                              room,
                              spaceDelegateCandidates[room.id],
                              spaces: spaceDelegateCandidates,
                            );
                            return ValueListenableBuilder(
                              key: ValueKey(room.id),
                              valueListenable: swipeActionsChanged,
                              builder: (context, _, _) {
                                final swipe = chatSwipeActions(
                                  controller,
                                  room,
                                );
                                return ChatListSwipe(
                                  right: swipe.right,
                                  left: swipe.left,
                                  child: tile,
                                );
                              },
                            );
                          },
                        ),
                      ),
                    // Room past the last chat for the New chat button, which
                    // floats over the bottom of the list: its 56 plus 16 on
                    // either side, so the last row scrolls clear of it. The
                    // button shows only outside search and spaces (see
                    // ChatListView), so the room does too.
                    if (client.prevBatch != null &&
                        !controller.isSearchMode &&
                        controller.activeSpaceId == null)
                      const SliverToBoxAdapter(
                        child: SizedBox(height: 16 + 56 + 16),
                      ),
                  ],
                );
              },
            ),
            // The directory results come from the server after the chats,
            // which are found at once, so they go below them instead of
            // pushing them down when they arrive.
            if (controller.isSearchMode) ...[
              if (explore) ...[
                _SearchSection(
                  key: ValueKey(('people', filter)),
                  title: L10n.of(context).chatListPeople,
                  rows: [
                    for (final profile
                        in userSearchResult?.results ?? <Profile>[])
                      _UserResultTile(client: client, profile: profile),
                  ],
                ),
              ],
              _SearchSection(
                key: ValueKey(('rooms', filter)),
                title: L10n.of(context).publicRooms,
                rows: [
                  for (final chunk in publicRooms ?? <PublishedRoomsChunk>[])
                    _PublicRoomResultTile(chunk: chunk),
                ],
              ),
              _SearchSection(
                key: ValueKey(('spaces', filter)),
                title: L10n.of(context).publicSpaces,
                rows: [
                  for (final chunk in publicSpaces ?? <PublishedRoomsChunk>[])
                    _PublicRoomResultTile(chunk: chunk, space: true),
                ],
              ),
              MessageSearchResults(
                client: client,
                searchField: controller.searchController,
              ),
            ],
          ],
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
/// land the next unread chat on screen. It comes and goes with
/// [FloatingControlTransition].
class _UnreadBelowChip extends StatelessWidget {
  final ChatListController controller;

  const _UnreadBelowChip(this.controller);

  static const double _rowHeight = 68;
  static const double _unreadRowHeight = 89;
  static const double _headerHeight = 72;
  static const double _pinsHeight = _PinnedRow.height;

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
          return const FloatingControlTransition(visible: false, child: null);
        }
        final listed = controller.listedRooms.value;
        final bottom = scroll.offset + scroll.position.viewportDimension;
        // Under a title bar the list has no header.
        final header = controller.titleBarSearch == null ? _headerHeight : 0.0;
        var top = header + (listed.pins ? _pinsHeight : 0);
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
        if (below == 0 || target == null) {
          return const FloatingControlTransition(visible: false, child: null);
        }
        return FloatingControlTransition(
          visible: true,
          child: ActionChip(
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
  /// The row's height: 30 above the pins for the bubbles, the pins, and 8
  /// below.
  static const double height = 150;

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
  /// The slot each pin takes in a row that scrolls: 36 between avatars,
  /// which keeps the widest bubbles 16 apart.
  static const double _itemWidth = 112;

  /// How far the avatars of the chat list below start from the edge: the
  /// tile's 8dp margin plus its 8dp content padding (see `ChatListItem`).
  static const double _listAvatarInset = 16;

  /// How far a pin in a row that scrolls sits left of its slot's centre,
  /// so the first avatar lines up with the list avatars below: half the
  /// space beside an avatar is 18, 2 more than the inset, and a list's
  /// padding cannot be negative. The extra room is all between pins.
  static const double _shift =
      (_itemWidth - _PinnedChat._avatarSize) / 2 - _listAvatarInset;

  final _scrollController = ScrollController();

  /// The width each pin takes, as laid out last. Pins that fit share the
  /// row's width evenly, so they sit centred; pins that do not fit take
  /// [_itemWidth] each and start level with the list avatars below,
  /// scrolling sideways.
  double _extent = _itemWidth;

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
    return (rightEdge / _extent).floor();
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
      ((next + 1) * _extent - position.viewportDimension).clamp(
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
      height: _PinnedRow.height,
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              final fits =
                  sorted.isNotEmpty &&
                  sorted.length * _itemWidth - 2 * _shift <=
                      constraints.maxWidth;
              _extent = fits
                  ? constraints.maxWidth / sorted.length
                  : _itemWidth;
              return ReorderableList(
                controller: _scrollController,
                scrollDirection: Axis.horizontal,
                // Extra room above for the unread preview bubbles.
                padding: const EdgeInsets.only(top: 30, bottom: 8),
                itemExtent: _extent,
                itemCount: sorted.length,
                onReorderStart: (_) => setState(() => _dragging = true),
                onReorderEnd: (_) => setState(() => _dragging = false),
                onReorderItem: (from, to) => _onReorder(sorted, from, to),
                proxyDecorator: _decorateDragged,
                itemBuilder: (context, i) => _PinnedChat(
                  key: ValueKey(sorted[i].id),
                  shift: fits ? 0 : _shift,
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
/// name under it, in bold with its newest message in a bubble over the
/// avatar while it has unread messages.
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

  /// How far the pin sits towards the start of its slot from the centre.
  final double shift;

  const _PinnedChat({
    required this.index,
    this.shift = 0,
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
    final notificationCount =
        contact?.notificationCount ?? room.notificationCount;
    final space = this.space;
    final selected = controller.isSelected(room);
    final lastEvent = contact?.lastEvent ?? room.lastEvent;
    // An effect that hides the message hides it here too.
    final preview = unread && lastEvent != null
        ? effectPreviewOf(lastEvent, L10n.of(context)) ??
              lastEvent
                  .calcLocalizedBody(
                    locals,
                    hideReply: true,
                    hideEdit: true,
                    plaintextBody: true,
                    removeMarkdown: true,
                  )
                  .trim()
                  .replaceAll('\n', ' ')
        : null;
    return Padding(
      padding: EdgeInsetsDirectional.only(end: 2 * shift),
      child: Center(
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
                          child: GroupAvatar.shows(contact?.sendViaRoom ?? room)
                              ? GroupAvatar(
                                  room: contact?.sendViaRoom ?? room,
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
                        // bubble over the top of the avatar, its tail pointing
                        // down at it.
                        if (preview != null)
                          Positioned(
                            top: -19,
                            left: -10,
                            right: -10,
                            child: Center(
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color: theme
                                          .colorScheme
                                          .surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(12),
                                      boxShadow: [
                                        BoxShadow(
                                          color: theme.colorScheme.shadow
                                              .withAlpha(60),
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
                                      style: theme.textTheme.labelSmall
                                          ?.copyWith(
                                            color: theme.colorScheme.onSurface,
                                            height: 1.15,
                                          ),
                                    ),
                                  ),
                                  _BubbleTail(
                                    color: theme
                                        .colorScheme
                                        .surfaceContainerHighest,
                                  ),
                                ],
                              ),
                            ),
                          ),
                        // A selected chat shows only the check, without badges.
                        if (selected ||
                            !AppSettings.chatListNetworkBadges.value)
                          const SizedBox.shrink()
                        else if (contact != null && contact.spansNetworks)
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
                    // An unread pin shows in its bold name and its bubble,
                    // so the name sits centred under the avatar with nothing
                    // before it. A screen reader hears it as the chat list
                    // tiles' unread count says it.
                    Semantics(
                      label: !unread
                          ? null
                          : notificationCount > 0
                          ? '${L10n.of(context).unread}: $notificationCount'
                          : L10n.of(context).unread,
                      child: Text(
                        name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodySmall?.copyWith(
                          fontWeight: unread ? FontWeight.w700 : null,
                          color: unread ? theme.colorScheme.onSurface : null,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The tail under a pin's speech bubble: a small triangle with a rounded
/// tip, in the bubble's color, pointing down at the avatar.
class _BubbleTail extends StatelessWidget {
  final Color color;

  const _BubbleTail({required this.color});

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: const Size(12, 6), painter: _BubbleTailPainter(color));
}

class _BubbleTailPainter extends CustomPainter {
  final Color color;

  const _BubbleTailPainter(this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width;
    final h = size.height;
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(w, 0)
      ..lineTo(w / 2 + 2, h - 1.5)
      ..quadraticBezierTo(w / 2, h + 0.5, w / 2 - 2, h - 1.5)
      ..close();
    canvas.drawPath(path, Paint()..color = color);
  }

  @override
  bool shouldRepaint(_BubbleTailPainter oldDelegate) =>
      oldDelegate.color != color;
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
  final ChatListController controller;
  final Room space;
  final void Function() onBack;
  final void Function() onOpenDirectory;

  const _SpaceChatListHeader({
    required this.controller,
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
      surfaceTintColor: Colors.transparent,
      backgroundColor: chatListBarColor(theme.colorScheme),
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
        // The space's name is the title here, so the filter menu opens
        // from a button, filled while a filter narrows the space's chats.
        Builder(
          builder: (context) {
            final filtered = controller.activeFilter != ActiveFilter.allChats;
            final label = L10n.of(
              context,
            ).filterChatsSelected(chatFilterLabel(context, controller));
            void open() => showChatFilterMenu(context, controller);
            return filtered
                ? IconButton.filledTonal(
                    tooltip: label,
                    icon: const Icon(Icons.filter_list),
                    onPressed: open,
                  )
                : IconButton(
                    tooltip: label,
                    icon: const Icon(Icons.filter_list),
                    onPressed: open,
                  );
          },
        ),
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

/// Places [child] centred, [gap] below the part of the list's top bar that
/// is on screen, and never above [minTop] (the status bar). The bar is the
/// sliver under [headerKey]: the header, which floats in and out as the
/// list scrolls, or the pinned selection bar. With no bar the child sits
/// [gap] below [minTop].
///
/// The bar's visible height is read from its sliver geometry when painting,
/// after the list has been laid out for the frame, so the child follows the
/// bar in the same frame. Every scroll of [scrollController] repaints it.
class _BelowHeader extends SingleChildRenderObjectWidget {
  final GlobalKey headerKey;
  final ScrollController scrollController;
  final double minTop;
  final double gap;

  const _BelowHeader({
    required this.headerKey,
    required this.scrollController,
    required this.minTop,
    required this.gap,
    required super.child,
  });

  @override
  _RenderBelowHeader createRenderObject(BuildContext context) =>
      _RenderBelowHeader(
        headerKey: headerKey,
        scrollController: scrollController,
        minTop: minTop,
        gap: gap,
      );

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBelowHeader renderObject,
  ) => renderObject
    ..headerKey = headerKey
    ..scrollController = scrollController
    ..minTop = minTop
    ..gap = gap;
}

class _RenderBelowHeader extends RenderBox
    with RenderObjectWithChildMixin<RenderBox> {
  _RenderBelowHeader({
    required this.headerKey,
    required ScrollController scrollController,
    required double minTop,
    required double gap,
  }) : _scrollController = scrollController,
       _minTop = minTop,
       _gap = gap;

  GlobalKey headerKey;

  ScrollController get scrollController => _scrollController;
  ScrollController _scrollController;
  set scrollController(ScrollController value) {
    if (value == _scrollController) return;
    if (attached) _scrollController.removeListener(markNeedsPaint);
    _scrollController = value;
    if (attached) _scrollController.addListener(markNeedsPaint);
    markNeedsPaint();
  }

  double _minTop;
  set minTop(double value) {
    if (value == _minTop) return;
    _minTop = value;
    markNeedsPaint();
  }

  double _gap;
  set gap(double value) {
    if (value == _gap) return;
    _gap = value;
    markNeedsPaint();
  }

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _scrollController.addListener(markNeedsPaint);
  }

  @override
  void detach() {
    _scrollController.removeListener(markNeedsPaint);
    super.detach();
  }

  /// Where the child goes this frame.
  Offset get _childOffset {
    final child = this.child!;
    final bar = headerKey.currentContext?.findRenderObject();
    final barHeight = bar is RenderSliver && bar.attached
        ? bar.geometry?.paintExtent ?? 0.0
        : 0.0;
    return Offset(
      (size.width - child.size.width) / 2,
      math.max(_minTop, barHeight) + _gap,
    );
  }

  @override
  void performLayout() {
    child!.layout(constraints.loosen(), parentUsesSize: true);
    size = constraints.biggest;
  }

  @override
  void paint(PaintingContext context, Offset offset) =>
      context.paintChild(child!, offset + _childOffset);

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      result.addWithPaintOffset(
        offset: _childOffset,
        position: position,
        hitTest: (result, transformed) =>
            child!.hitTest(result, position: transformed),
      );

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) {
    final offset = _childOffset;
    transform.translateByDouble(offset.dx, offset.dy, 0, 1);
  }
}

/// Fades the list's content in when a search starts or ends, so the
/// results and the chats replace each other without a cut. The old content
/// is gone at once, which keeps the two from showing through each other;
/// the new content fades in over 250 ms (medium 1) in Material's emphasized
/// decelerate easing.
class _SearchFade extends StatefulWidget {
  final bool searching;
  final List<Widget> slivers;

  const _SearchFade({required this.searching, required this.slivers});

  @override
  State<_SearchFade> createState() => _SearchFadeState();
}

class _SearchFadeState extends State<_SearchFade>
    with SingleTickerProviderStateMixin {
  late final AnimationController _fade = AnimationController(
    vsync: this,
    duration: Durations.medium1,
    value: 1,
  );

  late final Animation<double> _opacity = CurvedAnimation(
    parent: _fade,
    curve: Easing.emphasizedDecelerate,
  );

  @override
  void didUpdateWidget(_SearchFade oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searching != oldWidget.searching) _fade.forward(from: 0);
  }

  @override
  void dispose() {
    _fade.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SliverFadeTransition(
    opacity: _opacity,
    sliver: SliverMainAxisGroup(slivers: widget.slivers),
  );
}

/// A section of the search results from the server, such as the people in
/// the user directory: a heading and Material list rows, the first
/// [collapsedCount] of them until Show more is tapped. Nothing at all while
/// there are no rows.
class _SearchSection extends StatefulWidget {
  final String title;
  final List<Widget> rows;

  const _SearchSection({required this.title, required this.rows, super.key});

  static const collapsedCount = 5;

  @override
  State<_SearchSection> createState() => _SearchSectionState();
}

class _SearchSectionState extends State<_SearchSection> {
  bool _expanded = false;

  @override
  Widget build(BuildContext context) {
    final rows = widget.rows;
    if (rows.isEmpty) return const SliverToBoxAdapter();
    final collapsed = !_expanded && rows.length > _SearchSection.collapsedCount;
    return SliverList.list(
      children: [
        SearchTitle(title: widget.title),
        ...collapsed ? rows.take(_SearchSection.collapsedCount) : rows,
        if (collapsed)
          Align(
            alignment: AlignmentDirectional.centerStart,
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 4),
              child: TextButton(
                onPressed: () => setState(() => _expanded = true),
                child: Text(L10n.of(context).showMore),
              ),
            ),
          ),
      ],
    );
  }
}

/// A row of the search results: a Material two line list item on the
/// list's 16 insets, with the avatar the chat rows use so the names line up
/// with theirs, the title in body large and the supporting text in body
/// medium.
class _SearchResultTile extends StatelessWidget {
  final Widget leading;
  final String title;
  final String? subtitle;
  final VoidCallback onTap;

  const _SearchResultTile({
    required this.leading,
    required this.title,
    required this.onTap,
    this.subtitle,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: leading,
      title: Text(title, maxLines: 1, overflow: TextOverflow.ellipsis),
      titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
      subtitle: subtitle == null
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: onTap,
    );
  }
}

/// A person found in the server's user directory.
class _UserResultTile extends StatelessWidget {
  final Client client;
  final Profile profile;

  const _UserResultTile({required this.client, required this.profile});

  @override
  Widget build(BuildContext context) {
    final name =
        profile.displayName ??
        profile.userId.localpart ??
        L10n.of(context).unknownDevice;
    return _SearchResultTile(
      leading: Avatar(mxContent: profile.avatarUrl, name: name, client: client),
      title: name,
      subtitle: MatrixFeatures.forClient(client).userLabel(profile.userId),
      onTap: () => UserDialog.show(context: context, profile: profile),
    );
  }
}

/// A public room or space from the server's room directory.
class _PublicRoomResultTile extends StatelessWidget {
  final PublishedRoomsChunk chunk;
  final bool space;

  const _PublicRoomResultTile({required this.chunk, this.space = false});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final name = chunk.name ?? chunk.canonicalAlias?.localpart ?? l10n.group;
    return _SearchResultTile(
      leading: Avatar(
        mxContent: chunk.avatarUrl,
        name: name,
        borderRadius: space
            ? BorderRadius.circular(AppConfig.spaceBorderRadius)
            : null,
      ),
      title: name,
      subtitle: l10n.countParticipants(chunk.numJoinedMembers),
      onTap: () => showAdaptiveDialog(
        context: context,
        barrierDismissible: true,
        builder: (c) => PublicRoomDialog(
          roomAlias: chunk.canonicalAlias ?? chunk.roomId,
          chunk: chunk,
        ),
      ),
    );
  }
}
