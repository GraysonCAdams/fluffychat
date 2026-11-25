// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/model.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/merged_contacts/merge_picker.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Opens the sheet to manage the merged contact [contactId]: its name, its
/// networks and which one sends by default, how replies pick a network,
/// adding and removing chats, and unmerging.
Future<void> showManageMergedContactSheet(
  BuildContext context,
  String contactId,
) => showAdaptiveBottomSheet(
  context: context,
  builder: (context) => ManageMergedContactSheet(contactId: contactId),
);

class ManageMergedContactSheet extends StatelessWidget {
  final String contactId;

  const ManageMergedContactSheet({required this.contactId, super.key});

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final store = MergedContactsStore.forClient(client);
    return ValueListenableBuilder(
      valueListenable: store.revision,
      builder: (context, _, _) {
        final entry = store.contactById(contactId);
        final contact = entry == null
            ? null
            : MergedContact.resolve(client, entry);
        if (contact == null) {
          // Unmerged here or on another device while the sheet was open.
          return Scaffold(
            appBar: AppBar(leading: const CloseButton()),
            body: Center(child: Text(L10n.of(context).contactWasUnmerged)),
          );
        }
        return _ManageContact(store: store, contact: contact);
      },
    );
  }
}

class _ManageContact extends StatelessWidget {
  final MergedContactsStore store;
  final MergedContact contact;

  const _ManageContact({required this.store, required this.contact});

  Future<void> _rename(BuildContext context) async {
    final l10n = L10n.of(context);
    final name = await showTextInputDialog(
      context: context,
      title: l10n.renameContact,
      okLabel: l10n.ok,
      cancelLabel: l10n.cancel,
      initialText: contact.entry.name ?? '',
      hintText: contact.sendViaRoom.getLocalizedDisplayname(MatrixLocals(l10n)),
    );
    if (name == null || !context.mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => store.rename(contact.id, name),
    );
  }

  Future<void> _addChats(BuildContext context) async {
    final picked = await showMergePicker(
      context,
      client: contact.rooms.first.client,
      exclude: contact.roomIds.toSet(),
    );
    if (picked == null || picked.isEmpty || !context.mounted) return;
    await showFutureLoadingDialog(
      context: context,
      future: () => store.merge(picked, intoContactId: contact.id),
    );
  }

  Future<void> _remove(BuildContext context, String roomId) async {
    final l10n = L10n.of(context);
    if (contact.rooms.length <= 2) {
      final ok = await showOkCancelAlertDialog(
        context: context,
        title: l10n.unmergeContactQuestion,
        message: l10n.removingLastChatUnmerges,
        okLabel: l10n.remove,
        cancelLabel: l10n.cancel,
        isDestructive: true,
      );
      if (ok != OkCancelResult.ok || !context.mounted) return;
    }
    await showFutureLoadingDialog(
      context: context,
      future: () => store.removeRoom(roomId),
    );
  }

  Future<void> _unmerge(BuildContext context) async {
    final l10n = L10n.of(context);
    final ok = await showOkCancelAlertDialog(
      context: context,
      title: l10n.unmergeContactQuestion,
      message: l10n.unmergeContactDescription,
      okLabel: l10n.unmerge,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (ok != OkCancelResult.ok || !context.mounted) return;
    final result = await showFutureLoadingDialog(
      context: context,
      future: () => store.unmerge(contact.id),
    );
    if (result.error == null && context.mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final locals = MatrixLocals(l10n);
    final spaces = spacesByChild(contact.rooms.first.client);
    final sendVia = contact.sendViaRoom.id;
    final name = contact.displayName(locals);
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(l10n.manageContact),
      ),
      body: ListView(
        children: [
          ListTile(
            leading: Avatar(mxContent: contact.avatar, name: name),
            title: Text(name, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(
              contact.rooms
                  .map((room) => networkName(room, spaces[room.id], locals))
                  .join(', '),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            trailing: IconButton(
              tooltip: l10n.renameContact,
              icon: const Icon(Icons.edit_outlined),
              onPressed: () => _rename(context),
            ),
          ),
          const Divider(),
          ListTile(
            title: Text(
              l10n.networks,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
            subtitle: Text(l10n.defaultNetworkDescription),
          ),
          RadioGroup<String>(
            groupValue: sendVia,
            onChanged: (roomId) {
              if (roomId == null) return;
              showFutureLoadingDialog(
                context: context,
                future: () => store.setSendVia(contact.id, roomId),
              );
            },
            child: Column(
              children: [
                for (final room in contact.rooms)
                  ListTile(
                    leading: Radio<String>(value: room.id),
                    title: Text(
                      networkName(room, spaces[room.id], locals),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      room.getLocalizedDisplayname(locals),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onTap: () => showFutureLoadingDialog(
                      context: context,
                      future: () => store.setSendVia(contact.id, room.id),
                    ),
                    trailing: PopupMenuButton<String>(
                      onSelected: (action) {
                        switch (action) {
                          case 'details':
                            Navigator.of(context).pop();
                            // Pushed, so going back returns to the merged
                            // chat (or chat list) it was opened from.
                            context.push('/rooms/${room.id}/details');
                          case 'up':
                            store.reorderRoom(
                              contact.id,
                              room.id,
                              contact.entry.rooms.indexOf(room.id) - 1,
                            );
                          case 'remove':
                            _remove(context, room.id);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'details',
                          child: Text(l10n.chatDetails),
                        ),
                        if (contact.rooms.first != room)
                          PopupMenuItem(value: 'up', child: Text(l10n.moveUp)),
                        PopupMenuItem(
                          value: 'remove',
                          child: Text(l10n.removeFromContact),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.add_outlined),
            title: Text(l10n.addChatToContact),
            onTap: () => _addChats(context),
          ),
          const Divider(),
          ListTile(
            title: Text(
              l10n.replyNetwork,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.primary,
              ),
            ),
          ),
          RadioGroup<SendMode>(
            groupValue: contact.entry.sendMode,
            onChanged: (mode) {
              if (mode == null) return;
              showFutureLoadingDialog(
                context: context,
                future: () => store.setSendMode(contact.id, mode),
              );
            },
            child: Column(
              children: [
                RadioListTile<SendMode>(
                  value: SendMode.preferred,
                  title: Text(l10n.sendModePreferred),
                ),
                RadioListTile<SendMode>(
                  value: SendMode.lastReceived,
                  title: Text(l10n.sendModeLastReceived),
                ),
              ],
            ),
          ),
          SwitchListTile.adaptive(
            value: contact.entry.fallback,
            title: Text(l10n.offerFallback),
            subtitle: Text(l10n.offerFallbackDescription),
            onChanged: (value) => showFutureLoadingDialog(
              context: context,
              future: () => store.setFallback(contact.id, value),
            ),
          ),
          const Divider(),
          ListTile(
            leading: Icon(
              Icons.call_split_outlined,
              color: theme.colorScheme.error,
            ),
            title: Text(
              l10n.unmerge,
              style: TextStyle(color: theme.colorScheme.error),
            ),
            onTap: () => _unmerge(context),
          ),
        ],
      ),
    );
  }
}
