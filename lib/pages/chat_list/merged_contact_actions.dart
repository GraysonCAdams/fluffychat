// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/model.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/merged_contacts/manage_merged_contact_sheet.dart';
import 'package:fluffychat/widgets/merged_contacts/merge_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Opens [contact]'s chat: the room new messages go to, with the contact's
/// other networks a tap away in the app bar.
void openMergedContact(BuildContext context, MergedContact contact) {
  final room = contact.entry.sendMode == SendMode.lastReceived
      ? contact.lastReceivedRoom ?? contact.sendViaRoom
      : contact.sendViaRoom;
  context.go('/rooms/${room.id}');
}

/// The value the chat list gets as its active chat while a merged contact's
/// screen is open, so the contact's tile is highlighted. It cannot clash
/// with a room ID, which starts with "!".
String mergedContactActiveChat(String contactId) => 'contact:$contactId';

/// Whether [activeChat], the chat list's active chat, is [contact]: its
/// merged screen or one of its rooms on its own.
bool isMergedContactActive(MergedContact contact, String? activeChat) =>
    activeChat != null &&
    (activeChat == mergedContactActiveChat(contact.id) ||
        contact.roomIds.contains(activeChat));

enum _ContactAction { manage, mute, markUnread, favorite, unmerge }

/// The long press menu of a merged contact's tile: manage and unmerge, and
/// the usual chat actions applied to every room of the contact.
Future<void> mergedContactContextAction(
  ChatListController controller,
  MergedContact contact,
  BuildContext posContext, [
  Offset? globalPosition,
]) async {
  final context = controller.context;
  final l10n = L10n.of(context);
  final overlay =
      Overlay.of(posContext).context.findRenderObject() as RenderBox;
  final Rect anchor;
  if (globalPosition != null) {
    anchor = overlay.globalToLocal(globalPosition) & Size.zero;
  } else {
    final button = posContext.findRenderObject() as RenderBox;
    anchor =
        button.localToGlobal(
          button.size.bottomLeft(Offset.zero),
          ancestor: overlay,
        ) &
        Size(button.size.width, 0);
  }
  final muted = contact.isMuted;
  final unread = contact.markedUnread || contact.isUnread;
  final pinned = contact.isFavourite;

  PopupMenuItem<_ContactAction> item(
    _ContactAction value,
    IconData icon,
    String label, {
    Color? color,
  }) => PopupMenuItem(
    value: value,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: color),
        const SizedBox(width: 12),
        Text(label, style: color == null ? null : TextStyle(color: color)),
      ],
    ),
  );

  final action = await showMenu<_ContactAction>(
    context: posContext,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    items: [
      item(_ContactAction.manage, Icons.tune_outlined, l10n.manageContact),
      item(
        _ContactAction.mute,
        muted ? Icons.notifications_off : Icons.notifications_off_outlined,
        muted ? l10n.unmuteChat : l10n.muteChat,
      ),
      item(
        _ContactAction.markUnread,
        unread ? Icons.mark_as_unread : Icons.mark_as_unread_outlined,
        unread ? l10n.markAsRead : l10n.markAsUnread,
      ),
      item(
        _ContactAction.favorite,
        pinned ? Icons.push_pin : Icons.push_pin_outlined,
        pinned ? l10n.unpin : l10n.pin,
      ),
      item(
        _ContactAction.unmerge,
        Icons.call_split_outlined,
        l10n.unmerge,
        color: Theme.of(context).colorScheme.onErrorContainer,
      ),
    ],
  );
  if (action == null || !context.mounted) return;
  switch (action) {
    case _ContactAction.manage:
      await showManageMergedContactSheet(context, contact.id);
    case _ContactAction.mute:
      await showFutureLoadingDialog(
        context: context,
        future: () => Future.wait(
          contact.rooms.map(
            (room) => room.setPushRuleState(
              muted ? PushRuleState.notify : PushRuleState.mentionsOnly,
            ),
          ),
        ),
      );
    case _ContactAction.markUnread:
      await showFutureLoadingDialog(
        context: context,
        future: () => Future.wait(
          contact.rooms.map((room) async {
            if (!unread) {
              // Marking unread once is enough to light up the contact.
              if (room == contact.sendViaRoom) await room.markUnread(true);
              return;
            }
            if (room.markedUnread) await room.markUnread(false);
            final eventId = room.lastEvent?.eventId;
            if (eventId == null || !room.isUnread) return;
            await room.setReadMarker(
              eventId,
              mRead: eventId,
              public: AppSettings.sendPublicReadReceipts.value,
            );
          }),
        ),
      );
    case _ContactAction.favorite:
      await showFutureLoadingDialog(
        context: context,
        future: () => Future.wait(
          contact.rooms
              .where((room) => room.isFavourite == pinned)
              .map((room) => room.setFavourite(!pinned)),
        ),
      );
    case _ContactAction.unmerge:
      await confirmUnmerge(context, contact.rooms.first.client, contact.id);
  }
}

/// Asks, then dissolves the contact. Returns whether it was unmerged.
Future<bool> confirmUnmerge(
  BuildContext context,
  Client client,
  String contactId,
) async {
  final l10n = L10n.of(context);
  final confirmed = await showOkCancelAlertDialog(
    context: context,
    title: l10n.unmergeContactQuestion,
    message: l10n.unmergeContactDescription,
    okLabel: l10n.unmerge,
    cancelLabel: l10n.cancel,
    isDestructive: true,
  );
  if (confirmed != OkCancelResult.ok || !context.mounted) return false;
  final result = await showFutureLoadingDialog(
    context: context,
    future: () => MergedContactsStore.forClient(client).unmerge(contactId),
  );
  return result.error == null;
}

/// "Merge with..." on a direct chat: picks the other chats and merges them
/// with [room] into one contact, or into the contact [room] is already in.
Future<void> mergeChatWith(ChatListController controller, Room room) async {
  final context = controller.context;
  final store = MergedContactsStore.forClient(room.client);
  final existing = store.contactForRoom(room.id);
  final picked = await showMergePicker(
    context,
    client: room.client,
    exclude: {room.id, ...?existing?.rooms},
  );
  if (picked == null || picked.isEmpty || !context.mounted) return;
  await showFutureLoadingDialog(
    context: context,
    future: () =>
        store.merge([room.id, ...picked], intoContactId: existing?.id),
  );
}
