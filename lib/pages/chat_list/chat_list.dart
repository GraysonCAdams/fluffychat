// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: experimental_member_use

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/pages/chat_list/chat_list_view.dart';
import 'package:fluffychat/pages/chat_list/merged_contact_actions.dart';
import 'package:fluffychat/pages/chat_list/merged_contact_list.dart';
import 'package:fluffychat/pages/chat_list/room_updates_builder.dart';
import 'package:fluffychat/pages/chat_list/title_bar_search.dart';
import 'package:fluffychat/utils/android_direct_share.dart';
import 'package:fluffychat/utils/android_share_targets.dart';
import 'package:fluffychat/utils/chat_windows/chat_windows.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/notification_snooze.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/room_unread.dart';
import 'package:fluffychat/utils/share_items.dart';
import 'package:fluffychat/utils/show_update_snackbar.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/gestures.dart' show kDoubleTapTimeout;
import 'package:flutter/services.dart';
import 'package:flutter_callkit_incoming/entities/entities.dart';
import 'package:flutter_callkit_incoming/flutter_callkit_incoming.dart';
import 'package:flutter_shortcuts_new/flutter_shortcuts_new.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:livekit_client/livekit_client.dart' as lk;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' as sdk;
import 'package:matrix/matrix.dart';
import 'package:receive_sharing_intent/receive_sharing_intent.dart';

import '../../../utils/account_bundles.dart';
import '../../config/setting_keys.dart';
import '../../utils/url_launcher.dart';
import '../../widgets/matrix.dart';

/// The chats of [space] and of the spaces directly inside it, matching the
/// two levels the space's room directory shows.
Set<String> roomIdsInSpace(Client client, Room space) {
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

enum ActiveFilter { allChats, unread, groups, messages, tag }

extension LocalizedActiveFilter on ActiveFilter {
  String toLocalizedString(BuildContext context) {
    switch (this) {
      case ActiveFilter.allChats:
        return L10n.of(context).all;
      // One-to-one chats. Named for the people in them, which keeps it
      // apart from the Messages section of the search.
      case ActiveFilter.messages:
        return L10n.of(context).chatListPeople;
      case ActiveFilter.unread:
        return L10n.of(context).unread;
      case ActiveFilter.groups:
        return L10n.of(context).groups;
      case ActiveFilter.tag:
        throw 'Tags should not directly be displayed!';
    }
  }
}

class ChatList extends StatefulWidget {
  final String? activeChat;
  final String? activeSpace;
  final bool displayNavigationRail;

  const ChatList({
    super.key,
    required this.activeChat,
    this.activeSpace,
    this.displayNavigationRail = false,
  });

  @override
  ChatListController createState() => ChatListController();
}

class ChatListController extends State<ChatList>
    with TickerProviderStateMixin, RouteAware {
  StreamSubscription? _intentDataStreamSubscription;

  StreamSubscription? _intentFileStreamSubscription;

  StreamSubscription? _callEventSubscription;

  late ActiveFilter activeFilter;
  String? activeTag;

  String? _activeSpaceId;

  String? get activeSpaceId => _activeSpaceId;

  Future<void> setActiveSpace(String spaceId) async {
    await Matrix.of(context).client.getRoomById(spaceId)!.postLoad();
    if (!mounted) return;
    if (!FluffyThemes.isColumnMode(context) &&
        !AppSettings.displayNavigationRail.value) {
      await AppSettings.displayNavigationRail.setItem(true);
    }

    setState(() {
      _activeSpaceId = spaceId;
      _spaceDirectoryOpen = false;
    });
  }

  void clearActiveSpace() => setState(() {
    _activeSpaceId = null;
    _spaceDirectoryOpen = false;
  });

  String? _sourceSpaceId;

  /// The network (a space) the chat list is narrowed to from the filter
  /// menu's Networks section, on top of the Unread / Groups / People
  /// filters. Null shows every network.
  String? get sourceSpaceId => _sourceSpaceId;

  void setSourceSpace(String? spaceId) => setState(() {
    _sourceSpaceId = spaceId;
  });

  bool _spaceDirectoryOpen = false;

  /// Whether the active space shows its room directory, which lists every
  /// room in the space including ones not joined yet, rather than the chat
  /// list filtered to the space.
  bool get spaceDirectoryOpen => _spaceDirectoryOpen;

  void setSpaceDirectoryOpen(bool open) => setState(() {
    _spaceDirectoryOpen = open;
  });

  Future<void> _onCallEvent(CallEvent? event) async {
    switch (event) {
      case CallEventActionCallAccept():
        _joinCallWith(event.callKitParams);
        break;
      case CallEventActionCallEnded():
        final roomId = event.callKitParams.extra?.tryGet<String>('roomId');
        if (roomId != null &&
            Matrix.of(context).activeCallRoomId.value == roomId) {
          Matrix.of(context).activeCallRoomId.value = null;
        }
        break;
      case CallEventActionCallIncoming() || CallEventActionCallStart()
          when PlatformInfos.isIOS:
        // To have audio session correctly configured on iOS:
        lk.AudioManager.instance.setEngineAvailability(.none);
        break;
      case CallEventActionCallToggleAudioSession() when PlatformInfos.isIOS:
        // To have audio session correctly configured on iOS:
        await lk.AudioManager.instance.setEngineAvailability(
          event.isActive ? .defaultAvailability : .none,
        );
        break;
      default:
        break;
    }
  }

  /// Opens [room]'s row: in the main window, or in its chat window when it
  /// has one, which comes to the front.
  Future<void> onChatTap(Room room) async {
    final target = chatWindowTarget(room);
    if (target != null && ChatWindows.instance.focus(target)) return;
    final contact = mergedContactFor(room);
    if (contact != null) {
      openMergedContact(context, contact);
      return;
    }
    if (room.membership == Membership.leave) {
      context.go('/rooms/archive/${room.id}');
      return;
    }

    if (room.membership == .join && room.isSpace) {
      setActiveSpace(room.id);
      return;
    }

    context.go('/rooms/${room.id}');
  }

  bool Function(Room) getRoomFilterByActiveFilter(ActiveFilter activeFilter) {
    switch (activeFilter) {
      case ActiveFilter.allChats:
        return (room) => true;
      case ActiveFilter.messages:
        return (room) => !room.isSpace && room.isDirectChat;
      case ActiveFilter.groups:
        return (room) => !room.isSpace && !room.isDirectChat;
      case ActiveFilter.unread:
        return (room) => room.countsAsUnread;
      case ActiveFilter.tag:
        return (room) => room.tags.keys.contains(activeTag);
    }
  }

  List<Room> get filteredRooms => Matrix.of(
    context,
  ).client.rooms.where(getRoomFilterByActiveFilter(activeFilter)).toList();

  MergedChatList _mergedChatList = const MergedChatList([], {});

  MergedContactsStore? _watchedMergedContacts;

  /// Rebuilds the list when merged contacts change, since merging or
  /// unmerging changes which tiles exist. Follows the active account.
  void _watchMergedContacts(Client client) {
    final store = MergedContactsStore.forClient(client);
    if (identical(store, _watchedMergedContacts)) return;
    _unwatchMergedContacts();
    _watchedMergedContacts = store..revision.addListener(_onMergedContacts);
  }

  void _unwatchMergedContacts() {
    // The store of an account that logged out is already disposed.
    try {
      _watchedMergedContacts?.revision.removeListener(_onMergedContacts);
    } catch (_) {}
    _watchedMergedContacts = null;
  }

  void _onMergedContacts() {
    if (mounted) setState(() {});
  }

  /// The chats to list under the active filter and [where], with each
  /// merged contact collapsed into one entry (see [MergedChatList]).
  List<Room> listedChats(bool Function(Room room) where) {
    _watchMergedContacts(Matrix.of(context).client);
    final filter = getRoomFilterByActiveFilter(activeFilter);
    _mergedChatList = MergedChatList.build(
      Matrix.of(context).client,
      Matrix.of(context).client.rooms,
      (room) => filter(room) && where(room),
    );
    return _mergedChatList.rooms;
  }

  /// The merged contact [room] stands for in the list, if it is one.
  MergedContact? mergedContactFor(Room room) =>
      _mergedChatList.contacts[room.id];

  /// How much taller than its usual height a listed chat's row is drawn,
  /// for estimates of row positions: a row offering to copy a one-time code
  /// has a button under its preview.
  double extraRowHeight(Room room) =>
      chatListOneTimeCode(room, mergedContactFor(room)) == null
      ? 0
      : ChatListItem.oneTimeCodeHeight;

  /// Whether a listed chat counts as unread, across all rooms of a contact.
  bool listedChatIsUnread(Room room) =>
      mergedContactFor(room)?.isUnread ?? room.countsAsUnread;

  /// Whether a listed chat belongs in the pinned row.
  bool listedChatIsPinned(Room room) =>
      mergedContactFor(room)?.isFavourite ?? room.isFavourite;

  /// Whether the chat list search [filter] (lower case) finds [room].
  bool listedChatMatches(Room room, String filter, MatrixLocals locals) =>
      mergedContactFor(room)?.matchesSearch(filter, locals) ??
      room.getLocalizedDisplayname(locals).toLowerCase().contains(filter);

  /// The chats picked by a long press, by [selectionKey]. While any are
  /// picked, the selection bar replaces the header and a tap on a chat
  /// picks or drops it instead of opening it.
  final Set<String> _selection = {};

  bool get selectionMode => _selection.isNotEmpty;

  /// What identifies a listed chat in the selection. A merged contact is
  /// keyed by its ID, since the room it is listed under changes with every
  /// new message.
  String selectionKey(Room room) {
    final contact = mergedContactFor(room);
    return contact == null ? room.id : 'contact:${contact.id}';
  }

  bool isSelected(Room room) => _selection.contains(selectionKey(room));

  void toggleSelection(Room room) {
    final key = selectionKey(room);
    setState(() {
      if (!_selection.remove(key)) _selection.add(key);
    });
  }

  void clearSelection() {
    if (_selection.isEmpty || !mounted) return;
    setState(_selection.clear);
  }

  /// Drops selected chats that are not among [shown], the chats the list
  /// shows now, for example after they were left or merged away.
  void keepSelectedOnly(Iterable<Room> shown) {
    if (_selection.isEmpty || !mounted) return;
    final keys = {for (final room in shown) selectionKey(room)};
    if (_selection.every(keys.contains)) return;
    setState(() => _selection.retainWhere(keys.contains));
  }

  /// The selected chats, in list order.
  List<SelectedChat> get selectedChats => [
    for (final room in _mergedChatList.rooms)
      if (_selection.contains(selectionKey(room)))
        SelectedChat(room, mergedContactFor(room)),
  ];

  /// Escape on a keyboard clears the selection, as back does, unless a
  /// dialog or menu is open over the list or the key went to another
  /// window.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.escape ||
        !selectionMode ||
        !mounted ||
        ModalRoute.of(context)?.isCurrent == false) {
      return false;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        View.maybeOf(focusContext) != View.maybeOf(context)) {
      return false;
    }
    clearSelection();
    return true;
  }

  /// The chat window [room]'s row opens in: its merged contact's, else the
  /// room's own. Null for rows that open only in the main window (spaces
  /// and chats that were left) and where there are no chat windows.
  ChatWindowTarget? chatWindowTarget(Room room) {
    if (!ChatWindows.instance.isSupported) return null;
    final contact = mergedContactFor(room);
    if (contact != null) return ChatWindowTarget.contact(contact.id);
    if (room.isSpace || room.membership == Membership.leave) return null;
    return ChatWindowTarget.room(room.id);
  }

  /// Opens [room]'s row in a chat window, or brings its window to the
  /// front.
  void openInNewWindow(Room room) {
    final target = chatWindowTarget(room);
    if (target == null) return;
    final i18n = MatrixLocals(L10n.of(context));
    ChatWindows.instance.open(
      target,
      title:
          mergedContactFor(room)?.displayName(i18n) ??
          room.getLocalizedDisplayname(i18n),
    );
  }

  /// The row clicked last and where the main window was before, kept for
  /// [kDoubleTapTimeout] in case a second click makes it a double click.
  ({String roomId, String location})? _firstClick;
  Timer? _firstClickTimer;

  void _forgetFirstClick() {
    _firstClickTimer?.cancel();
    _firstClickTimer = null;
    _firstClick = null;
  }

  /// A tap on a listed chat: opens it, or while chats are selected, picks
  /// or drops it. Where there are chat windows, a second click on the same
  /// row within [kDoubleTapTimeout] opens it in its window instead. The
  /// first click still opens it at once, so a single click is not held
  /// back; the second one returns the main window to where it was.
  void onListedChatTap(Room room) {
    if (selectionMode) {
      toggleSelection(room);
      return;
    }
    final first = _firstClick;
    _forgetFirstClick();
    if (chatWindowTarget(room) != null) {
      final router = GoRouter.of(context);
      final location = router.routerDelegate.currentConfiguration.uri
          .toString();
      if (first != null && first.roomId == room.id) {
        openInNewWindow(room);
        if (location != first.location) router.go(first.location);
        return;
      }
      _firstClick = (roomId: room.id, location: location);
      _firstClickTimer = Timer(kDoubleTapTimeout, _forgetFirstClick);
    }
    onChatTap(room);
  }

  bool isSearchMode = false;
  Future<QueryPublicRoomsResponse>? publicRoomsResponse;
  String? searchServer;
  Timer? _coolDown;
  SearchUserDirectoryResponse? userSearchResult;
  QueryPublicRoomsResponse? roomSearchResult;

  bool isSearching = false;
  static const String _serverStoreNamespace = 'im.fluffychat.search.server';

  Future<void> setServer() async {
    final matrix = Matrix.of(context);
    final l10n = L10n.of(context);
    final newServer = await showTextInputDialog(
      useRootNavigator: false,
      title: l10n.changeTheHomeserver,
      context: context,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      prefixText: 'https://',
      hintText: matrix.client.homeserver?.host,
      initialText: searchServer,
      keyboardType: TextInputType.url,
      autocorrect: false,
      validator: (server) =>
          server.contains('.') == true ? null : l10n.invalidServerName,
    );
    if (newServer == null) return;
    if (!mounted) return;
    matrix.store.setString(_serverStoreNamespace, newServer);
    setState(() {
      searchServer = newServer;
    });
    _coolDown?.cancel();
    _coolDown = Timer(const Duration(milliseconds: 500), _search);
  }

  /// The window title bar that holds this list's search field and account
  /// button (see [TitleBarSearch]), if there is one. The list then shows
  /// neither itself.
  TitleBarSearch? titleBarSearch;

  /// The search field's text and focus: the title bar's while there is one,
  /// which outlive this list.
  late final TextEditingController searchController =
      titleBarSearch?.textController ?? TextEditingController();
  late final FocusNode searchFocusNode =
      titleBarSearch?.focusNode ?? FocusNode();

  Future<void> _search() async {
    final client = Matrix.of(context).client;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (!isSearching) {
      setState(() {
        isSearching = true;
      });
    }
    SearchUserDirectoryResponse? userSearchResult;
    QueryPublicRoomsResponse? roomSearchResult;
    final searchQuery = searchController.text.trim();
    // Without Matrix contacts to find, the search stays with the user's own
    // chats and messages: no public rooms, no user directory, and only a
    // typed room address is looked up.
    final explore = MatrixFeatures.forClient(
      client,
    ).isRelevant(MatrixFeature.explore);
    try {
      roomSearchResult = explore
          ? await client.queryPublicRooms(
              server: searchServer,
              filter: PublicRoomQueryFilter(genericSearchTerm: searchQuery),
              limit: 20,
            )
          : QueryPublicRoomsResponse(chunk: []);

      if (searchQuery.isValidMatrixIdStrict() &&
          searchQuery.sigil == '#' &&
          roomSearchResult.chunk.any(
                (room) => room.canonicalAlias == searchQuery,
              ) ==
              false) {
        final response = await client.getRoomIdByAlias(searchQuery);
        final roomId = response.roomId;
        if (roomId != null) {
          roomSearchResult.chunk.add(
            PublishedRoomsChunk(
              name: searchQuery,
              guestCanJoin: false,
              numJoinedMembers: 0,
              roomId: roomId,
              worldReadable: false,
              canonicalAlias: searchQuery,
            ),
          );
        }
      }
      if (explore) {
        userSearchResult = await client.searchUserDirectory(
          searchController.text,
          limit: 20,
        );
      }
    } catch (e, s) {
      Logs().w('Searching has crashed', e, s);
      if (!mounted) return;
      scaffoldMessenger.showSnackBar(
        SnackBar(content: Text(e.toLocalizedString(context))),
      );
    }
    // Search ended, or the text changed while the server answered: a later
    // search (or none, for cleared text) owns the results.
    if (!isSearchMode || searchController.text.trim() != searchQuery) return;
    setState(() {
      isSearching = false;
      this.roomSearchResult = roomSearchResult;
      this.userSearchResult = userSearchResult;
    });
  }

  /// Searches for [text] as it is typed. Clearing the text keeps search
  /// open and focused, with every chat listed and no server results, as
  /// Google Messages does; only [cancelSearch] (the close button, back or
  /// Escape) ends it.
  void onSearchEnter(String text, {bool globalSearch = true}) {
    _coolDown?.cancel();
    if (text.isEmpty) {
      setState(() {
        isSearchMode = true;
        roomSearchResult = userSearchResult = null;
        isSearching = false;
      });
      return;
    }

    setState(() {
      isSearchMode = true;
    });
    if (globalSearch) {
      _coolDown = Timer(const Duration(milliseconds: 500), _search);
    }
  }

  void openNavrail() {
    setState(() {
      AppSettings.displayNavigationRail.setItem(
        !AppSettings.displayNavigationRail.value,
      );
    });
  }

  void startSearch() {
    setState(() {
      isSearchMode = true;
    });
    searchFocusNode.requestFocus();
    _coolDown?.cancel();
    _coolDown = Timer(const Duration(milliseconds: 500), _search);
  }

  void cancelSearch({bool unfocus = true}) {
    setState(() {
      searchController.clear();
      isSearchMode = false;
      roomSearchResult = userSearchResult = null;
      isSearching = false;
    });
    if (unfocus) searchFocusNode.unfocus();
  }

  BoxConstraints? snappingSheetContainerSize;

  final ScrollController scrollController = ScrollController();

  /// Marks the bar at the top of the list, so what sits below it can find
  /// how much of it is on screen.
  final GlobalKey headerKey = GlobalKey(debugLabel: 'chat list header');

  /// The chats the list currently shows below the pins, in order, and
  /// whether the pinned row is shown above them.
  final listedRooms = ValueNotifier<({List<Room> rooms, bool pins})>((
    rooms: const [],
    pins: false,
  ));
  final ValueNotifier<bool> scrolledToTop = ValueNotifier(true);

  final StreamController<Client> _clientStream = StreamController.broadcast();

  Stream<Client> get clientStream => _clientStream.stream;

  void addAccountAction() => context.go('/rooms/settings/account');

  void _onScroll() {
    final newScrolledToTop = scrollController.position.pixels <= 0;
    if (newScrolledToTop != scrolledToTop.value) {
      scrolledToTop.value = newScrolledToTop;
    }
  }

  Future<void> editSpace(BuildContext context, String spaceId) async {
    await Matrix.of(context).client.getRoomById(spaceId)!.postLoad();
    if (!context.mounted) return;
    context.push('/rooms/$spaceId/details');
  }

  // Needs to match GroupsSpacesEntry for 'separate group' checking.
  List<Room> get spaces =>
      Matrix.of(context).client.rooms.where((r) => r.isSpace).toList();

  String? get activeChat => widget.activeChat;

  /// Counts the changes that can alter what the header and the chat tiles
  /// show: every setState of this controller and every room update the
  /// list rebuilds for (see [markRoomsUpdated]).
  ///
  /// The router hands this page a new [ChatList] whenever the location
  /// changes, for example when a chat is closed, and that rebuilds the whole
  /// list. The header and the tiles built since the last change are handed
  /// back as the same widget instances, which the framework skips, so such a
  /// rebuild only redoes the tiles whose active state changed. They still
  /// rebuild on their own when an inherited widget they read changes.
  int _viewGeneration = 0;

  @override
  void setState(VoidCallback fn) {
    _viewGeneration++;
    super.setState(fn);
    titleBarSearch?.listChanged();
  }

  /// Called before the chat list rebuilds for a sync that touched the rooms,
  /// so the tiles are built again with the new room data.
  void markRoomsUpdated() => _viewGeneration++;

  (int, Widget?)? _header;

  /// The list's app bar: the search header, or the selection bar while
  /// chats are selected. Null under the title bar, which holds the search
  /// field, and where a selection floats in a toolbar instead (see
  /// [ChatListSelectionToolbar]).
  Widget? get header {
    final cached = _header;
    if (cached != null && cached.$1 == _viewGeneration) return cached.$2;
    final header = titleBarSearch != null
        ? null
        : selectionMode
        ? RoomUpdatesBuilder(
            client: Matrix.of(context).client,
            builder: (context) => ChatListSelectionBar(controller: this),
          )
        : ChatListHeader(controller: this);
    _header = (_viewGeneration, header);
    return header;
  }

  /// Built tiles, reused while nothing they show has changed: the view,
  /// merged contacts, the room and its space, whether it is the open chat,
  /// and whether network badges are shown.
  final Map<String, (int, int, Room, Room?, bool, bool, ChatListItem)> _tiles =
      {};

  /// The chat list tile for [room], shown below [space] when it has one.
  /// A room standing for a merged contact gets the contact's tile, with a
  /// badge for each of its rooms' spaces found in [spaces].
  ChatListItem chatListTile(
    Room room,
    Room? space, {
    Map<String, Room> spaces = const {},
  }) {
    final contact = mergedContactFor(room);
    final active = contact == null
        ? activeChat == room.id
        : isMergedContactActive(contact, activeChat);
    final mergedRevision = MergedContactsStore.forClient(
      room.client,
    ).revision.value;
    final badges = AppSettings.chatListNetworkBadges.value;
    final cached = _tiles[room.id];
    if (cached != null &&
        cached.$1 == _viewGeneration &&
        cached.$2 == mergedRevision &&
        identical(cached.$3, room) &&
        identical(cached.$4, space) &&
        cached.$5 == active &&
        cached.$6 == badges) {
      return cached.$7;
    }
    final tile = ChatListItem(
      room,
      space: space,
      contact: contact,
      networks: contact == null ? const [] : contact.networks(spaces),
      key: ValueKey(room.id),
      onTap: () => onListedChatTap(room),
      // A right-click (which brings a position) opens the chat's menu, unless
      // chats are being selected, when it picks this one too.
      onLongPress: (context, [position]) => position != null && !selectionMode
          ? showChatContextMenu(this, room, position)
          : toggleSelection(room),
      activeChat: active,
      selected: isSelected(room),
    );
    _tiles[room.id] = (
      _viewGeneration,
      mergedRevision,
      room,
      space,
      active,
      badges,
      tile,
    );
    return tile;
  }

  Future<void> _processIncomingSharedMedia(List<SharedMediaFile> files) async {
    // Links the app opens itself are not shared content: deep links, matrix:
    // links, and the address a notification bubble starts with (one per
    // conversation, see bubbleActivity in third_party/flutter_local_notifications),
    // which the plugin reports as shared text because it reads every VIEW
    // intent's data.
    files.removeWhere(
      (file) =>
          file.path.startsWith(AppConfig.deepLinkPrefix) ||
          const {
            'matrix',
            'fluffychat-bubble',
          }.contains(Uri.tryParse(file.path)?.scheme),
    );
    if (files.isEmpty) return;

    final items = files.map<ShareItem>((file) {
      if ({SharedMediaType.text, SharedMediaType.url}.contains(file.type)) {
        return TextShareItem(file.path);
      }
      return FileShareItem(
        XFile(file.path.replaceFirst('file://', ''), mimeType: file.mimeType),
      );
    }).toList();

    // A chat picked in the Android share sheet skips the To field.
    final shortcutId = await AndroidDirectShare.takeTargetShortcutId();
    if (!mounted) return;
    final client = Matrix.of(context).client;
    final store = MergedContactsStore.forClient(client);
    final targetRoute = shortcutId == null
        ? null
        : shareTargetRoute(
            shortcutId,
            hasRoom: (roomId) => client.getRoomById(roomId) != null,
            hasContact: (contactId) => store.contactById(contactId) != null,
            contactIdOf: (roomId) => store.contactForRoom(roomId)?.id,
          );
    final share = SharedDraft(items, fromShareIntent: true);
    // The chat a Direct Share picked opens with the share staged; else the
    // compose screen does, for the user to say who it goes to.
    context.go(targetRoute ?? '/rooms/newprivatechat', extra: share);
  }

  void _initReceiveSharingIntent() {
    if (!PlatformInfos.isMobile) return;

    // For sharing images coming from outside the app while the app is in the memory
    _intentFileStreamSubscription = ReceiveSharingIntent.instance
        .getMediaStream()
        .listen(_processIncomingSharedMedia, onError: print);

    // For sharing images coming from outside the app while the app is closed
    ReceiveSharingIntent.instance.getInitialMedia().then(
      _processIncomingSharedMedia,
    );

    if (PlatformInfos.isAndroid) {
      final shortcuts = FlutterShortcuts();
      shortcuts.initialize().then(
        (_) => shortcuts.listenAction((action) {
          if (!mounted) return;
          UrlLauncher(context, action).launchUrl();
        }),
      );
    }
  }

  void _joinCallWith(CallKitParams params) {
    final roomId = params.extra?.tryGet<String>('roomId');
    final clientName = params.extra?.tryGet<String>('clientName');
    if (roomId != null) {
      context.go('/rooms/$roomId?client=$clientName&action=call');
    }
  }

  StreamSubscription? _onRoomTagUpdate;

  @override
  void didUpdateWidget(covariant ChatList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.activeSpace != null &&
        widget.activeSpace != oldWidget.activeSpace) {
      setActiveSpace(widget.activeSpace!);
    }
  }

  @override
  void initState() {
    titleBarSearch = TitleBarSearch.maybeOf(context)?..register(this);
    _initReceiveSharingIntent();

    scrollController.addListener(_onScroll);
    HardwareKeyboard.instance.addHandler(_onKey);
    _waitForFirstSync();
    if (PlatformInfos.isMobile) {
      _callEventSubscription = FlutterCallkitIncoming.onEvent.listen(
        _onCallEvent,
      );
      // To have audio session correctly configured on iOS:
      lk.AudioManager.instance.setAudioSessionManagementMode(
        lk.AudioSessionManagementMode.externalCallSystem,
      );
      FlutterCallkitIncoming.activeCalls().then((calls) {
        final params = calls.firstOrNull;
        if (params == null) return;
        _joinCallWith(params);
      });
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (widget.activeSpace != null) {
        setActiveSpace(widget.activeSpace!);
      }
      if (mounted) {
        searchServer = Matrix.of(
          context,
        ).store.getString(_serverStoreNamespace);
        Matrix.of(context).backgroundPush?.setupPush(context);
        UpdateNotifier.showUpdateDialog(context);
        UpdateNotifier.showUpdateAvailableBanner(context);
      }

      // Workaround for system UI overlay style not applied on app start
      SystemChrome.setSystemUIOverlayStyle(
        Theme.of(context).appBarTheme.systemOverlayStyle!,
      );
    });

    _updateRoomTags();
    _onRoomTagUpdate = Matrix.of(context).client.onSync.stream
        .where(
          (syncUpdate) =>
              syncUpdate.rooms?.join?.values.any(
                (roomUpdate) =>
                    roomUpdate.accountData?.any(
                      (accountData) => accountData.type == 'm.tag',
                    ) ??
                    false,
              ) ??
              false,
        )
        .listen(_updateRoomTags);

    if (roomTags.containsKey(AppSettings.chatFilter.value)) {
      activeFilter = ActiveFilter.tag;
      activeTag = AppSettings.chatFilter.value;
    } else {
      activeFilter =
          ActiveFilter.values.singleWhereOrNull(
            (filter) => AppSettings.chatFilter.value == filter.name,
          ) ??
          ActiveFilter.allChats;
    }

    _processPushHelperCrashReport();

    super.initState();
  }

  @override
  void dispose() {
    _intentDataStreamSubscription?.cancel();
    _intentFileStreamSubscription?.cancel();
    _callEventSubscription?.cancel();
    _onRoomTagUpdate?.cancel();
    _unwatchMergedContacts();
    HardwareKeyboard.instance.removeHandler(_onKey);
    _firstClickTimer?.cancel();
    scrollController.removeListener(_onScroll);
    final titleBarSearch = this.titleBarSearch;
    if (titleBarSearch == null) {
      searchController.dispose();
      searchFocusNode.dispose();
    } else {
      titleBarSearch.unregister(this);
    }
    scrollController.dispose();
    scrolledToTop.dispose();
    _clientStream.close();
    super.dispose();
  }

  void _processPushHelperCrashReport() {
    if (AppSettings.autoSendErrorReports.value != true) return;
    final store = Matrix.of(context).store;
    final report = store.getStringList(AppConfig.pushHelperCrashReportKey);
    if (report == null) return;
    store.remove(AppConfig.pushHelperCrashReportKey);
    ErrorReporter(
      context,
      'Push Helper has been crashed',
    ).onErrorCallback(report.first, StackTrace.fromString(report.last));
  }

  Map<String, int> roomTags = {};

  void _updateRoomTags([_]) {
    roomTags.clear();
    for (final room in Matrix.of(context).client.rooms) {
      for (final tag in room.tags.keys) {
        if (tag.startsWith('u.')) roomTags[tag] = (roomTags[tag] ?? 0) + 1;
      }
    }
    setState(() {
      if (activeTag != null && !roomTags.keys.contains(activeTag)) {
        activeTag = null;
        activeFilter = ActiveFilter.allChats;
      }
    });
  }

  /// The chats [markAllAsRead] would mark: every unread joined chat of the
  /// active account, or only those of [space] and the spaces in it.
  List<Room> unreadChats([Room? space]) {
    final client = Matrix.of(context).client;
    final among = space == null ? null : roomIdsInSpace(client, space);
    return client.rooms
        .where(
          (room) =>
              room.membership == Membership.join &&
              (room.isUnread || room.markedUnread) &&
              (among == null || among.contains(room.id)),
        )
        .toList();
  }

  /// Moves the read marker to the newest event of every unread chat of the
  /// active account, or of [space] only, in small batches so large accounts
  /// are not rate limited.
  Future<void> markAllAsRead([Room? space]) async {
    final rooms = unreadChats(space);
    if (rooms.isEmpty) return;
    await showFutureLoadingDialog(
      context: context,
      future: () async {
        for (var i = 0; i < rooms.length; i += 10) {
          await Future.wait(
            rooms.skip(i).take(10).map((room) async {
              if (room.markedUnread) await room.markUnread(false);
              final eventId = room.lastEvent?.eventId;
              if (eventId == null) return;
              await room.setReadMarker(
                eventId,
                mRead: eventId,
                public: AppSettings.sendPublicReadReceipts.value,
              );
            }),
          );
        }
      },
    );
  }

  /// Takes [space] off the rail (see [AppSettings.railHiddenSpaces]),
  /// leaving it first if it is the one open.
  Future<void> hideFromRail(Room space) async {
    await AppSettings.railHiddenSpaces.setItem([
      ...AppSettings.railHiddenSpaces.value.where((id) => id != space.id),
      space.id,
    ]);
    if (!mounted) return;
    if (activeSpaceId == space.id) {
      clearActiveSpace();
    } else {
      setState(() {});
    }
  }

  /// Resumes notifications when snoozed, and otherwise asks for how long to
  /// snooze them.
  Future<void> toggleNotificationSnooze() async {
    final l10n = L10n.of(context);
    if (notificationsSnoozedUntil != null) {
      await snoozeNotificationsUntil(null);
      return;
    }
    final now = DateTime.now();
    final until = await showModalActionPopup<DateTime>(
      context: context,
      title: l10n.snoozeNotifications,
      actions: [
        AdaptiveModalAction(
          value: now.add(const Duration(hours: 1)),
          label: l10n.snoozeForOneHour,
        ),
        AdaptiveModalAction(
          value: now.add(const Duration(hours: 8)),
          label: l10n.snoozeForEightHours,
        ),
        AdaptiveModalAction(
          value: nextMorning,
          label: l10n.snoozeUntilTomorrow,
        ),
      ],
    );
    if (until == null || !mounted) return;
    await snoozeNotificationsUntil(until);
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          l10n.notificationsSnoozedUntil(
            DateFormat.MMMd().add_jm().format(until),
          ),
        ),
      ),
    );
  }

  Future<void> setStatus() async {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final currentPresence = await client.fetchCurrentPresence(client.userID!);
    if (!mounted) return;
    final input = await showTextInputDialog(
      useRootNavigator: false,
      context: context,
      title: l10n.setStatus,
      message: l10n.leaveEmptyToClearStatus,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      hintText: l10n.statusExampleMessage,
      maxLines: 6,
      minLines: 1,
      maxLength: 255,
      initialText: currentPresence.statusMsg,
    );
    if (input == null) return;
    if (!mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => client.setPresence(
        client.userID!,
        PresenceType.online,
        statusMsg: input,
      ),
    );
  }

  bool waitForFirstSync = false;

  Future<void> _waitForFirstSync() async {
    final router = GoRouter.of(context);
    final client = Matrix.of(context).client;
    await client.roomsLoading;
    await client.accountDataLoading;
    await client.userDeviceKeysLoading;
    if (client.prevBatch == null) {
      await client.onSyncStatus.stream.firstWhere(
        (status) => status.status == SyncStatus.finished,
      );

      if (!mounted) return;
      setState(() {
        waitForFirstSync = true;
      });
    }
    if (!mounted) return;
    setState(() {
      waitForFirstSync = true;
    });

    // Other sessions being unverified is not something this install can act
    // on, so only its own device is checked.
    final thisDevice =
        client.userDeviceKeys[client.userID!]?.deviceKeys[client.deviceID];
    if (thisDevice != null && !thisDevice.verified && !thisDevice.blocked) {
      late final ScaffoldFeatureController controller;
      final theme = Theme.of(context);
      controller = ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 15),
          showCloseIcon: true,
          backgroundColor: theme.colorScheme.errorContainer,
          closeIconColor: theme.colorScheme.onErrorContainer,
          content: Text(
            L10n.of(context).thisDeviceIsNotVerified,
            style: TextStyle(color: theme.colorScheme.onErrorContainer),
          ),
          action: SnackBarAction(
            onPressed: () {
              controller.close();
              router.go('/rooms/settings/devices');
            },
            textColor: theme.colorScheme.onErrorContainer,
            label: L10n.of(context).settings,
          ),
        ),
      );
    }
  }

  void setActiveFilter(ActiveFilter filter, String? tag) {
    if (filter == ActiveFilter.tag && tag == null) {
      throw ('Must set a tag when setting filter to tags!');
    }
    setState(() {
      activeTag = tag;
      activeFilter = filter;
    });
    AppSettings.chatFilter.setItem(
      filter == ActiveFilter.tag ? tag! : filter.name,
    );
  }

  void setActiveClient(Client client) {
    context.go('/rooms');
    setState(() {
      activeFilter = ActiveFilter.allChats;
      _activeSpaceId = null;
      Matrix.of(context).setActiveClient(client);
    });
    _clientStream.add(client);
  }

  void setActiveBundle(String bundle) {
    context.go('/rooms');
    setState(() {
      _activeSpaceId = null;
      Matrix.of(context).activeBundle = bundle;
      if (!Matrix.of(
        context,
      ).currentBundle!.any((client) => client == Matrix.of(context).client)) {
        Matrix.of(
          context,
        ).setActiveClient(Matrix.of(context).currentBundle!.first);
      }
    });
  }

  Future<void> editBundlesForAccount(
    String? userId,
    String? activeBundle,
  ) async {
    final l10n = L10n.of(context);
    final client = Matrix.of(
      context,
    ).widget.clients[Matrix.of(context).getClientIndexByMatrixId(userId!)];
    final action = await showModalActionPopup<EditBundleAction>(
      context: context,
      title: L10n.of(context).editBundlesForAccount,
      cancelLabel: L10n.of(context).cancel,
      actions: [
        AdaptiveModalAction(
          value: EditBundleAction.addToBundle,
          label: L10n.of(context).addToBundle,
        ),
        if (activeBundle != client.userID)
          AdaptiveModalAction(
            value: EditBundleAction.removeFromBundle,
            label: L10n.of(context).removeFromBundle,
          ),
      ],
    );
    if (action == null) return;
    switch (action) {
      case EditBundleAction.addToBundle:
        if (!mounted) return;
        final bundle = await showTextInputDialog(
          context: context,
          title: l10n.bundleName,
          hintText: l10n.bundleName,
        );
        if (bundle == null || bundle.isEmpty || bundle.isEmpty) return;
        if (!mounted) return;
        await showFutureLoadingDialog(
          context: context,
          future: () => client.setAccountBundle(bundle),
        );
        break;
      case EditBundleAction.removeFromBundle:
        if (!mounted) return;
        await showFutureLoadingDialog(
          context: context,
          future: () => client.removeFromAccountBundle(activeBundle!),
        );
    }
  }

  bool get displayBundles =>
      Matrix.of(context).hasComplexBundles &&
      Matrix.of(context).accountBundles.keys.length > 1;

  String? get secureActiveBundle {
    if (Matrix.of(context).activeBundle == null ||
        !Matrix.of(
          context,
        ).accountBundles.keys.contains(Matrix.of(context).activeBundle)) {
      return Matrix.of(context).accountBundles.keys.first;
    }
    return Matrix.of(context).activeBundle;
  }

  void resetActiveBundle() {
    WidgetsBinding.instance.addPostFrameCallback((timeStamp) {
      setState(() {
        Matrix.of(context).activeBundle = null;
      });
    });
  }

  @override
  Widget build(BuildContext context) => ChatListView(this);

  Future<void> dehydrate() => Matrix.of(context).dehydrateAction(context);
}

enum EditBundleAction { addToBundle, removeFromBundle }
