// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/active_call_indicator.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/pages/chat_list/chat_list_swipe.dart';
import 'package:fluffychat/pages/chat_list/chat_peek.dart';
import 'package:fluffychat/pages/chat_list/message_preview.dart';
import 'package:fluffychat/pages/chat_list/message_preview_cache.dart';
import 'package:fluffychat/pages/chat_list/own_message_status.dart';
import 'package:fluffychat/pages/chat_list/push_rule_state_cache.dart';
import 'package:fluffychat/pages/chat_list/search_scope.dart';
import 'package:fluffychat/pages/chat_list/unread_bubble.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/one_time_code.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
import 'package:fluffychat/utils/room_unread.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:fluffychat/widgets/typing_animation.dart';
import 'package:flutter/gestures.dart' show PointerDeviceKind;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../utils/date_time_extension.dart';
import '../../widgets/avatar.dart';
import '../../widgets/group_avatar.dart';

/// The one-time passcode a chat list row offers to copy, from the latest
/// message of an unread chat when someone else sent it. Once the chat is
/// read the button goes, so old codes do not linger.
String? chatListOneTimeCode(Room room, [MergedContact? contact]) {
  if (room.membership != Membership.join) return null;
  if (!(contact?.isUnread ?? room.countsAsUnread)) return null;
  final event = contact?.lastEvent ?? room.lastEvent;
  if (event == null ||
      event.redacted ||
      event.type != EventTypes.Message ||
      event.senderId == room.client.userID ||
      !{MessageTypes.Text, MessageTypes.Notice}.contains(event.messageType)) {
    return null;
  }
  return findOneTimeCode(event.body);
}

class ChatListItem extends StatefulWidget {
  /// How much taller a row is while it shows the copy code button, see
  /// [chatListOneTimeCode].
  static const double oneTimeCodeHeight = 40;

  final Room room;
  final Room? space;

  /// Set when [room] stands for a merged contact: the tile then shows the
  /// contact (its name, newest message, summed unread state) and a badge for
  /// each of [networks] instead of [space].
  final MergedContact? contact;
  final List<Room?> networks;
  final bool activeChat;

  /// Whether the chat is picked in the chat list's selection mode: the row
  /// is highlighted and a check stands in for the avatar.
  final bool selected;

  /// Called on a long press of the avatar, a long press of the row that
  /// does not open its peek (see [onPeek]), and a right-click, which passes
  /// its [globalPosition]. [context] is the tile's.
  final void Function(BuildContext context, [Offset? globalPosition])?
  onLongPress;

  /// Called instead of [onLongPress] when a finger or stylus holds the row
  /// outside its avatar, with the tile's [context], the [pointer] still
  /// down and its global [position]. A mouse's long press and a screen
  /// reader's still call [onLongPress].
  final void Function(BuildContext context, int pointer, Offset position)?
  onPeek;
  final void Function()? onForget;
  final void Function() onTap;
  final String? filter;

  /// Search text to mark in the name, bold in the primary colour.
  final String? highlight;

  const ChatListItem(
    this.room, {
    this.activeChat = false,
    this.selected = false,
    required this.onTap,
    this.onLongPress,
    this.onPeek,
    this.onForget,
    this.filter,
    this.highlight,
    this.space,
    this.contact,
    this.networks = const [],
    super.key,
  });

  @override
  State<ChatListItem> createState() => _ChatListItemState();
}

class _ChatListItemState extends State<ChatListItem> {
  // The futures below are created once per input and reused across builds.
  // A FutureBuilder given a new future on every build resubscribes and
  // rebuilds again when each one completes, and the SDK call behind it is
  // repeated on every sync.
  Object? _heroUsersKey;
  Future<List<User>>? _heroUsersFuture;
  Object? _senderKey;
  Future<User?>? _senderFuture;

  /// Loads the members a nameless room is named after, again only when the
  /// room or its heroes change.
  Future<List<User>>? _heroUsers(Room room) {
    if (room.name.isNotEmpty) {
      _heroUsersKey = null;
      return _heroUsersFuture = null;
    }
    final key = (
      room.id,
      room.membership,
      room.summary.mHeroes?.join('\n'),
      room.directChatMatrixID,
    );
    if (key != _heroUsersKey || _heroUsersFuture == null) {
      _heroUsersKey = key;
      _heroUsersFuture = room.loadHeroUsers();
    }
    return _heroUsersFuture;
  }

  /// Fetches the sender of [event] while it is missing from the room state,
  /// once per event.
  Future<User?>? _sender(Event? event, bool needed) {
    if (event == null || !needed) {
      _senderKey = null;
      return _senderFuture = null;
    }
    final key = (event.eventId, event.type, event.redacted);
    if (key != _senderKey || _senderFuture == null) {
      _senderKey = key;
      _senderFuture = event.fetchSenderUser();
    }
    return _senderFuture;
  }

  /// The finger or stylus on the row, while one is down. A long press with
  /// it opens the peek.
  int? _touchPointer;
  Offset _touchPosition = Offset.zero;

  void _pointerDown(PointerDownEvent event) {
    _touchPointer =
        event.kind == PointerDeviceKind.mouse ||
            event.kind == PointerDeviceKind.trackpad
        ? null
        : event.pointer;
    _touchPosition = event.position;
  }

  void _pointerMove(PointerMoveEvent event) {
    if (event.pointer == _touchPointer) _touchPosition = event.position;
    ChatPeekGesture.move(event);
  }

  void _pointerUp(PointerUpEvent event) {
    if (event.pointer == _touchPointer) _touchPointer = null;
    ChatPeekGesture.up(event);
  }

  void _pointerCancel(PointerCancelEvent event) {
    if (event.pointer == _touchPointer) _touchPointer = null;
    ChatPeekGesture.cancel(event);
  }

  void _longPress(BuildContext context) {
    final pointer = _touchPointer;
    final onPeek = widget.onPeek;
    if (pointer != null && onPeek != null) {
      onPeek(context, pointer, _touchPosition);
    } else {
      widget.onLongPress?.call(context);
    }
  }

  /// A long press of the avatar selects the chat however the row's own
  /// long press is taken.
  void _avatarLongPress(BuildContext context) {
    Feedback.forLongPress(context);
    widget.onLongPress?.call(context);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = widget.room;
    final activeChat = widget.activeChat;
    final onLongPress = widget.onLongPress;
    final onForget = widget.onForget;

    final contact = widget.contact;
    final displayname =
        contact?.displayName(MatrixLocals(L10n.of(context))) ??
        room.chatDisplayname(MatrixLocals(L10n.of(context)));
    final filter = widget.filter;
    final highlight = widget.highlight?.trim().isEmpty ?? true
        ? null
        : widget.highlight;
    if (filter != null && !displayname.toLowerCase().contains(filter)) {
      return const SizedBox.shrink();
    }

    // A merged contact reads these from all of its rooms; see MergedContact.
    final isMuted =
        contact?.isMuted ?? room.cachedPushRuleState != PushRuleState.notify;
    final typingText = contact == null
        ? room.getLocalizedTypingText(context)
        : contact.rooms
              .map((room) => room.getLocalizedTypingText(context))
              .firstWhere((text) => text.isNotEmpty, orElse: () => '');
    final lastEvent = contact?.lastEvent ?? room.lastEvent;
    // The room the preview's message is in, which for a contact can be any
    // of its rooms.
    final previewRoom = lastEvent?.room ?? room;
    final ownMessage = lastEvent?.senderId == room.client.userID;
    final directChatMatrixId = previewRoom.directChatMatrixID;
    final isDirectChat = previewRoom.isOneToOne;
    final isUnread = contact?.isUnread ?? room.countsAsUnread;
    final notificationCount =
        contact?.notificationCount ?? room.notificationCount;
    final highlightCount = contact?.highlightCount ?? room.highlightCount;
    final hasNewMessages = contact?.hasNewMessages ?? room.hasNewMessages;
    final isFavourite = contact?.isFavourite ?? room.isFavourite;
    final isLowPriority = contact?.isLowPriority ?? room.isLowPriority;
    final hasNotifications = notificationCount > 0;
    final selected = widget.selected;
    final backgroundColor = activeChat || selected
        ? theme.colorScheme.secondaryContainer
        : null;

    final needLastEventSender =
        lastEvent != null &&
        previewRoom.getState(EventTypes.RoomMember, lastEvent.senderId) == null;
    final previewLocals =
        isDirectChat && lastEvent?.senderId == directChatMatrixId
        ? DirectChatMatrixLocals(L10n.of(context), displayname)
        : MatrixLocals(L10n.of(context));
    final space = widget.space;
    final oneTimeCode = chatListOneTimeCode(room, contact);

    // Rows have 12dp above and below their content: 3dp outside the
    // highlight, so two highlighted rows in a row stay apart by a 6dp gap,
    // and 9dp inside it.
    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: Material(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.hardEdge,
        color: backgroundColor,
        child: FutureBuilder(
          future: _heroUsers(room),
          builder: (context, _) => _mergeSemantics(
            hasOwnActions: oneTimeCode != null,
            selected: selected,
            ListTile(
              minVerticalPadding: 9,
              // The padding sets the height. Material's 72dp floor for two
              // lines would swallow part of it, and part of the one-time
              // code button.
              minTileHeight: 0,
              // A row up to 72dp tall centres its avatar. A taller one (a
              // two-line preview or the copy code button) holds it 16dp from
              // its top, beside the name, as Material places leading
              // elements in three-line items.
              titleAlignment: ListTileTitleAlignment.titleHeight,
              // With the tile's own 8dp margin the avatar starts 16dp from the
              // edge, as in Google Messages.
              contentPadding: const EdgeInsets.only(left: 8, right: 8),
              onLongPress: () => _longPress(context),
              // The avatars show a picture or initials of the chat named in
              // the title and of its space, plus a presence dot. A tap on
              // them opens the chat as the row's does, and a long press
              // selects it. Left in the tree each would become a separate
              // screen reader stop that announces bare initials.
              leading: ExcludeSemantics(
                child: GestureDetector(
                  onTap: widget.onTap,
                  onLongPress: () => _avatarLongPress(context),
                  child: HoverBuilder(
                    builder: (context, hovered) => AnimatedScale(
                      duration: FluffyThemes.animationDuration,
                      curve: FluffyThemes.animationCurve,
                      scale: hovered ? 1.1 : 1.0,
                      child: SizedBox(
                        width: Avatar.defaultSize,
                        height: Avatar.defaultSize,
                        child: Stack(
                          clipBehavior: Clip.none,
                          children: [
                            // The chat itself gets the full-size avatar; the
                            // space it belongs to (for bridges, the network) is
                            // a small badge in the corner, outlined in the
                            // tile's background so it reads as separate. A
                            // group without a picture shows its members. A
                            // selected chat shows a check instead of both.
                            SelectableAvatar(
                              selected: selected,
                              size: Avatar.defaultSize,
                              child:
                                  GroupAvatar.shows(
                                    contact?.sendViaRoom ?? room,
                                  )
                                  ? GroupAvatar(
                                      room: contact?.sendViaRoom ?? room,
                                      name: displayname,
                                    )
                                  : Avatar(
                                      shapeBorder: room.isSpace
                                          ? RoundedSuperellipseBorder(
                                              side: BorderSide(
                                                width: 1,
                                                color: theme.dividerColor,
                                              ),
                                              borderRadius:
                                                  BorderRadius.circular(
                                                    AppConfig.spaceBorderRadius,
                                                  ),
                                            )
                                          : null,
                                      borderRadius: room.isSpace
                                          ? BorderRadius.circular(
                                              AppConfig.spaceBorderRadius,
                                            )
                                          : null,
                                      mxContent:
                                          contact?.avatar ?? room.chatAvatar,
                                      size: Avatar.defaultSize,
                                      name: displayname,
                                      presenceUserId:
                                          contact
                                              ?.sendViaRoom
                                              .directChatMatrixID ??
                                          room.directChatMatrixID,
                                      presenceBackgroundColor: backgroundColor,
                                    ),
                            ),
                            if (selected ||
                                !AppSettings.chatListNetworkBadges.value)
                              const SizedBox.shrink()
                            else if (contact != null && contact.spansNetworks)
                              Positioned(
                                right: -4,
                                bottom: -4,
                                child: MergedBadge(
                                  contact: contact,
                                  size: Avatar.defaultSize * 0.42,
                                  outlineColor:
                                      backgroundColor ??
                                      theme.colorScheme.surface,
                                ),
                              )
                            else if (space != null)
                              Positioned(
                                right: -4,
                                bottom: -4,
                                child: Avatar(
                                  shapeBorder: RoundedSuperellipseBorder(
                                    side: BorderSide(
                                      width: 2,
                                      color:
                                          backgroundColor ??
                                          theme.colorScheme.surface,
                                    ),
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.spaceBorderRadius * 0.5,
                                    ),
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConfig.spaceBorderRadius * 0.5,
                                  ),
                                  mxContent: space.avatar,
                                  size: Avatar.defaultSize * 0.42,
                                  name: space.chatDisplayname(),
                                ),
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              title: Row(
                children: <Widget>[
                  Expanded(
                    child: Text.rich(
                      highlight == null
                          ? TextSpan(text: displayname)
                          : TextSpan(
                              children: highlightMatches(
                                displayname,
                                highlight,
                                searchMatchStyle(theme),
                              ),
                            ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                      // Unread chats stand out with heavier, brighter
                      // text.
                      style: isUnread
                          ? TextStyle(
                              fontWeight: FontWeight.w700,
                              color: theme.colorScheme.onSurface,
                            )
                          : null,
                    ),
                  ),
                  if (isMuted)
                    const Padding(
                      padding: EdgeInsets.only(left: 4.0),
                      child: Icon(Icons.notifications_off_outlined, size: 16),
                    ),
                  if (isLowPriority)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.low_priority,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (isFavourite)
                    Padding(
                      padding: EdgeInsets.only(
                        right: hasNotifications ? 4.0 : 0.0,
                      ),
                      child: Icon(
                        Icons.push_pin,
                        size: 16,
                        color: theme.colorScheme.primary,
                      ),
                    ),
                  if (!room.isSpace && room.membership != Membership.invite)
                    Padding(
                      padding: const EdgeInsets.only(left: 4.0),
                      child: Text(
                        (contact?.latestEventReceivedTime ??
                                room.latestEventReceivedTime)
                            .localizedTimeShort(context),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: hasNewMessages ? FontWeight.bold : null,
                          color: highlightCount >= 1
                              ? theme.colorScheme.error
                              : hasNewMessages
                              ? theme.colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      if (room.hasActiveMatrixRtcCall)
                        Padding(
                          padding: const EdgeInsets.only(right: 4.0),
                          child: ActiveCallIndicator(room: room),
                        ),
                      AnimatedSize(
                        clipBehavior: Clip.hardEdge,
                        duration: FluffyThemes.animationDuration,
                        curve: FluffyThemes.animationCurve,
                        child: typingText.isNotEmpty
                            ? Padding(
                                padding: const EdgeInsets.only(right: 4.0),
                                child: TypingAnimation(size: 4.0),
                              )
                            : lastEvent?.relationshipType ==
                                  RelationshipTypes.thread
                            ? Container(
                                decoration: BoxDecoration(
                                  border: Border.all(
                                    color: theme.colorScheme.outline,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConfig.borderRadius,
                                  ),
                                ),
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8.0,
                                ),
                                margin: const EdgeInsets.only(right: 4.0),
                                child: Row(
                                  mainAxisSize: .min,
                                  children: [
                                    Icon(
                                      Icons.message_outlined,
                                      size: 12,
                                      color: theme.colorScheme.outline,
                                    ),
                                    const SizedBox(width: 4),
                                    Text(
                                      L10n.of(context).thread,
                                      style: TextStyle(fontSize: 11),
                                    ),
                                  ],
                                ),
                              )
                            : const SizedBox.shrink(),
                      ),
                      Expanded(
                        child:
                            room.isSpace && room.membership == Membership.join
                            ? Text(
                                L10n.of(
                                  context,
                                ).countChats(room.spaceChildren.length),
                              )
                            : typingText.isNotEmpty
                            ? Text(
                                typingText,
                                style: TextStyle(
                                  color: theme.colorScheme.primary,
                                ),
                                maxLines: 1,
                                softWrap: false,
                              )
                            : FutureBuilder(
                                key: ValueKey(
                                  '${lastEvent?.eventId}_${lastEvent?.type}_${lastEvent?.redacted}',
                                ),
                                future: _sender(lastEvent, needLastEventSender),
                                builder: (context, snapshot) {
                                  final l10n = L10n.of(context);
                                  // An invite shows its reason instead of the
                                  // last message, so the body is not needed.
                                  final preview =
                                      lastEvent == null ||
                                          room.membership == Membership.invite
                                      ? null
                                      : MessagePreviewCache.preview(
                                          lastEvent,
                                          l10n,
                                          previewLocals,
                                        );
                                  final sender =
                                      lastEvent == null ||
                                          preview == null ||
                                          (isDirectChat &&
                                              directChatMatrixId ==
                                                  lastEvent.senderId)
                                      ? null
                                      : lastEvent.senderId == room.client.userID
                                      ? l10n.you
                                      : snapshot.data?.calcDisplayname() ??
                                            lastEvent.senderFromMemoryOrFallback
                                                .calcDisplayname();
                                  final textColor = isUnread
                                      ? theme.colorScheme.onSurface
                                      : null;
                                  String plain(MessagePreview preview) {
                                    final text = preview.text.trim().replaceAll(
                                      '\n',
                                      ' ',
                                    );
                                    return sender == null
                                        ? text
                                        : l10n.senderMessage(sender, text);
                                  }

                                  final span =
                                      room.membership == Membership.invite
                                      ? TextSpan(
                                          text:
                                              room
                                                  .getState(
                                                    EventTypes.RoomMember,
                                                    room.client.userID!,
                                                  )
                                                  ?.content
                                                  .tryGet<String>('reason') ??
                                              (isDirectChat
                                                  ? l10n.newChatRequest
                                                  : l10n.inviteGroupChat),
                                        )
                                      : preview == null
                                      ? TextSpan(text: l10n.noMessagesYet)
                                      // Media and a lone link show an icon
                                      // before a word or the address.
                                      : preview.icon != null
                                      ? messagePreviewSpan(
                                          l10n,
                                          preview,
                                          sender: sender,
                                          color: textColor,
                                        )
                                      : TextSpan(text: plain(preview));
                                  // The user's own message shows how far it
                                  // has got before "You:".
                                  final ownStatus =
                                      lastEvent != null &&
                                      preview != null &&
                                      room.membership != Membership.invite &&
                                      ownMessage;
                                  return Text.rich(
                                    ownStatus
                                        ? TextSpan(
                                            children: [
                                              WidgetSpan(
                                                alignment:
                                                    PlaceholderAlignment.middle,
                                                child: OwnMessageStatusIcon(
                                                  lastEvent,
                                                  color: textColor,
                                                ),
                                              ),
                                              span,
                                            ],
                                          )
                                        : span,
                                    softWrap: false,
                                    maxLines: notificationCount >= 1 ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: TextStyle(
                                      decoration: lastEvent?.redacted == true
                                          ? TextDecoration.lineThrough
                                          : null,
                                      fontWeight: isUnread
                                          ? FontWeight.w600
                                          : null,
                                      color: textColor,
                                    ),
                                  );
                                },
                              ),
                      ),
                      // Unread chats show how many messages are unread, in
                      // red when one mentions the user.
                      if (isUnread) ...[
                        const SizedBox(width: 8),
                        UnreadBubble(room: room, contact: contact),
                      ],
                    ],
                  ),
                  if (oneTimeCode != null) _CopyCodeButton(oneTimeCode),
                ],
              ),
              onTap: widget.onTap,
              trailing: onForget == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.delete_outlined),
                      onPressed: onForget,
                    ),
            ),
          ),
        ),
      ),
    );
    return GestureDetector(
      onSecondaryTapUp: (details) =>
          onLongPress?.call(context, details.globalPosition),
      // Raw pointer events, outside the gesture arena: the row learns what
      // touches it, and hands the moves of the finger that opened a peek on
      // to the peek.
      child: Listener(
        onPointerDown: _pointerDown,
        onPointerMove: _pointerMove,
        onPointerUp: _pointerUp,
        onPointerCancel: _pointerCancel,
        child: MediaQuery.disableAnimationsOf(context)
            ? tile
            // A row that changes height while on screen, such as a preview
            // going from one line to two or a typing indicator taking its
            // place, grows or shrinks over 250 ms and the rows below slide
            // with it. A row's first layout, as it scrolls in, is not
            // animated.
            : AnimatedSize(
                alignment: Alignment.topCenter,
                duration: Durations.medium1,
                curve: Easing.standard,
                clipBehavior: Clip.hardEdge,
                child: tile,
              ),
      ),
    );
  }

  /// Joins everything the tile shows into one screen reader stop: name,
  /// preview, time and unread count read as one chat, and the tile's tap and
  /// long press stay its actions. It reads as selected while picked in the
  /// selection mode. The archive's delete button and the copy code button
  /// ([hasOwnActions]) are actions of their own, so a tile that has one is
  /// left unmerged. A swipeable row's actions (see [ChatListSwipe]) are
  /// custom actions of the tile.
  Widget _mergeSemantics(
    Widget child, {
    bool hasOwnActions = false,
    bool selected = false,
  }) {
    final swipeActions = ChatListSwipeSemantics.of(context);
    final tile = Semantics(
      selected: selected,
      customSemanticsActions: swipeActions.isEmpty ? null : swipeActions,
      child: child,
    );
    return widget.onForget == null && !hasOwnActions
        ? MergeSemantics(child: tile)
        : tile;
  }
}

/// An outlined pill under the preview that copies a one-time passcode. As a
/// button of its own it takes the tap, so the chat does not open.
class _CopyCodeButton extends StatelessWidget {
  final String code;

  const _CopyCodeButton(this.code);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: SizedBox(
        height: ChatListItem.oneTimeCodeHeight - 8,
        child: OutlinedButton.icon(
          onPressed: () => FluffyShare.share(code, context, copyOnly: true),
          icon: const Icon(Icons.copy_outlined, size: 16),
          label: Text(L10n.of(context).copyOneTimeCode(code)),
          style: OutlinedButton.styleFrom(
            visualDensity: VisualDensity.compact,
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            minimumSize: const Size(0, ChatListItem.oneTimeCodeHeight - 8),
            shape: const StadiumBorder(),
            textStyle: theme.textTheme.labelLarge,
          ),
        ),
      ),
    );
  }
}
