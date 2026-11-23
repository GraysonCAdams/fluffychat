// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/active_call_indicator.dart';
import 'package:fluffychat/pages/chat_list/message_preview_cache.dart';
import 'package:fluffychat/pages/chat_list/push_rule_state_cache.dart';
import 'package:fluffychat/pages/chat_list/unread_bubble.dart';
import 'package:fluffychat/utils/matrix_live_kit_calls/matrix_live_kit_call.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/room_status_extension.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/typing_animation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';
import '../../utils/date_time_extension.dart';
import '../../widgets/avatar.dart';

class ChatListItem extends StatefulWidget {
  final Room room;
  final Room? space;
  final bool activeChat;

  /// Opens the context menu below [context]'s widget, or at [globalPosition]
  /// when the item was right-clicked.
  final void Function(BuildContext context, [Offset? globalPosition])?
  onLongPress;
  final void Function()? onForget;
  final void Function() onTap;
  final String? filter;

  const ChatListItem(
    this.room, {
    this.activeChat = false,
    required this.onTap,
    this.onLongPress,
    this.onForget,
    this.filter,
    this.space,
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

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final room = widget.room;
    final activeChat = widget.activeChat;
    final onLongPress = widget.onLongPress;
    final onForget = widget.onForget;

    final displayname = room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final filter = widget.filter;
    if (filter != null && !displayname.toLowerCase().contains(filter)) {
      return const SizedBox.shrink();
    }

    final isMuted = room.cachedPushRuleState != PushRuleState.notify;
    final typingText = room.getLocalizedTypingText(context);
    final lastEvent = room.lastEvent;
    final ownMessage = lastEvent?.senderId == room.client.userID;
    final directChatMatrixId = room.directChatMatrixID;
    final isDirectChat = directChatMatrixId != null;
    final hasNotifications = room.notificationCount > 0;
    final backgroundColor = activeChat
        ? theme.colorScheme.secondaryContainer
        : null;

    final needLastEventSender =
        lastEvent != null &&
        room.getState(EventTypes.RoomMember, lastEvent.senderId) == null;
    final previewLocals =
        isDirectChat && lastEvent?.senderId == directChatMatrixId
        ? DirectChatMatrixLocals(L10n.of(context), displayname)
        : MatrixLocals(L10n.of(context));
    final space = widget.space;

    final tile = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      child: Material(
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        clipBehavior: Clip.hardEdge,
        color: backgroundColor,
        child: FutureBuilder(
          future: _heroUsers(room),
          builder: (context, _) => _mergeSemantics(
            ListTile(
              minVerticalPadding: 16,
              contentPadding: const EdgeInsets.symmetric(horizontal: 8),
              onLongPress: () => onLongPress?.call(context),
              // The avatars show a picture or initials of the chat named in
              // the title and of its space, plus a presence dot, and their
              // only action opens the same context menu as the tile's long
              // press. Left in the tree each would become a separate screen
              // reader stop that announces bare initials.
              leading: ExcludeSemantics(
                child: HoverBuilder(
                  builder: (context, hovered) => AnimatedScale(
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    scale: hovered ? 1.1 : 1.0,
                    child: SizedBox(
                      width: Avatar.defaultSize,
                      height: Avatar.defaultSize,
                      child: Stack(
                        children: [
                          if (space != null)
                            Positioned(
                              top: 0,
                              left: 0,
                              child: Avatar(
                                shapeBorder: RoundedSuperellipseBorder(
                                  side: BorderSide(
                                    width: 2,
                                    color:
                                        backgroundColor ??
                                        theme.colorScheme.surface,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConfig.spaceBorderRadius * 0.75,
                                  ),
                                ),
                                borderRadius: BorderRadius.circular(
                                  AppConfig.spaceBorderRadius * 0.75,
                                ),
                                mxContent: space.avatar,
                                size: Avatar.defaultSize * 0.75,
                                name: space.getLocalizedDisplayname(),
                                onTap: () => onLongPress?.call(context),
                              ),
                            ),
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: Avatar(
                              shapeBorder: space == null
                                  ? room.isSpace
                                        ? RoundedSuperellipseBorder(
                                            side: BorderSide(
                                              width: 1,
                                              color: theme.dividerColor,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              AppConfig.spaceBorderRadius,
                                            ),
                                          )
                                        : null
                                  : RoundedRectangleBorder(
                                      side: BorderSide(
                                        width: 2,
                                        color:
                                            backgroundColor ??
                                            theme.colorScheme.surface,
                                      ),
                                      borderRadius: BorderRadius.circular(
                                        Avatar.defaultSize,
                                      ),
                                    ),
                              borderRadius: room.isSpace
                                  ? BorderRadius.circular(
                                      AppConfig.spaceBorderRadius,
                                    )
                                  : null,
                              mxContent: room.avatar,
                              size: space != null
                                  ? Avatar.defaultSize * 0.75
                                  : Avatar.defaultSize,
                              name: displayname,
                              presenceUserId: directChatMatrixId,
                              presenceBackgroundColor: backgroundColor,
                              onTap: () => onLongPress?.call(context),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              title: Row(
                children: <Widget>[
                  Expanded(
                    child: Text(
                      displayname,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      softWrap: false,
                    ),
                  ),
                  if (isMuted)
                    const Padding(
                      padding: EdgeInsets.only(left: 4.0),
                      child: Icon(Icons.notifications_off_outlined, size: 16),
                    ),
                  if (room.isLowPriority)
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
                  if (room.isFavourite)
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
                        room.latestEventReceivedTime.localizedTimeShort(
                          context,
                        ),
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: room.hasNewMessages
                              ? FontWeight.bold
                              : null,
                          color: room.highlightCount >= 1
                              ? theme.colorScheme.error
                              : room.hasNewMessages
                              ? theme.colorScheme.primary
                              : null,
                        ),
                      ),
                    ),
                ],
              ),
              subtitle: Row(
                children: [
                  if (room.hasActiveMatrixRtcCall)
                    Padding(
                      padding: const EdgeInsets.only(right: 4.0),
                      child: ActiveCallIndicator(room: room),
                    ),
                  if (typingText.isEmpty &&
                      ownMessage &&
                      room.lastEvent?.status.isSending == true) ...[
                    const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    ),
                    const SizedBox(width: 4),
                  ],
                  AnimatedSize(
                    clipBehavior: Clip.hardEdge,
                    duration: FluffyThemes.animationDuration,
                    curve: FluffyThemes.animationCurve,
                    child: typingText.isNotEmpty
                        ? Padding(
                            padding: const EdgeInsets.only(right: 4.0),
                            child: TypingAnimation(size: 4.0),
                          )
                        : room.lastEvent?.relationshipType ==
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
                    child: room.isSpace && room.membership == Membership.join
                        ? Text(
                            L10n.of(
                              context,
                            ).countChats(room.spaceChildren.length),
                          )
                        : typingText.isNotEmpty
                        ? Text(
                            typingText,
                            style: TextStyle(color: theme.colorScheme.primary),
                            maxLines: 1,
                            softWrap: false,
                          )
                        : FutureBuilder(
                            key: ValueKey(
                              '${lastEvent?.eventId}_${lastEvent?.type}_${lastEvent?.redacted}',
                            ),
                            future: _sender(lastEvent, needLastEventSender),
                            builder: (context, snapshot) {
                              // An invite shows its reason instead of the
                              // last message, so the body is not needed.
                              var body =
                                  lastEvent == null ||
                                      room.membership == Membership.invite
                                  ? null
                                  : MessagePreviewCache.localizedBody(
                                      lastEvent,
                                      L10n.of(context),
                                      previewLocals,
                                    );
                              if (lastEvent != null &&
                                  body != null &&
                                  (!isDirectChat ||
                                      directChatMatrixId !=
                                          room.lastEvent?.senderId)) {
                                body = L10n.of(context).senderMessage(
                                  lastEvent.senderId == room.client.userID
                                      ? L10n.of(context).you
                                      : snapshot.data?.calcDisplayname() ??
                                            lastEvent.senderFromMemoryOrFallback
                                                .calcDisplayname(),
                                  body,
                                );
                              }
                              return Text(
                                room.membership == Membership.invite
                                    ? room
                                              .getState(
                                                EventTypes.RoomMember,
                                                room.client.userID!,
                                              )
                                              ?.content
                                              .tryGet<String>('reason') ??
                                          (isDirectChat
                                              ? L10n.of(context).newChatRequest
                                              : L10n.of(
                                                  context,
                                                ).inviteGroupChat)
                                    : body?.trim().replaceAll('\n', ' ') ??
                                          L10n.of(context).noMessagesYet,
                                softWrap: false,
                                maxLines: room.notificationCount >= 1 ? 2 : 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  decoration: room.lastEvent?.redacted == true
                                      ? TextDecoration.lineThrough
                                      : null,
                                ),
                              );
                            },
                          ),
                  ),
                  const SizedBox(width: 8),
                  UnreadBubble(room: room),
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
      child: tile,
    );
  }

  /// Joins everything the tile shows into one screen reader stop: name,
  /// preview, time and unread count read as one chat, and the tile's tap and
  /// long press stay its actions. The archive's delete button is a second
  /// action of its own, so a tile that has one is left unmerged.
  Widget _mergeSemantics(Widget child) =>
      widget.onForget == null ? MergeSemantics(child: child) : child;
}
