// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:url_launcher/url_launcher_string.dart';

import '../../widgets/mxc_image_viewer.dart';
import 'settings.dart';

/// The settings home: the profile, then the pages and actions in groups
/// (General, Account, About) and Logout on its own. On a phone the title
/// is a large app bar that collapses as the list scrolls; in column mode
/// the page is the narrow left pane and marks the page open beside it.
class SettingsView extends StatelessWidget {
  final SettingsController controller;

  const SettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final columnMode = FluffyThemes.isColumnMode(context);
    final activeRoute = GoRouter.of(
      context,
    ).routeInformationProvider.value.uri.path;

    /// A row that opens the settings page at [route].
    Widget page(IconData icon, String title, String summary, String route) =>
        SettingsTile(
          leading: Icon(icon),
          title: Text(title),
          subtitle: Text(summary),
          selected: columnMode && activeRoute.startsWith(route),
          onTap: () => context.go(route),
        );

    final title = Text(l10n.settings);
    final back = Center(
      child: BackButton(onPressed: () => context.go('/rooms')),
    );

    return Scaffold(
      body: CustomScrollView(
        key: const Key('SettingsListViewContent'),
        slivers: [
          if (columnMode)
            SliverAppBar(
              pinned: true,
              title: title,
              leading: back,
              // As tall as the app bar of the page beside it.
              toolbarHeight:
                  Theme.of(context).appBarTheme.toolbarHeight ?? kToolbarHeight,
            )
          else
            SliverAppBar.large(title: title, leading: back),
          SliverSafeArea(
            top: false,
            sliver: SliverPadding(
              padding: const EdgeInsets.only(top: 8, bottom: 24),
              sliver: SliverToBoxAdapter(
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(
                      maxWidth: SettingsMetrics.maxContentWidth,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        _ProfileCard(controller),
                        SettingsSectionHeader(l10n.settingsGeneral),
                        SettingsGroup(
                          children: [
                            page(
                              Icons.format_paint_outlined,
                              l10n.changeTheme,
                              l10n.settingsStyleSummary,
                              '/rooms/settings/style',
                            ),
                            page(
                              Icons.notifications_outlined,
                              l10n.notifications,
                              l10n.settingsNotificationsSummary,
                              '/rooms/settings/notifications',
                            ),
                            page(
                              Icons.forum_outlined,
                              l10n.chat,
                              l10n.settingsChatSummary,
                              '/rooms/settings/chat',
                            ),
                          ],
                        ),
                        SettingsSectionHeader(l10n.account),
                        SettingsGroup(
                          children: [
                            SettingsSwitchTile(
                              leading: const Icon(Icons.backup_outlined),
                              title: Text(l10n.chatBackup),
                              subtitle: Text(l10n.settingsChatBackupSummary),
                              value: controller.cryptoIdentityConnected == true,
                              onChanged: controller.firstRunBootstrapAction,
                            ),
                            page(
                              Icons.devices_outlined,
                              l10n.devices,
                              l10n.settingsDevicesSummary,
                              '/rooms/settings/devices',
                            ),
                            page(
                              Icons.shield_outlined,
                              l10n.security,
                              l10n.settingsSecuritySummary,
                              '/rooms/settings/security',
                            ),
                            FutureBuilder(
                              future: controller.authMetadataFuture,
                              builder: (context, snapshot) {
                                final accountManageUrl =
                                    snapshot.data?.accountManagementUri;
                                if (accountManageUrl == null) {
                                  return const SizedBox.shrink();
                                }
                                return SettingsTile(
                                  leading: const Icon(
                                    Icons.account_circle_outlined,
                                  ),
                                  title: Text(l10n.manageAccount),
                                  subtitle: Text(
                                    l10n.settingsManageAccountSummary,
                                  ),
                                  trailing: const Icon(
                                    Icons.open_in_new_outlined,
                                  ),
                                  onTap: () => launchUrl(
                                    accountManageUrl,
                                    mode: LaunchMode.inAppBrowserView,
                                  ),
                                );
                              },
                            ),
                            SettingsTile(
                              leading: const Icon(Icons.person_add_outlined),
                              title: Text(l10n.addAccount),
                              subtitle: Text(l10n.settingsAddAccountSummary),
                              onTap: () =>
                                  context.go('/rooms/settings/addaccount'),
                            ),
                          ],
                        ),
                        SettingsSectionHeader(l10n.about),
                        SettingsGroup(
                          children: [
                            page(
                              Icons.dns_outlined,
                              l10n.aboutHomeserver(
                                Matrix.of(context).client.userID?.domain ??
                                    'homeserver',
                              ),
                              l10n.settingsHomeserverSummary,
                              '/rooms/settings/homeserver',
                            ),
                            if (AppSettings.privacyPolicy.value.isNotEmpty)
                              SettingsTile(
                                leading: const Icon(Icons.privacy_tip_outlined),
                                title: Text(l10n.privacy),
                                trailing: const Icon(
                                  Icons.open_in_new_outlined,
                                ),
                                onTap: () => launchUrlString(
                                  AppSettings.privacyPolicy.value,
                                ),
                              ),
                            SettingsTile(
                              leading: const Icon(Icons.info_outline_rounded),
                              title: Text(l10n.about),
                              subtitle: Text(l10n.settingsAboutSummary),
                              onTap: () => PlatformInfos.showDialog(context),
                            ),
                          ],
                        ),
                        const SizedBox(height: 24),
                        SettingsGroup(
                          children: [
                            SettingsTile(
                              leading: const Icon(Icons.logout_outlined),
                              title: Text(l10n.logout),
                              onTap: controller.logoutAction,
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The account at the top of the settings home: the avatar with its change
/// button, the display name (tap to rename) and the user ID (tap to share).
class _ProfileCard extends StatelessWidget {
  final SettingsController controller;

  const _ProfileCard(this.controller);

  static const double _avatarSize = 72;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return FutureBuilder<Profile>(
      future: controller.profileFuture,
      builder: (context, snapshot) {
        final profile = snapshot.data;
        final avatar = profile?.avatarUrl;
        final mxid = Matrix.of(context).client.userID ?? l10n.user;
        final displayname = profile?.displayName ?? mxid.localpart ?? mxid;
        final avatarActions = [
          if (PlatformInfos.isMobile) AvatarAction.camera,
          AvatarAction.file,
          if (avatar != null) AvatarAction.remove,
        ];
        final avatarButtonStyle = IconButton.styleFrom(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          minimumSize: const Size.square(36),
          padding: EdgeInsets.zero,
          iconSize: 18,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          // A ring in the card's colour lifts the button off the avatar.
          side: BorderSide(color: SettingsMetrics.rowColor(theme), width: 2),
        );
        const cameraIcon = Icon(Icons.camera_alt_outlined);
        return Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SettingsMetrics.pageMargin,
          ),
          child: Material(
            color: SettingsMetrics.rowColor(theme),
            borderRadius: BorderRadius.circular(SettingsMetrics.groupRadius),
            child: Padding(
              padding: const EdgeInsets.all(SettingsMetrics.rowInset),
              child: Row(
                children: [
                  SizedBox.square(
                    dimension: _avatarSize + 8,
                    child: Stack(
                      children: [
                        Avatar(
                          mxContent: avatar,
                          name: displayname,
                          size: _avatarSize,
                          animated: true,
                          onTap: avatar != null
                              ? () => showDialog(
                                  context: context,
                                  builder: (_) => MxcImageViewer(avatar),
                                )
                              : null,
                        ),
                        if (profile != null)
                          Positioned(
                            bottom: 0,
                            right: 0,
                            child: avatarActions.length == 1
                                ? IconButton(
                                    style: avatarButtonStyle,
                                    tooltip: l10n.changeYourAvatar,
                                    onPressed: () => controller.setAvatarAction(
                                      avatarActions.single,
                                    ),
                                    icon: cameraIcon,
                                  )
                                : PopupMenuButton<AvatarAction>(
                                    style: avatarButtonStyle,
                                    tooltip: l10n.changeYourAvatar,
                                    onSelected: controller.setAvatarAction,
                                    icon: cameraIcon,
                                    itemBuilder: (context) => [
                                      for (final action in avatarActions)
                                        PopupMenuItem(
                                          value: action,
                                          child: Row(
                                            mainAxisSize: .min,
                                            spacing: 12,
                                            children: [
                                              Icon(switch (action) {
                                                AvatarAction.camera =>
                                                  Icons.camera_alt_outlined,
                                                AvatarAction.file =>
                                                  Icons.photo_outlined,
                                                AvatarAction.remove =>
                                                  Icons.delete_outlined,
                                              }),
                                              Text(switch (action) {
                                                AvatarAction.camera =>
                                                  l10n.openCamera,
                                                AvatarAction.file =>
                                                  l10n.openGallery,
                                                AvatarAction.remove =>
                                                  l10n.removeYourAvatar,
                                              }),
                                            ],
                                          ),
                                        ),
                                    ],
                                  ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        _ProfileLine(
                          onTap: controller.setDisplaynameAction,
                          icon: Icons.edit_outlined,
                          child: Text(
                            displayname,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleLarge,
                          ),
                        ),
                        _ProfileLine(
                          onTap: () => FluffyShare.share(mxid, context),
                          // Shown short in messenger mode; shared in full.
                          child: Text(
                            MatrixFeatures.forClient(
                              Matrix.of(context).client,
                            ).userLabel(mxid),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

/// One tappable line of the profile card, with an optional trailing [icon]
/// that says what the tap does.
class _ProfileLine extends StatelessWidget {
  final VoidCallback onTap;
  final Widget child;
  final IconData? icon;

  const _ProfileLine({required this.onTap, required this.child, this.icon});

  @override
  Widget build(BuildContext context) {
    final icon = this.icon;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 8,
          children: [
            Flexible(child: child),
            if (icon != null)
              Icon(
                icon,
                size: 18,
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
          ],
        ),
      ),
    );
  }
}
