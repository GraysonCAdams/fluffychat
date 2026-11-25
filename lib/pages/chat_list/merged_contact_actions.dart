// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/merged_contacts/conversation.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/merged_contacts/merge_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The route of the merged chat screen of [contactId].
String mergedContactRoute(String contactId) => '/rooms/contact/$contactId';

/// Opens [contact]'s merged chat screen: all of its rooms in one timeline.
void openMergedContact(BuildContext context, MergedContact contact) =>
    context.go(mergedContactRoute(contact.id));

/// Whether [activeChat], the chat list's active chat, is [contact]: its
/// merged screen or one of its rooms on its own.
bool isMergedContactActive(MergedContact contact, String? activeChat) =>
    activeChat != null &&
    (activeChat == mergedContactActiveChat(contact.id) ||
        contact.roomIds.contains(activeChat));

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
