// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/merged_network_menu.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/phone_number.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/widgets/merged_contacts/manage_merged_contact_sheet.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Opens the details of the chat shown. A merged chat ([mergedContact] set)
/// first asks which network's room to open, or offers its linked chats; a
/// single chat opens its details at once, in the side column when three
/// columns fit ([toggleDetailsColumn]).
///
/// A network's details are pushed over the merged chat, so going back lands
/// on the same merged view with its send-via pick untouched. Going to the
/// nested `/rooms/<id>/details` route would rebuild the stack under it as
/// that one room's chat.
Future<void> openChatDetails(
  BuildContext context, {
  required Room room,
  MergedContact? mergedContact,
  required VoidCallback toggleDetailsColumn,
}) async {
  if (mergedContact == null) {
    if (FluffyThemes.isThreeColumnMode(context)) {
      toggleDetailsColumn();
    } else {
      context.go('/rooms/${room.id}/details');
    }
    return;
  }
  final pick = await showAdaptiveBottomSheet<ChatDetailsPick>(
    context: context,
    builder: (context) => ChatDetailsNetworkSheet(contact: mergedContact),
  );
  if (pick == null || !context.mounted) return;
  switch (pick) {
    case NetworkDetailsPick(:final roomId):
      await context.push('/rooms/$roomId/details');
    case LinkedChatsPick():
      await showManageMergedContactSheet(context, mergedContact.id);
  }
}

/// What was picked in [ChatDetailsNetworkSheet].
sealed class ChatDetailsPick {
  const ChatDetailsPick();
}

/// The details of one network's room.
final class NetworkDetailsPick extends ChatDetailsPick {
  final String roomId;

  const NetworkDetailsPick(this.roomId);
}

/// The sheet that adds, removes or unlinks the contact's chats.
final class LinkedChatsPick extends ChatDetailsPick {
  const LinkedChatsPick();
}

/// Lists a merged contact's networks, each opening that room's details, and
/// a last row for the contact's linked chats. Closes with the
/// [ChatDetailsPick] tapped.
class ChatDetailsNetworkSheet extends StatelessWidget {
  final MergedContact contact;

  const ChatDetailsNetworkSheet({required this.contact, super.key});

  static const _iconSize = 40.0;

  /// The person as [room]'s network knows them: their phone number when
  /// known, else the chat's name.
  static String _identifierOn(Room room, MatrixLocals locals) {
    final phone = MergeSuggestionService.forClient(room.client).phoneOf(room);
    if (phone != null) return formatPhoneForDisplay(phone.value);
    return room.getLocalizedDisplayname(locals);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final locals = MatrixLocals(l10n);
    final networks = MergedNetwork.of(contact, locals);
    return SafeArea(
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 24, 24, 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                spacing: 4,
                children: [
                  Text(l10n.chatDetails, style: theme.textTheme.titleLarge),
                  Text(
                    l10n.chooseNetwork,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
            for (final network in networks)
              ListTile(
                contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                leading: network.icon(size: _iconSize),
                title: Text(
                  network.name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                subtitle: Text(
                  _identifierOn(network.room, locals),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(
                  context,
                ).pop(NetworkDetailsPick(network.room.id)),
              ),
            const Divider(),
            ListTile(
              contentPadding: const EdgeInsets.symmetric(horizontal: 24),
              leading: CircleAvatar(
                radius: _iconSize / 2,
                backgroundColor: theme.colorScheme.surfaceContainerHighest,
                foregroundColor: theme.colorScheme.onSurfaceVariant,
                child: const Icon(Icons.link),
              ),
              title: Text(l10n.linkedChats),
              subtitle: Text(l10n.linkedChatsDescription),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => Navigator.of(context).pop(const LinkedChatsPick()),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
