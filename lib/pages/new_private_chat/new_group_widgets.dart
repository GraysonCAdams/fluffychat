// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';

/// The people picked for a group as removable chips, after the icon of the
/// network they are added on.
class GroupRecipientsBar extends StatelessWidget {
  final GroupDraft draft;

  const GroupRecipientsBar(this.draft, {super.key});

  @override
  Widget build(BuildContext context) {
    final bridge = draft.bridge;
    if (bridge == null) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        spacing: 12,
        children: [
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Tooltip(
              message: bridge.displayName,
              child: Avatar(
                key: const ValueKey('group-network'),
                mxContent: bridge.icon,
                name: bridge.displayName,
                size: 32,
                borderRadius: BorderRadius.circular(8),
              ),
            ),
          ),
          Expanded(
            child: Wrap(
              spacing: 8,
              runSpacing: 4,
              children: [
                for (final member in draft.members)
                  InputChip(
                    key: ValueKey('group-chip-${member.key}'),
                    avatar: Avatar(
                      mxContent: member.person.avatar,
                      name: member.person.name,
                      size: 24,
                    ),
                    label: Text(member.person.name),
                    deleteButtonTooltipMessage: l10n.remove,
                    onDeleted: () => draft.remove(member.key),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
