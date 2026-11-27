// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_swipe.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/settings_switch_list_tile.dart';
import 'package:material_ui/material_ui.dart';

/// The subtitle of the Swipe actions row in chat settings: what each
/// direction does, or that swiping is off.
String swipeActionsSummary(L10n l10n) => AppSettings.chatListSwipe.value
    ? l10n.swipeActionsSummary(
        ChatSwipeAction.right.label(l10n),
        ChatSwipeAction.left.label(l10n),
      )
    : l10n.swipeOff;

/// Settings > Chat > Swipe actions: whether chat list rows swipe at all, a
/// preview of each direction, and the action each one runs.
class SettingsSwipeActions extends StatefulWidget {
  const SettingsSwipeActions({super.key});

  @override
  State<SettingsSwipeActions> createState() => _SettingsSwipeActionsState();
}

class _SettingsSwipeActionsState extends State<SettingsSwipeActions> {
  /// Opens the picker for the direction stored in [setting] and stores the
  /// action chosen.
  Future<void> _pick(AppSettings<String> setting, String title) async {
    final theme = Theme.of(context);
    final current = ChatSwipeAction.named(setting.value);
    final picked = await showModalBottomSheet<ChatSwipeAction>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      constraints: const BoxConstraints(maxWidth: 512),
      builder: (context) => SafeArea(
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(title: Text(title, style: theme.textTheme.labelSmall)),
              const Divider(height: 1),
              for (final action in ChatSwipeAction.values)
                _option(context, action, selected: action == current),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (picked == null || picked == current) return;
    await setting.setItem(picked.name);
    swipeActionsChanged.value++;
    if (mounted) setState(() {});
  }

  Widget _option(
    BuildContext context,
    ChatSwipeAction action, {
    required bool selected,
  }) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context);
    final destructive = action == ChatSwipeAction.leave;
    return ListTile(
      leading: Icon(action.icon, color: destructive ? scheme.error : null),
      title: Text(
        action.label(l10n),
        style: destructive ? TextStyle(color: scheme.error) : null,
      ),
      subtitle: destructive ? Text(l10n.swipeLeaveDescription) : null,
      trailing: selected ? Icon(Icons.check, color: scheme.primary) : null,
      selected: selected,
      onTap: () => Navigator.of(context).pop(action),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final l10n = L10n.of(context);
    final enabled = AppSettings.chatListSwipe.value;
    final right = ChatSwipeAction.right;
    final left = ChatSwipeAction.left;

    Widget directionTile(
      AppSettings<String> setting,
      ChatSwipeAction action,
      String title,
      IconData icon,
    ) => ListTile(
      enabled: enabled,
      leading: Icon(icon),
      title: Text(title),
      subtitle: Text(action.label(l10n)),
      trailing: Icon(
        action.icon,
        color: enabled ? scheme.primary : scheme.onSurface.withAlpha(97),
      ),
      onTap: () => _pick(setting, title),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.swipeActions),
        automaticallyImplyLeading: !FluffyThemes.isColumnMode(context),
        centerTitle: FluffyThemes.isColumnMode(context),
      ),
      body: ListTileTheme(
        iconColor: theme.textTheme.bodyLarge!.color,
        child: MaxWidthBody(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SettingsSwitchListTile.adaptive(
                title: l10n.swipeOnChats,
                subtitle: l10n.swipeOnChatsDescription,
                setting: AppSettings.chatListSwipe,
                onChanged: (_) => setState(() => swipeActionsChanged.value++),
              ),
              if (enabled)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(
                      AppConfig.borderRadius + 6,
                    ),
                    child: ColoredBox(
                      color: scheme.surfaceContainer,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 6),
                        child: Column(
                          children: [
                            _SwipePreview(
                              action: right,
                              title: l10n.swipeRight,
                              toRight: true,
                            ),
                            _SwipePreview(
                              action: left,
                              title: l10n.swipeLeft,
                              toRight: false,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ListTile(
                title: Text(
                  l10n.swipeActionsHeading,
                  style: TextStyle(
                    color: scheme.secondary,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              directionTile(
                AppSettings.chatListSwipeRight,
                right,
                l10n.swipeRight,
                Icons.swipe_right_outlined,
              ),
              directionTile(
                AppSettings.chatListSwipeLeft,
                left,
                l10n.swipeLeft,
                Icons.swipe_left_outlined,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Text(
                  l10n.swipeActionsFootnote,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: scheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// A sample row held past the threshold one way, showing what that
/// direction's swipe looks like with its current action.
class _SwipePreview extends StatelessWidget {
  final ChatSwipeAction action;
  final String title;
  final bool toRight;

  const _SwipePreview({
    required this.action,
    required this.title,
    required this.toRight,
  });

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final l10n = L10n.of(context);
    final row = Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: scheme.secondaryContainer,
          foregroundColor: scheme.onSecondaryContainer,
          child: const Icon(Icons.person_outlined),
        ),
        title: Text(title),
        subtitle: Text(action.label(l10n)),
      ),
    );
    if (action == ChatSwipeAction.none) return row;
    return ExcludeSemantics(
      child: LayoutBuilder(
        builder: (context, constraints) {
          final offset = ChatListSwipe.thresholdFor(constraints.maxWidth) + 30;
          return SwipeRowFrame(
            offset: toRight ? offset : -offset,
            // Labelled as on a chat it would act on, not as its setting.
            action: SwipeAction(
              action,
              switch (action) {
                ChatSwipeAction.markRead => l10n.markAsRead,
                ChatSwipeAction.pin => l10n.pin,
                ChatSwipeAction.mute => l10n.muteChat,
                _ => action.label(l10n),
              },
              action.icon,
              () {},
            ),
            armed: true,
            background: scheme.surfaceContainer,
            child: row,
          );
        },
      ),
    );
  }
}
