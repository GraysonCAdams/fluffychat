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

/// What the user confirmed in [NewGroupSheet].
typedef NewGroupConfirmation = ({String name});

/// The confirm step of a new group: the network, the people and, when the
/// network takes one, a name. Pops a [NewGroupConfirmation] from the
/// button, which reads [actionLabel].
class NewGroupSheet extends StatefulWidget {
  final GroupNetwork network;
  final List<GroupMember> members;
  final String actionLabel;

  const NewGroupSheet({
    required this.network,
    required this.members,
    required this.actionLabel,
    super.key,
  });

  @override
  State<NewGroupSheet> createState() => _NewGroupSheetState();
}

class _NewGroupSheetState extends State<NewGroupSheet> {
  final TextEditingController _name = TextEditingController();

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final bridge = widget.network.bridge;
    final type = widget.network.type;
    final canCreate = !type.nameRequired || _name.text.trim().isNotEmpty;
    return SafeArea(
      child: Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            ListTile(
              title: Text(
                l10n.newGroupChat,
                style: theme.textTheme.titleMedium,
              ),
            ),
            ListTile(
              leading: Avatar(
                mxContent: bridge.icon,
                name: bridge.displayName,
                size: 32,
                borderRadius: BorderRadius.circular(8),
              ),
              title: Text(bridge.displayName),
              subtitle: Text(
                widget.members.map((member) => member.person.name).join(', '),
              ),
            ),
            if (type.nameAllowed)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: TextField(
                  key: const ValueKey('group-name'),
                  controller: _name,
                  onChanged: (_) => setState(() {}),
                  textCapitalization: TextCapitalization.sentences,
                  decoration: InputDecoration(
                    labelText: type.nameRequired
                        ? l10n.groupName
                        : l10n.groupNameOptional,
                    helperText: bridge.name == 'gmessages'
                        ? l10n.groupNameRcsOnly
                        : null,
                  ),
                ),
              ),
            Padding(
              padding: const EdgeInsets.all(16),
              child: FilledButton(
                style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48),
                ),
                onPressed: canCreate
                    ? () => Navigator.of(
                        context,
                      ).pop<NewGroupConfirmation>((name: _name.text.trim()))
                    : null,
                child: Text(widget.actionLabel),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
