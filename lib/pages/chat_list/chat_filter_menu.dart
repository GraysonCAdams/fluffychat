// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The network the chat list is narrowed to, if any. Inside a space the
/// space itself narrows the list, so no network applies.
Room? _network(ChatListController controller) {
  final id = controller.sourceSpaceId;
  if (id == null || controller.activeSpaceId != null) return null;
  return Matrix.of(controller.context).client.getRoomById(id);
}

/// What the chat list shows, as its title says it: "All chats", a filter
/// ("Unread", "Groups", "People" or a tag), a network's name, or a filter
/// and a network together ("Unread · WhatsApp").
String chatFilterLabel(BuildContext context, ChatListController controller) {
  final l10n = L10n.of(context);
  final filter = controller.activeFilter;
  final network = _network(controller);
  final parts = [
    if (filter == ActiveFilter.tag)
      controller.activeTag!.replaceFirst('u.', '')
    else if (filter != ActiveFilter.allChats)
      filter.toLocalizedString(context),
    if (network != null) network.getLocalizedDisplayname(MatrixLocals(l10n)),
  ];
  return parts.isEmpty ? l10n.allChats : parts.join(' · ');
}

/// Opens the chat filter menu under [anchor]: All chats, Unread, Groups and
/// People, then the networks (the spaces, which for bridged networks are
/// the networks themselves) and the user's tags. The kind of chat and the
/// network combine, as each narrows the list on its own; the active ones
/// carry a check, and picking a checked one again clears it.
Future<void> showChatFilterMenu(
  BuildContext anchor,
  ChatListController controller,
) async {
  final l10n = L10n.of(anchor);
  final theme = Theme.of(anchor);
  final locals = MatrixLocals(l10n);
  final client = Matrix.of(controller.context).client;
  // The menu opens in the chat list's navigator, which the Windows title
  // bar sits outside of, so the anchor is placed through global positions.
  final navigator = Navigator.of(controller.context);
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final origin = overlay.globalToLocal(
    box.localToGlobal(Offset(0, box.size.height + 4)),
  );
  final filter = controller.activeFilter;
  final network = _network(controller);
  final networks = controller.activeSpaceId == null
      ? controller.spaces
      : const <Room>[];
  final tags = controller.roomTags.keys.toList();

  PopupMenuEntry<String> heading(String text) => PopupMenuItem(
    enabled: false,
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text(
      text,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );

  final picked = await showMenu<String>(
    context: navigator.context,
    position: RelativeRect.fromLTRB(
      origin.dx,
      origin.dy,
      overlay.size.width - origin.dx,
      0,
    ),
    // Material menu metrics: 48 high rows, 12 side padding, and a width
    // that follows the longest row between 112 and 280.
    constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
    items: [
      chatMenuItem(
        value: 'filter:${ActiveFilter.allChats.name}',
        leading: const Icon(Icons.forum_outlined),
        label: l10n.allChats,
        checked: filter == ActiveFilter.allChats && network == null,
      ),
      for (final (kind, icon) in [
        (ActiveFilter.unread, Icons.mark_chat_unread_outlined),
        (ActiveFilter.groups, Icons.group_outlined),
        (ActiveFilter.messages, Icons.person_outlined),
      ])
        chatMenuItem(
          value: 'filter:${kind.name}',
          leading: Icon(icon),
          label: kind.toLocalizedString(anchor),
          checked: filter == kind,
        ),
      if (networks.isNotEmpty) ...[
        const PopupMenuDivider(),
        heading(l10n.networks),
        for (final space in networks)
          chatMenuItem(
            value: 'network:${space.id}',
            leading: _networkAvatar(space, locals),
            label: space.getLocalizedDisplayname(locals),
            checked: space.id == network?.id,
          ),
      ],
      if (tags.isNotEmpty) ...[
        const PopupMenuDivider(),
        heading(l10n.chatFilterTags),
        for (final tag in tags)
          chatMenuItem(
            value: 'tag:$tag',
            leading: const Icon(Icons.label_outlined),
            label: tag.replaceFirst('u.', ''),
            checked: filter == ActiveFilter.tag && controller.activeTag == tag,
          ),
      ],
    ],
  );
  if (picked == null || !controller.mounted) return;
  final separator = picked.indexOf(':');
  final kind = picked.substring(0, separator);
  final value = picked.substring(separator + 1);
  switch (kind) {
    case 'filter':
      final chosen = ActiveFilter.values.byName(value);
      if (chosen == ActiveFilter.allChats) {
        controller.setActiveFilter(ActiveFilter.allChats, null);
        controller.setSourceSpace(null);
      } else {
        controller.setActiveFilter(
          chosen == filter ? ActiveFilter.allChats : chosen,
          null,
        );
      }
    case 'network':
      controller.setSourceSpace(
        value == network?.id ? null : client.getRoomById(value)?.id,
      );
    case 'tag':
      if (filter == ActiveFilter.tag && controller.activeTag == value) {
        controller.setActiveFilter(ActiveFilter.allChats, null);
      } else {
        controller.setActiveFilter(ActiveFilter.tag, value);
      }
  }
}

/// A row of the chat list's menus: [leading] in a 24 box, [label], and a
/// check at the end while [checked], on Material's 48 high rows with 12 of
/// side padding.
PopupMenuItem<String> chatMenuItem({
  required String value,
  required Widget leading,
  required String label,
  required bool checked,
}) => PopupMenuItem(
  value: value,
  height: 48,
  padding: const EdgeInsets.symmetric(horizontal: 12),
  child: Semantics(
    selected: checked,
    child: Row(
      children: [
        SizedBox.square(dimension: 24, child: Center(child: leading)),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
        const SizedBox(width: 12),
        // Keeps every row the same width whether or not it is checked.
        SizedBox(
          width: 24,
          child: checked ? const Icon(Icons.check, size: 20) : null,
        ),
      ],
    ),
  ),
);

Widget _networkAvatar(Room space, MatrixLocals locals) => Avatar(
  mxContent: space.avatar,
  name: space.getLocalizedDisplayname(locals),
  size: 24,
  borderRadius: BorderRadius.circular(6),
);

/// The chat list's title as a dropdown: what the list shows (see
/// [chatFilterLabel]) and an arrow, opening [showChatFilterMenu] on a tap,
/// or on Enter or Space once focused. A screen reader hears it as a
/// button, "Filter chats, All chats selected".
class ChatFilterButton extends StatelessWidget {
  final ChatListController controller;

  /// The title's text style; the theme's large title when null.
  final TextStyle? style;

  /// The widest the button grows; a longer label is cut short.
  final double maxWidth;

  /// What the button reads while nothing is filtered, in place of "All
  /// chats": the desktop title says "Chats". A screen reader still hears
  /// "All chats".
  final String? unfilteredText;

  const ChatFilterButton({
    required this.controller,
    this.style,
    this.maxWidth = 240,
    this.unfilteredText,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = chatFilterLabel(context, controller);
    final unfiltered =
        controller.activeFilter == ActiveFilter.allChats &&
        label == L10n.of(context).allChats;
    final text = unfiltered ? unfilteredText ?? label : label;
    final textStyle = style ?? theme.textTheme.titleLarge;
    // One node: this label, with the InkWell's tap and focus.
    return Semantics(
      button: true,
      label: L10n.of(context).filterChatsSelected(label),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: InkWell(
          borderRadius: BorderRadius.circular(8),
          onTap: () => showChatFilterMenu(context, controller),
          child: ExcludeSemantics(
            child: Padding(
              // Flush with the edge the title would start at.
              padding: const EdgeInsetsDirectional.fromSTEB(0, 4, 4, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      text,
                      style: textStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.arrow_drop_down,
                    color: textStyle?.color ?? theme.colorScheme.onSurface,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
