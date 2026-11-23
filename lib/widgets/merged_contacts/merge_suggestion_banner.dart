// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/widgets/merged_contacts/merge_suggestion_card.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Above the chat list: the first merge suggestion, with a link to the
/// rest. The service orders them, same phone number or email ahead of same
/// name only.
///
/// Only this widget listens to the suggestions, so a new suggestion
/// rebuilds the banner and not the list.
class MergeSuggestionBanner extends StatelessWidget {
  final Client client;

  const MergeSuggestionBanner({required this.client, super.key});

  @override
  Widget build(BuildContext context) {
    final service = MergeSuggestionService.forClient(client);
    return ValueListenableBuilder(
      valueListenable: service.suggestions,
      builder: (context, suggestions, _) {
        final pending = suggestions;
        if (pending.isEmpty) return const SizedBox.shrink();
        return MergeSuggestionCard(
          key: ValueKey(pending.first.roomIds.join()),
          client: client,
          suggestion: pending.first,
          footer: pending.length < 2
              ? null
              : Align(
                  alignment: Alignment.centerRight,
                  child: TextButton(
                    onPressed: () =>
                        context.go('/rooms/settings/chat/merged_contacts'),
                    child: Text(
                      L10n.of(context).moreMergeSuggestions(pending.length - 1),
                    ),
                  ),
                ),
        );
      },
    );
  }
}
