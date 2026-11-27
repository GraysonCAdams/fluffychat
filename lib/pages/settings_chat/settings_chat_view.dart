// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_swipe.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/windows_shell.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:fluffychat/widgets/settings_switch_list_tile.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'hidden_rail_spaces_tile.dart';
import 'message_search_index_tile.dart';
import 'settings_chat.dart';
import 'settings_swipe_actions.dart';

/// Settings > Chat, in groups: how messages show, writing them, gestures,
/// the chat list, the Windows app's own options, and the rarely changed
/// rest under Advanced.
class SettingsChatView extends StatelessWidget {
  final SettingsChatController controller;
  const SettingsChatView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    return SettingsPage(
      title: l10n.chat,
      children: [
        SettingsSectionHeader(l10n.messages),
        SettingsGroup(
          children: [
            SettingsSwitchListTile.adaptive(
              title: l10n.formattedMessages,
              subtitle: l10n.formattedMessagesDescription,
              setting: AppSettings.renderHtml,
            ),
            SettingsSwitchListTile.adaptive(
              title: l10n.showThumbnailsInTimeline,
              setting: AppSettings.showThumbnailsInTimeline,
            ),
            if (PlatformInfos.isMobile)
              SettingsSwitchListTile.adaptive(
                title: l10n.autoplayImages,
                setting: AppSettings.autoplayImages,
              ),
            SettingsSwitchListTile.adaptive(
              title: l10n.hideRedactedMessages,
              subtitle: l10n.hideRedactedMessagesBody,
              setting: AppSettings.hideRedactedEvents,
            ),
            SettingsSwitchListTile.adaptive(
              title: l10n.hideInvalidOrUnknownMessageFormats,
              setting: AppSettings.hideUnknownEvents,
            ),
          ],
        ),
        SettingsSectionHeader(l10n.settingsWriting),
        SettingsGroup(
          children: [
            SettingsSwitchListTile.adaptive(
              title: l10n.sendOnEnter,
              setting: AppSettings.sendOnEnter,
            ),
            SettingsSwitchListTile.adaptive(
              title: l10n.recordVoiceMessages,
              subtitle: l10n.recordVoiceMessagesDescription,
              setting: AppSettings.voiceMessages,
            ),
          ],
        ),
        SettingsSectionHeader(l10n.settingsGestures),
        SettingsGroup(
          children: [
            SettingsSwitchListTile.adaptive(
              title: l10n.swipeRightToLeftToReply,
              setting: AppSettings.swipeRightToLeftToReply,
            ),
            SettingsSwitchListTile.adaptive(
              title: l10n.doubleTapToReact,
              subtitle: l10n.doubleTapToReactDescription,
              setting: AppSettings.doubleTapToReact,
              onChanged: (_) => controller.updateState(),
            ),
            if (AppSettings.doubleTapToReact.value)
              SettingsTile(
                title: Text(l10n.doubleTapReaction),
                trailing: Text(
                  AppSettings.doubleTapReaction.value,
                  style: const TextStyle(fontSize: 24),
                ),
                onTap: () async {
                  final emoji = await showAdaptiveBottomSheet<String>(
                    context: context,
                    builder: (context) => Scaffold(
                      appBar: AppBar(
                        title: Text(L10n.of(context).doubleTapReaction),
                        leading: CloseButton(
                          onPressed: () => Navigator.of(context).pop(null),
                        ),
                      ),
                      body: SizedBox(
                        height: double.infinity,
                        child: EmojiPicker(
                          onEmojiSelected: (_, emoji) =>
                              Navigator.of(context).pop(emoji.emoji),
                          config: Config(
                            locale: Localizations.localeOf(context),
                            emojiViewConfig: const EmojiViewConfig(
                              backgroundColor: Colors.transparent,
                            ),
                            bottomActionBarConfig: const BottomActionBarConfig(
                              enabled: false,
                            ),
                            categoryViewConfig: CategoryViewConfig(
                              initCategory: Category.SMILEYS,
                              backspaceColor: theme.colorScheme.primary,
                              iconColor: theme.colorScheme.primary.withAlpha(
                                128,
                              ),
                              iconColorSelected: theme.colorScheme.primary,
                              indicatorColor: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.surface,
                            ),
                            skinToneConfig: SkinToneConfig(
                              dialogBackgroundColor: Color.lerp(
                                theme.colorScheme.surface,
                                theme.colorScheme.primaryContainer,
                                0.75,
                              )!,
                              indicatorColor: theme.colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  if (emoji != null) {
                    await AppSettings.doubleTapReaction.setItem(emoji);
                    controller.updateState();
                  }
                },
              ),
            ValueListenableBuilder(
              valueListenable: swipeActionsChanged,
              builder: (context, _, _) => SettingsTile(
                title: Text(l10n.swipeActions),
                subtitle: Text(swipeActionsSummary(l10n)),
                onTap: () => context.go('/rooms/settings/chat/swipe_actions'),
                trailing: SettingsTile.chevron,
              ),
            ),
          ],
        ),
        SettingsSectionHeader(l10n.settingsChatList),
        SettingsGroup(
          children: [
            SettingsSwitchListTile.adaptive(
              title: l10n.suggestContactsFromChats,
              subtitle: l10n.suggestContactsFromChatsDescription,
              setting: AppSettings.suggestContactsFromChats,
            ),
            SettingsSwitchListTile.adaptive(
              title: l10n.openSpacesAsChatList,
              subtitle: l10n.openSpacesAsChatListDescription,
              setting: AppSettings.openSpacesAsChatList,
            ),
            SettingsSwitchListTile.adaptive(
              title: l10n.hideRoomsInSpaces,
              setting: AppSettings.hideRoomsInSpaces,
            ),
            const HiddenRailSpacesTile(),
            SettingsTile(
              title: Text(l10n.mergedContacts),
              subtitle: Text(l10n.mergedContactsDescription),
              onTap: () => context.go('/rooms/settings/chat/merged_contacts'),
              trailing: SettingsTile.chevron,
            ),
          ],
        ),
        if (PlatformInfos.isWindows) ...[
          SettingsSectionHeader(l10n.settingsWindows),
          SettingsGroup(
            children: [
              SettingsSwitchListTile.adaptive(
                title: l10n.closeToTray,
                setting: AppSettings.closeToTray,
              ),
              SettingsSwitchListTile.adaptive(
                title: l10n.launchAtStartup,
                setting: AppSettings.launchAtStartup,
                onChanged: WindowsDesktop.setLaunchAtStartup,
              ),
            ],
          ),
        ],
        SettingsSectionHeader(l10n.advanced),
        SettingsGroup(
          children: [
            SettingsTile(
              title: Text(l10n.matrixFeatures),
              subtitle: Text(l10n.matrixFeaturesDescription),
              onTap: () => context.go('/rooms/settings/chat/matrix_features'),
              trailing: SettingsTile.chevron,
            ),
            if (MatrixFeatures.forClient(
              Matrix.of(context).client,
            ).isRelevant(MatrixFeature.customEmotes))
              SettingsTile(
                title: Text(l10n.customEmojisAndStickers),
                subtitle: Text(l10n.customEmojisAndStickersBody),
                onTap: () => context.go('/rooms/settings/chat/emotes'),
                trailing: SettingsTile.chevron,
              ),
            const MessageSearchIndexTile(),
          ],
        ),
      ],
    );
  }
}
