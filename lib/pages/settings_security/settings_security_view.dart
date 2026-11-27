// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/beautify_string_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/app_lock.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:fluffychat/widgets/settings_switch_list_tile.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'settings_security.dart';

class SettingsSecurityView extends StatelessWidget {
  final SettingsSecurityController controller;

  const SettingsSecurityView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    final publicMasterKey =
        client.userDeviceKeys[client.userID]?.masterKey?.publicKey;

    return SettingsPage(
      title: l10n.security,
      children: [
        FutureBuilder(
          future: controller.capabilitiesFuture,
          builder: (context, snapshot) {
            final capabilities = snapshot.data;
            final error = snapshot.error;
            if (error == null && capabilities == null) {
              return const Center(
                child: Padding(
                  padding: EdgeInsets.all(16.0),
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsSectionHeader(l10n.privacy),
                SettingsGroup(
                  children: [
                    SettingsSwitchListTile.adaptive(
                      title: l10n.sendTypingNotifications,
                      subtitle: l10n.sendTypingNotificationsDescription,
                      setting: AppSettings.sendTypingNotifications,
                    ),
                    SettingsSwitchListTile.adaptive(
                      title: l10n.sendReadReceipts,
                      subtitle: l10n.sendReadReceiptsDescription,
                      setting: AppSettings.sendPublicReadReceipts,
                    ),
                    SettingsSwitchListTile.adaptive(
                      title: l10n.shareCrashReports,
                      subtitle: l10n.shareCrashReportsDescription,
                      setting: AppSettings.autoSendErrorReports,
                      defaultValue: false,
                    ),
                    SettingsTile(
                      leading: const Icon(Icons.block_outlined),
                      trailing: SettingsTile.chevron,
                      title: Text(l10n.blockedUsers),
                      subtitle: Text(
                        l10n.thereAreCountUsersBlocked(
                          client.ignoredUsers.length,
                        ),
                      ),
                      onTap: () =>
                          context.go('/rooms/settings/security/ignorelist'),
                    ),
                  ],
                ),
                if (PlatformInfos.supportsAppLock) ...[
                  SettingsSectionHeader(
                    l10n.appLock,
                    description: l10n.appLockDescription,
                  ),
                  SettingsGroup(
                    children: [
                      SettingsSwitchTile(
                        value: AppLock.of(context).isActive,
                        title: Text(l10n.useAppLock),
                        onChanged: (active) => active
                            ? controller.setAppLockAction()
                            : controller.disableAppLockAction(),
                      ),
                      if (AppLock.of(context).isActive) ...[
                        FutureBuilder(
                          future: controller.canCheckBiometricsFuture,
                          builder: (context, snapshot) {
                            if (snapshot.data != true) {
                              return const SizedBox.shrink();
                            }
                            return SettingsSwitchTile(
                              value: AppLock.of(context).useBiometrics,
                              onChanged: (_) => controller.toggleBiometrics(),
                              title: Text(l10n.unlockWithBiometrics),
                            );
                          },
                        ),
                        SettingsTile(
                          trailing: const Icon(Icons.lock_reset_outlined),
                          title: Text(l10n.resetPin),
                          onTap: controller.setAppLockAction,
                        ),
                      ],
                    ],
                  ),
                ],
                SettingsSectionHeader(l10n.encryption),
                SettingsGroup(
                  children: [
                    SettingsGroupItem(
                      padding: const EdgeInsets.fromLTRB(
                        SettingsMetrics.rowInset,
                        12,
                        SettingsMetrics.rowInset,
                        16,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            l10n.shareKeysWith,
                            style: theme.textTheme.bodyLarge,
                          ),
                          Text(
                            l10n.shareKeysWithDescription,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Material(
                            borderRadius: BorderRadius.circular(
                              AppConfig.borderRadius / 2,
                            ),
                            color: theme.colorScheme.surfaceContainerHighest,
                            child: DropdownButton<ShareKeysWith>(
                              isExpanded: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 12.0,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.borderRadius / 2,
                              ),
                              underline: const SizedBox.shrink(),
                              value: client.shareKeysWith,
                              items: ShareKeysWith.values
                                  .map(
                                    (share) => DropdownMenuItem(
                                      value: share,
                                      child: Text(share.localized(l10n)),
                                    ),
                                  )
                                  .toList(),
                              onChanged: controller.changeShareKeysWith,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (publicMasterKey != null)
                      SettingsTile(
                        title: Text(l10n.yourPublicKey),
                        leading: const Icon(Icons.verified_user_outlined),
                        subtitle: SelectableText(
                          publicMasterKey.beautified,
                          style: const TextStyle(fontFamily: 'RobotoMono'),
                        ),
                      ),
                    SettingsTile(
                      title: Text(l10n.deviceIdentityKey),
                      leading: const Icon(Icons.mobile_friendly_outlined),
                      subtitle: SelectableText(
                        client.fingerprintKey.beautified,
                        style: const TextStyle(fontFamily: 'RobotoMono'),
                      ),
                    ),
                  ],
                ),
                if (capabilities?.mChangePassword?.enabled != false ||
                    error != null) ...[
                  SettingsSectionHeader(l10n.account),
                  SettingsGroup(
                    children: [
                      SettingsTile(
                        leading: const Icon(Icons.password_outlined),
                        trailing: SettingsTile.chevron,
                        title: Text(l10n.changePassword),
                        onTap: () =>
                            context.go('/rooms/settings/security/password'),
                      ),
                    ],
                  ),
                ],
                SettingsSectionHeader(l10n.settingsDangerZone),
                SettingsGroup(
                  children: [
                    SettingsTile(
                      color: Colors.orange,
                      leading: const Icon(Icons.delete_sweep_outlined),
                      title: Text(l10n.dehydrate),
                      onTap: controller.dehydrateAction,
                    ),
                    SettingsTile(
                      color: theme.colorScheme.error,
                      leading: const Icon(Icons.delete_outlined),
                      title: Text(l10n.deleteAccount),
                      onTap: controller.deleteAccountAction,
                    ),
                  ],
                ),
              ],
            );
          },
        ),
      ],
    );
  }
}

extension on ShareKeysWith {
  String localized(L10n l10n) {
    switch (this) {
      case ShareKeysWith.all:
        return l10n.allDevices;
      case ShareKeysWith.crossVerifiedIfEnabled:
        return l10n.crossVerifiedDevicesIfEnabled;
      case ShareKeysWith.crossVerified:
        return l10n.crossVerifiedDevices;
      case ShareKeysWith.verifiedOnly:
      // ignore: deprecated_member_use
      case ShareKeysWith.directlyVerifiedOnly:
        return l10n.verifiedDevicesOnly;
    }
  }
}
