// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/merged_contact_actions.dart';
import 'package:fluffychat/pages/chat_list/push_rule_state_cache.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merge_rules.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/room_unread.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_modal_action_popup.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/merged_contacts/manage_merged_contact_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// A chat picked in the chat list's selection mode: a room, or a merged
/// contact together with the room it is listed under.
class SelectedChat {
  final Room room;
  final MergedContact? contact;

  const SelectedChat(this.room, [this.contact]);

  /// The rooms an action on this chat applies to: every room of a contact.
  List<Room> get rooms => contact?.rooms ?? [room];

  bool get isJoined => rooms.every((room) => room.membership == .join);

  bool get isPinned => contact?.isFavourite ?? room.isFavourite;

  bool get isLowPriority => contact?.isLowPriority ?? room.isLowPriority;

  bool get isMuted =>
      contact?.isMuted ?? room.cachedPushRuleState != PushRuleState.notify;

  bool get isUnread => contact == null
      ? room.countsAsUnread
      : contact!.markedUnread || contact!.isUnread;
}

/// Moves the read marker of [room] to its newest event and clears a manual
/// unread mark.
Future<void> markRoomRead(Room room) async {
  if (room.markedUnread) await room.markUnread(false);
  final eventId = room.lastEvent?.eventId;
  if (eventId == null || !room.isUnread) return;
  await room.setReadMarker(
    eventId,
    mRead: eventId,
    public: AppSettings.sendPublicReadReceipts.value,
  );
}

enum _MoreAction {
  openInNewWindow,
  mergeWith,
  manage,
  unmerge,
  mergeSelected,
  goToSpace,
  addToSpace,
  lowPriority,
  addTag,
  removeTag,
  block,
}

/// The chat list's app bar while chats are selected: a close button, the
/// number of chats, and the actions for all of them. Pin, mute and
/// read/unread each set every selected chat the same way: pinned unless all
/// already are, and so on. Whatever applies to only some selections waits
/// in the overflow menu, and an action that does not apply is left out.
class ChatListSelectionBar extends StatelessWidget {
  final ChatListController controller;

  /// Under a title bar the bar stands in for the 48 high chip row while
  /// chats are selected, so the chats below stay where they were; otherwise
  /// it takes the place of the 72 high search header.
  final double height;

  const ChatListSelectionBar({
    required this.controller,
    this.height = 72,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final chats = controller.selectedChats;
    final joined = chats.isNotEmpty && chats.every((chat) => chat.isJoined);
    final pin = !chats.every((chat) => chat.isPinned);
    final mute = !chats.every((chat) => chat.isMuted);
    final markRead = chats.any((chat) => chat.isUnread);
    final leavesInvites = chats.every(
      (chat) => chat.room.membership == .invite,
    );
    final more = _moreActions(controller, chats);

    return SliverAppBar(
      toolbarHeight: height,
      pinned: true,
      scrolledUnderElevation: 0,
      backgroundColor: theme.colorScheme.surfaceContainer,
      automaticallyImplyLeading: false,
      leading: IconButton(
        tooltip: l10n.clearSelection,
        icon: const Icon(Icons.close_outlined),
        onPressed: controller.clearSelection,
      ),
      titleSpacing: 0,
      title: Semantics(
        label: l10n.countSelected(chats.length),
        excludeSemantics: true,
        child: Text('${chats.length}', style: theme.textTheme.titleLarge),
      ),
      actions: [
        // A low priority chat is never pinned, so pinning stays out of a
        // selection that has one, as Low priority does for pinned chats.
        if (joined && !chats.any((chat) => chat.isLowPriority))
          IconButton(
            tooltip: pin ? l10n.pin : l10n.unpin,
            icon: Icon(pin ? Icons.push_pin_outlined : Icons.push_pin),
            onPressed: () => setSelectedPinned(controller, chats, pin),
          ),
        if (joined)
          IconButton(
            tooltip: mute ? l10n.muteChat : l10n.unmuteChat,
            icon: Icon(
              mute
                  ? Icons.notifications_off_outlined
                  : Icons.notifications_outlined,
            ),
            onPressed: () => setSelectedMuted(controller, chats, mute),
          ),
        if (joined)
          IconButton(
            tooltip: markRead ? l10n.markAsRead : l10n.markAsUnread,
            icon: Icon(
              markRead
                  ? Icons.mark_email_read_outlined
                  : Icons.mark_email_unread_outlined,
            ),
            onPressed: () => setSelectedRead(controller, chats, markRead),
          ),
        if (chats.isNotEmpty)
          IconButton(
            tooltip: leavesInvites ? l10n.delete : l10n.leave,
            icon: const Icon(Icons.delete_outlined),
            onPressed: () => leaveSelected(controller, chats),
          ),
        if (more.isNotEmpty)
          PopupMenuButton<_MoreAction>(
            tooltip: l10n.more,
            icon: const Icon(Icons.more_vert),
            onSelected: (action) => _onMore(controller, chats, action),
            itemBuilder: (context) => [
              for (final (action, label) in more)
                PopupMenuItem(value: action, child: Text(label)),
            ],
          ),
        const SizedBox(width: 4),
      ],
    );
  }
}

/// The menu a right-click on [room]'s row opens at [position]: the
/// selection bar's actions for that one chat, without selecting it. Opening
/// it in a new window comes first, as in the bar's overflow menu.
Future<void> showChatContextMenu(
  ChatListController controller,
  Room room,
  Offset position,
) async {
  final context = controller.context;
  final l10n = L10n.of(context);
  final chats = [SelectedChat(room, controller.mergedContactFor(room))];
  final chat = chats.single;
  final more = _moreActions(controller, chats);
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final leavesInvite = room.membership == .invite;

  PopupMenuItem<Future<void> Function()> item(
    String label,
    Future<void> Function() action, {
    Color? color,
  }) => PopupMenuItem(
    value: action,
    child: Text(label, style: TextStyle(color: color)),
  );

  final choice = await showMenu<Future<void> Function()>(
    context: context,
    position: RelativeRect.fromRect(
      position & Size.zero,
      Offset.zero & overlay.size,
    ),
    items: [
      for (final (action, label) in more)
        if (action == _MoreAction.openInNewWindow)
          item(label, () => _onMore(controller, chats, action)),
      if (chat.isJoined && !chat.isLowPriority)
        item(
          chat.isPinned ? l10n.unpin : l10n.pin,
          () => setSelectedPinned(controller, chats, !chat.isPinned),
        ),
      if (chat.isJoined)
        item(
          chat.isMuted ? l10n.unmuteChat : l10n.muteChat,
          () => setSelectedMuted(controller, chats, !chat.isMuted),
        ),
      if (chat.isJoined)
        item(
          chat.isUnread ? l10n.markAsRead : l10n.markAsUnread,
          () => setSelectedRead(controller, chats, chat.isUnread),
        ),
      for (final (action, label) in more)
        if (action != _MoreAction.openInNewWindow)
          item(label, () => _onMore(controller, chats, action)),
      item(
        leavesInvite ? l10n.delete : l10n.leave,
        () => leaveSelected(controller, chats),
        color: Theme.of(context).colorScheme.error,
      ),
    ],
  );
  await choice?.call();
}

/// The spaces the user may add a chat to that do not hold all of [rooms].
List<Room> _spacesToAddTo(Client client, List<Room> rooms) => [
  for (final space in client.rooms)
    if (space.isSpace &&
        space.canChangeStateEvent(EventTypes.SpaceChild) &&
        rooms.any(
          (room) => !space.spaceChildren.any((c) => c.roomId == room.id),
        ))
      space,
];

/// The overflow menu entries for [chats], with their labels, in menu order.
List<(_MoreAction, String)> _moreActions(
  ChatListController controller,
  List<SelectedChat> chats,
) {
  if (chats.isEmpty) return const [];
  final l10n = L10n.of(controller.context);
  final client = chats.first.room.client;
  final joined = chats.every((chat) => chat.isJoined);
  final rooms = [for (final chat in chats) ...chat.rooms];
  final addToSpace = joined && _spacesToAddTo(client, rooms).isNotEmpty;
  final lowPriority = joined && !chats.any((chat) => chat.isPinned);
  final lowPriorityLabel = chats.every((chat) => chat.isLowPriority)
      ? l10n.unsetLowPriority
      : l10n.setLowPriority;
  final single = chats.length == 1 ? chats.single : null;
  final room = single?.room;

  return [
    if (single != null && controller.chatWindowTarget(single.room) != null)
      (_MoreAction.openInNewWindow, l10n.openInNewWindow),
    if (single != null && single.contact != null) ...[
      (_MoreAction.manage, l10n.manageLinkedChats),
      (_MoreAction.unmerge, l10n.unmerge),
    ] else if (room != null) ...[
      if (joined && room.isDirectChat && !room.isSpace)
        (_MoreAction.mergeWith, l10n.mergeWith),
      if (spacesByChild(client)[room.id] case final space?)
        (
          _MoreAction.goToSpace,
          l10n.goToSpace(space.getLocalizedDisplayname(MatrixLocals(l10n))),
        ),
    ] else if (canMergeTogether(client, [for (final chat in chats) chat.rooms]))
      (_MoreAction.mergeSelected, l10n.mergeTheseChats),
    if (addToSpace) (_MoreAction.addToSpace, l10n.addToSpace),
    if (lowPriority) (_MoreAction.lowPriority, lowPriorityLabel),
    if (room != null && single!.contact == null && joined)
      controller.activeTag == null
          ? (_MoreAction.addTag, l10n.addTag)
          : (_MoreAction.removeTag, l10n.removeTag),
    if (room != null && single!.contact == null && room.membership == .invite)
      (_MoreAction.block, l10n.block),
  ];
}

/// Pins every selected chat when [pin], else unpins them, then ends the
/// selection.
Future<void> setSelectedPinned(
  ChatListController controller,
  List<SelectedChat> chats,
  bool pin,
) async {
  final rooms = [
    for (final chat in chats)
      for (final room in chat.rooms)
        if (room.isFavourite != pin) room,
  ];
  await showFutureLoadingDialog(
    context: controller.context,
    future: () => Future.wait(rooms.map((room) => room.setFavourite(pin))),
  );
  controller.clearSelection();
}

/// Mutes every selected chat when [mute] (mentions still notify), else
/// turns their notifications back on, then ends the selection.
Future<void> setSelectedMuted(
  ChatListController controller,
  List<SelectedChat> chats,
  bool mute,
) async {
  final rooms = [
    for (final chat in chats)
      for (final room in chat.rooms)
        if ((room.cachedPushRuleState == PushRuleState.notify) == mute) room,
  ];
  await showFutureLoadingDialog(
    context: controller.context,
    future: () => Future.wait(
      rooms.map(
        (room) => room.setPushRuleState(
          mute ? PushRuleState.mentionsOnly : PushRuleState.notify,
        ),
      ),
    ),
  );
  controller.clearSelection();
}

/// Marks every selected chat read when [read], else unread, then ends the
/// selection. A merged contact is marked unread through its `send_via`
/// room, as one marked room is enough to light up the contact.
Future<void> setSelectedRead(
  ChatListController controller,
  List<SelectedChat> chats,
  bool read,
) async {
  await showFutureLoadingDialog(
    context: controller.context,
    future: () => Future.wait([
      for (final chat in chats)
        if (read)
          ...chat.rooms.map(markRoomRead)
        else if (!chat.isUnread)
          (chat.contact?.sendViaRoom ?? chat.room).markUnread(true),
    ]),
  );
  controller.clearSelection();
}

/// Asks, then leaves every room of the selected chats (declining the
/// invites among them) and ends the selection.
Future<void> leaveSelected(
  ChatListController controller,
  List<SelectedChat> chats,
) async {
  final context = controller.context;
  final l10n = L10n.of(context);
  final rooms = [for (final chat in chats) ...chat.rooms];
  final confirmed = await showOkCancelAlertDialog(
    context: context,
    title: rooms.length == 1
        ? l10n.areYouSure
        : l10n.leaveChatsQuestion(rooms.length),
    message: l10n.archiveRoomDescription,
    okLabel: l10n.leave,
    cancelLabel: l10n.cancel,
    isDestructive: true,
  );
  if (confirmed != OkCancelResult.ok || !context.mounted) return;
  await showFutureLoadingDialog(
    context: context,
    future: () async {
      for (final room in rooms) {
        await room.leave();
      }
    },
  );
  controller.clearSelection();
}

/// Merges the selected chats into one conversation: into the first merged
/// contact among them when there is one (see [mergeAnchor]), else into a
/// new one. Then ends the selection.
Future<void> mergeSelected(
  ChatListController controller,
  List<SelectedChat> chats,
) async {
  final client = chats.first.room.client;
  final groups = [for (final chat in chats) chat.rooms];
  final anchor = mergeAnchor(groups);
  final into = chats[groups.indexOf(anchor)].contact;
  final roomIds = [
    for (final room in anchor) room.id,
    for (final group in groups)
      if (!identical(group, anchor)) ...group.map((room) => room.id),
  ];
  await showFutureLoadingDialog(
    context: controller.context,
    future: () => MergedContactsStore.forClient(
      client,
    ).merge(roomIds, intoContactId: into?.id),
  );
  controller.clearSelection();
}

Future<void> _onMore(
  ChatListController controller,
  List<SelectedChat> chats,
  _MoreAction action,
) async {
  final context = controller.context;
  final l10n = L10n.of(context);
  final room = chats.first.room;
  final client = room.client;
  final rooms = [for (final chat in chats) ...chat.rooms];

  switch (action) {
    case _MoreAction.openInNewWindow:
      controller.openInNewWindow(room);
      controller.clearSelection();
    case _MoreAction.mergeWith:
      controller.clearSelection();
      await mergeChatWith(controller, room);
    case _MoreAction.manage:
      controller.clearSelection();
      await showManageMergedContactSheet(context, chats.single.contact!.id);
    case _MoreAction.unmerge:
      if (await confirmUnmerge(context, client, chats.single.contact!.id)) {
        controller.clearSelection();
      }
    case _MoreAction.mergeSelected:
      await mergeSelected(controller, chats);
    case _MoreAction.goToSpace:
      final space = spacesByChild(client)[room.id];
      controller.clearSelection();
      if (space != null) await controller.setActiveSpace(space.id);
    case _MoreAction.addToSpace:
      final spaces = _spacesToAddTo(client, rooms);
      final space = await showModalActionPopup(
        context: context,
        title: l10n.space,
        actions: [
          for (final space in spaces)
            AdaptiveModalAction(
              value: space,
              label: space.getLocalizedDisplayname(MatrixLocals(l10n)),
            ),
        ],
      );
      if (space == null || !context.mounted) return;
      await showFutureLoadingDialog(
        context: context,
        future: () async {
          for (final room in rooms) {
            if (space.spaceChildren.any((c) => c.roomId == room.id)) continue;
            await space.setSpaceChild(room.id);
          }
        },
      );
      controller.clearSelection();
    case _MoreAction.lowPriority:
      final set = !chats.every((chat) => chat.isLowPriority);
      await showFutureLoadingDialog(
        context: context,
        future: () => Future.wait([
          for (final room in rooms)
            if (room.isLowPriority != set) room.setLowPriority(set),
        ]),
      );
      controller.clearSelection();
    case _MoreAction.addTag:
      final existingTags = List.of(controller.roomTags.keys);
      existingTags.removeWhere(room.tags.containsKey);
      String? tag;
      if (existingTags.isNotEmpty) {
        tag = await showModalActionPopup<String?>(
          context: context,
          actions: [
            ...existingTags.map((tag) {
              final displayTag = tag.replaceFirst('u.', '');
              return AdaptiveModalAction(label: displayTag, value: displayTag);
            }),
            AdaptiveModalAction(label: l10n.createNewTag, value: null),
          ],
        );
        if (!context.mounted) return;
      }
      tag ??= await showTextInputDialog(
        context: context,
        title: l10n.addTag,
        hintText: l10n.tagName,
      );
      final newTag = tag;
      if (!context.mounted || newTag == null) return;
      await showFutureLoadingDialog(
        context: context,
        future: () => room.addTag('u.$newTag'),
      );
      controller.clearSelection();
    case _MoreAction.removeTag:
      await showFutureLoadingDialog(
        context: context,
        future: () => room.removeTag(controller.activeTag!),
      );
      controller.clearSelection();
    case _MoreAction.block:
      final inviteEvent = await room.requestUser(client.userID!);
      if (!context.mounted) return;
      controller.clearSelection();
      context.go(
        '/rooms/settings/security/ignorelist',
        extra: inviteEvent?.senderId,
      );
  }
}

/// Stands in for a selected chat's avatar: a check in a filled circle.
class SelectedChatMark extends StatelessWidget {
  final double size;

  const SelectedChatMark({required this.size, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: theme.colorScheme.primaryContainer,
        shape: BoxShape.circle,
      ),
      child: Icon(
        Icons.check,
        size: size * 0.5,
        color: theme.colorScheme.onPrimaryContainer,
      ),
    );
  }
}

/// Swaps [child], a chat's avatar, for a [SelectedChatMark] of [size] while
/// [selected], with a quick flip-like scale.
class SelectableAvatar extends StatelessWidget {
  final bool selected;
  final double size;
  final Widget child;

  const SelectableAvatar({
    required this.selected,
    required this.size,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: FluffyThemes.animationDuration,
    switchInCurve: FluffyThemes.animationCurve,
    switchOutCurve: FluffyThemes.animationCurve,
    transitionBuilder: (child, animation) =>
        ScaleTransition(scale: animation, child: child),
    child: selected
        ? SelectedChatMark(key: const ValueKey(true), size: size)
        : KeyedSubtree(key: const ValueKey(false), child: child),
  );
}
