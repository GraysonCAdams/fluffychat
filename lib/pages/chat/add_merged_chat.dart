// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/network_toggle_group.dart';
import 'package:fluffychat/pages/chat_list/merged_contact_actions.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merge_rules.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The last segment of the app bar's network switcher: a dashed plus that
/// offers to merge another chat into the open one. With no chat that
/// qualifies (see [mergeCandidates]) it says so in a dialog.
class AddMergedChatButton extends StatefulWidget {
  final ChatController controller;
  final double width;
  final double height;

  const AddMergedChatButton(
    this.controller, {
    required this.width,
    required this.height,
    super.key,
  });

  @override
  State<AddMergedChatButton> createState() => _AddMergedChatButtonState();
}

class _AddMergedChatButtonState extends State<AddMergedChatButton> {
  late final MergedContactsStore _store = MergedContactsStore.forClient(
    widget.controller.room.client,
  );
  List<Room> _candidates = const [];

  List<Room> get _current {
    final controller = widget.controller;
    return controller.isMerged
        ? controller.mergedContact?.rooms ?? [controller.room]
        : [controller.room];
  }

  @override
  void initState() {
    super.initState();
    _store.revision.addListener(_refresh);
    _candidates = mergeCandidates(widget.controller.room.client, _current);
  }

  @override
  void dispose() {
    _store.revision.removeListener(_refresh);
    super.dispose();
  }

  void _refresh() {
    if (!mounted) return;
    setState(() {
      _candidates = mergeCandidates(widget.controller.room.client, _current);
    });
  }

  Future<void> _open() async {
    final controller = widget.controller;
    if (_candidates.isEmpty) {
      final l10n = L10n.of(context);
      await showOkAlertDialog(
        context: context,
        title: l10n.noChatsToAdd,
        message: controller.room.isDirectChat
            ? l10n.noMatchingChatByNumber
            : l10n.noMatchingChatByGroupName,
      );
      return;
    }
    final picked = await showModalBottomSheet<Room>(
      context: context,
      useRootNavigator: true,
      showDragHandle: true,
      builder: (context) => _AddChatSheet(
        name: controller.isMerged
            ? controller.mergedContact?.displayName(
                    MatrixLocals(L10n.of(context)),
                  ) ??
                  controller.room.getLocalizedDisplayname(
                    MatrixLocals(L10n.of(context)),
                  )
            : controller.room.getLocalizedDisplayname(
                MatrixLocals(L10n.of(context)),
              ),
        isGroup: !controller.room.isDirectChat,
        candidates: _candidates,
      ),
    );
    if (picked == null || !mounted) return;
    final contact = controller.isMerged ? controller.mergedContact : null;
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final router = GoRouter.of(context);
    try {
      final id = contact == null
          ? await _store.merge([controller.room.id, picked.id])
          : await _store.merge([picked.id], intoContactId: contact.id);
      // An unmerged chat becomes a merged conversation with a route of its
      // own; an already merged one picks the new room up by itself.
      if (contact == null) router.go(mergedContactRoute(id));
    } catch (e) {
      scaffoldMessenger.showSnackBar(SnackBar(content: Text(e.toString())));
    }
  }

  @override
  Widget build(BuildContext context) => DashedAddSegment(
    tooltip: L10n.of(context).chooseChatsToMerge,
    onTap: _open,
    width: widget.width,
    height: widget.height,
  );
}

class _AddChatSheet extends StatelessWidget {
  final String name;
  final bool isGroup;
  final List<Room> candidates;

  const _AddChatSheet({
    required this.name,
    required this.isGroup,
    required this.candidates,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final locals = MatrixLocals(l10n);
    final spaces = spacesByChild(candidates.first.client);
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 4),
            child: Text(
              l10n.addChatToNamed(name),
              style: theme.textTheme.titleMedium,
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
            child: Text(
              isGroup
                  ? l10n.sameGroupNameOtherNetworks
                  : l10n.sameNumberOtherNetworks,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          Flexible(
            child: ListView(
              shrinkWrap: true,
              children: [
                for (final room in candidates)
                  ListTile(
                    contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                    leading: Avatar(
                      name: room.getLocalizedDisplayname(locals),
                      mxContent: room.avatar,
                    ),
                    title: Text(
                      room.getLocalizedDisplayname(locals),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(networkName(room, spaces[room.id], locals)),
                    trailing: FilledButton.tonal(
                      onPressed: () => Navigator.of(context).pop(room),
                      child: Text(l10n.addChat),
                    ),
                  ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
