// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/contact_identifiers.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/phone_number.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggester.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// What a suggestion matched on, as shown with it: "Same number: +1 404
/// 555 1234".
String describeMatch(L10n l10n, ContactIdentifier identifier) =>
    switch (identifier.type) {
      IdentifierType.phone => l10n.sameNumber(
        formatPhoneForDisplay(identifier.value),
      ),
      IdentifierType.email => l10n.sameEmail(identifier.value),
      IdentifierType.name => l10n.sameName,
    };

/// Moves on to the next suggestion at once while [write] is still on its
/// way to the server. The store shows a change before it is saved and puts
/// the previous state back if saving fails, which brings the suggestion
/// back; the snack bar says why it reappeared.
void _showNextWhileSaving(
  BuildContext context,
  Client client,
  Future<void> write,
) {
  final messenger = ScaffoldMessenger.of(context);
  final failed = L10n.of(context).oopsSomethingWentWrong;
  final service = MergeSuggestionService.forClient(client);
  service.recomputeNow();
  () async {
    try {
      await write;
    } catch (_) {
      service.recomputeNow();
      messenger.showSnackBar(SnackBar(content: Text(failed)));
    }
  }();
}

/// Merges the rooms of [suggestion], into its existing contact if it has
/// one, and keeps a phone or email match as the contact's identifier.
void acceptSuggestion(
  BuildContext context,
  Client client,
  MergeSuggestion suggestion,
) => _showNextWhileSaving(
  context,
  client,
  MergedContactsStore.forClient(client).merge(
    suggestion.roomIds,
    intoContactId: suggestion.existingContactId,
    identifier: suggestion.strong ? suggestion.matchedOn.toJson() : null,
  ),
);

/// Remembers every pair of [suggestion]'s rooms as different people.
void dismissSuggestion(
  BuildContext context,
  Client client,
  MergeSuggestion suggestion,
) {
  final rooms = suggestion.roomIds;
  _showNextWhileSaving(
    context,
    client,
    MergedContactsStore.forClient(client).dismissSuggestions([
      for (var i = 0; i < rooms.length; i++)
        for (var j = i + 1; j < rooms.length; j++) (rooms[i], rooms[j]),
    ]),
  );
}

/// One suggestion: the chats with their networks, what they matched on, and
/// buttons to merge or dismiss them.
class MergeSuggestionCard extends StatelessWidget {
  final Client client;
  final MergeSuggestion suggestion;

  /// Shown under the buttons, for example a link to further suggestions.
  final Widget? footer;

  const MergeSuggestionCard({
    required this.client,
    required this.suggestion,
    this.footer,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final locals = MatrixLocals(l10n);
    final spaces = spacesByChild(client);
    final rooms = [
      for (final id in suggestion.roomIds) ?client.getRoomById(id),
    ];
    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      color: theme.colorScheme.secondaryContainer,
      elevation: 0,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.samePersonQuestion,
              style: theme.textTheme.titleSmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            Text(
              describeMatch(l10n, suggestion.matchedOn),
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSecondaryContainer,
              ),
            ),
            const SizedBox(height: 8),
            for (final room in rooms)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Row(
                  children: [
                    Avatar(
                      mxContent: room.chatAvatar,
                      name: room.chatDisplayname(locals),
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        '${room.chatDisplayname(locals)} '
                        '(${networkName(room, spaces[room.id], locals)})',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: theme.colorScheme.onSecondaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () =>
                      dismissSuggestion(context, client, suggestion),
                  child: Text(l10n.notTheSamePerson),
                ),
                const SizedBox(width: 4),
                FilledButton(
                  onPressed: () =>
                      acceptSuggestion(context, client, suggestion),
                  child: Text(l10n.merge),
                ),
              ],
            ),
            ?footer,
          ],
        ),
      ),
    );
  }
}
