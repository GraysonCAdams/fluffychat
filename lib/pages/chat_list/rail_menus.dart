// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/push_rule_state_cache.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/notification_snooze.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

typedef _Action = Future<void> Function();

/// Opens the menu of the rail's All chats tile at [position], for a right
/// click or a long press: Mark all as read and Snooze notifications for
/// all chats, then the app's own pages under its name.
Future<void> showAllChatsRailMenu(
  BuildContext context,
  ChatListController controller,
  Offset position,
) {
  final l10n = L10n.of(context);
  final snoozed = notificationsSnoozedUntil != null;
  return _showRailMenu(context, position, [
    _heading(context, l10n.allChats),
    _item(
      Icons.mark_chat_read_outlined,
      l10n.markAllAsRead,
      controller.markAllAsRead,
      enabled: controller.unreadChats().isNotEmpty,
    ),
    _item(
      snoozed
          ? Icons.notifications_active_outlined
          : Icons.notifications_paused_outlined,
      snoozed ? l10n.resumeNotifications : l10n.snoozeNotifications,
      controller.toggleNotificationSnooze,
    ),
    const PopupMenuDivider(),
    _heading(context, AppSettings.applicationName.value),
    _item(Icons.settings_outlined, l10n.settings, () async {
      context.go('/rooms/settings');
    }),
    _item(
      Icons.notifications_outlined,
      l10n.notificationSettings,
      () async => context.go('/rooms/settings/notifications'),
    ),
    _item(
      Icons.palette_outlined,
      l10n.appearance,
      () async => context.go('/rooms/settings/style'),
    ),
    _item(
      Icons.archive_outlined,
      l10n.archive,
      () async => context.go('/rooms/archive'),
    ),
  ]);
}

/// Opens the menu of a network's (a space's) rail tile at [position]: Mark
/// all as read and Mute all chats for the chats in it, its settings, and
/// Hide from rail. Marking is shown disabled while none of them is unread.
Future<void> showSpaceRailMenu(
  BuildContext context,
  ChatListController controller,
  Room space,
  Offset position,
) {
  final l10n = L10n.of(context);
  final client = Matrix.of(context).client;
  final chats = [
    for (final id in roomIdsInSpace(client, space))
      if (client.getRoomById(id) case final room?
          when room.membership == Membership.join)
        room,
  ];
  final unmute = chats.isNotEmpty && chats.every(_isMuted);
  return _showRailMenu(context, position, [
    _heading(context, space.getLocalizedDisplayname(MatrixLocals(l10n))),
    _item(
      Icons.mark_chat_read_outlined,
      l10n.markAllAsRead,
      () => controller.markAllAsRead(space),
      enabled: controller.unreadChats(space).isNotEmpty,
    ),
    _item(
      unmute ? Icons.notifications_outlined : Icons.notifications_off_outlined,
      unmute ? l10n.unmuteAllChats : l10n.muteAllChats,
      () => _setMuted(context, chats, !unmute),
      enabled: chats.isNotEmpty,
    ),
    const PopupMenuDivider(),
    // A bridge has no settings page of its own in the app, so this is the
    // space's details, which hold its settings.
    _item(
      Icons.settings_outlined,
      l10n.networkSettings,
      () async => context.push('/rooms/${space.id}/details'),
    ),
    _item(
      Icons.visibility_off_outlined,
      l10n.hideFromRail,
      () => controller.hideFromRail(space),
    ),
  ]);
}

bool _isMuted(Room room) => room.cachedPushRuleState != PushRuleState.notify;

/// Mutes [chats] (mentions still notify) when [mute], else turns their
/// notifications back on, as the selection bar's Mute does.
Future<void> _setMuted(BuildContext context, List<Room> chats, bool mute) =>
    showFutureLoadingDialog(
      context: context,
      future: () => Future.wait([
        for (final room in chats)
          if (_isMuted(room) != mute)
            room.setPushRuleState(
              mute ? PushRuleState.mentionsOnly : PushRuleState.notify,
            ),
      ]),
    );

Future<void> _showRailMenu(
  BuildContext context,
  Offset position,
  List<PopupMenuEntry<_Action>> items,
) async {
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  final choice = await showMenu<_Action>(
    context: context,
    position: RelativeRect.fromRect(
      overlay.globalToLocal(position) & Size.zero,
      Offset.zero & overlay.size,
    ),
    // Material menu metrics, as in the chat filter menu: 48 high rows, 12
    // side padding, between 112 and 280 wide.
    constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
    items: items,
  );
  await choice?.call();
}

/// A section label: small, in the variant color, not selectable.
PopupMenuEntry<_Action> _heading(BuildContext context, String text) {
  final theme = Theme.of(context);
  return PopupMenuItem(
    enabled: false,
    height: 32,
    padding: const EdgeInsets.symmetric(horizontal: 12),
    child: Text(
      text,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: theme.textTheme.labelSmall?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    ),
  );
}

PopupMenuEntry<_Action> _item(
  IconData icon,
  String label,
  _Action action, {
  bool enabled = true,
}) => PopupMenuItem(
  value: action,
  enabled: enabled,
  height: 48,
  padding: const EdgeInsets.symmetric(horizontal: 12),
  child: Row(
    children: [
      Icon(icon),
      const SizedBox(width: 12),
      Flexible(
        child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
      ),
    ],
  ),
);
