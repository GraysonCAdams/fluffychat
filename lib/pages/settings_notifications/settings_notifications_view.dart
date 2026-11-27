// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_notifications/push_rule_extensions.dart';
import 'package:fluffychat/utils/background_push.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:fluffychat/widgets/settings_switch_list_tile.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:unifiedpush_ui/unifiedpush_ui.dart';

import '../../utils/localized_exception_extension.dart';
import '../../widgets/matrix.dart';
import 'settings_notifications.dart';

class SettingsNotificationsView extends StatelessWidget {
  final SettingsNotificationsController controller;

  const SettingsNotificationsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final pushRules = Matrix.of(context).client.globalPushRules;
    final pushCategories = [
      if (pushRules?.override?.isNotEmpty ?? false)
        (rules: pushRules?.override ?? [], kind: PushRuleKind.override),
      if (pushRules?.content?.isNotEmpty ?? false)
        (rules: pushRules?.content ?? [], kind: PushRuleKind.content),
      if (pushRules?.sender?.isNotEmpty ?? false)
        (rules: pushRules?.sender ?? [], kind: PushRuleKind.sender),
      if (pushRules?.underride?.isNotEmpty ?? false)
        (rules: pushRules?.underride ?? [], kind: PushRuleKind.underride),
    ];
    final pushService = Matrix.of(context).backgroundPush;
    final l10n = L10n.of(context);
    return StreamBuilder(
      stream: controller.pushRuleUpdates,
      builder: (BuildContext context, _) {
        final theme = Theme.of(context);
        final lastReceivedPush =
            lastReceivedPushNotification[Matrix.of(context).client.clientName];
        return SelectionArea(
          child: SettingsPage(
            title: l10n.notifications,
            children: [
              if ((kDebugMode && lastReceivedPush != null) || kIsWeb)
                SettingsGroup(
                  children: [
                    if (kDebugMode && lastReceivedPush != null)
                      SettingsTile(
                        title: const Text('Last received push notification'),
                        subtitle: Text(lastReceivedPush.toIso8601String()),
                      ),
                    if (kIsWeb)
                      SettingsSwitchListTile.adaptive(
                        title: l10n.playSoundOnNotification,
                        setting: AppSettings.webNotificationSound,
                      ),
                  ],
                ),
              if (pushRules != null)
                for (final category in pushCategories) ...[
                  SettingsSectionHeader(category.kind.localized(l10n)),
                  SettingsGroup(
                    children: [
                      for (final rule in category.rules)
                        SettingsTile(
                          title: Text(rule.getPushRuleName(l10n)),
                          subtitle: Text.rich(
                            TextSpan(
                              children: [
                                TextSpan(
                                  text: rule.getPushRuleDescription(
                                    L10n.of(context),
                                  ),
                                ),
                                const TextSpan(text: ' '),
                                WidgetSpan(
                                  child: InkWell(
                                    onTap: () => controller.editPushRule(
                                      rule,
                                      category.kind,
                                    ),
                                    child: Text(
                                      L10n.of(context).more,
                                      style: TextStyle(
                                        color: theme.colorScheme.primary,
                                        decoration: TextDecoration.underline,
                                        decorationColor:
                                            theme.colorScheme.primary,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          trailing: Switch.adaptive(
                            value: rule.enabled,
                            onChanged: controller.isLoading
                                ? null
                                : rule.ruleId != '.m.rule.master' &&
                                      Matrix.of(
                                        context,
                                      ).client.allPushNotificationsMuted
                                ? null
                                : (_) => controller.togglePushRule(
                                    category.kind,
                                    rule,
                                  ),
                          ),
                        ),
                    ],
                  ),
                ],
              const SizedBox(height: 16),
              SettingsGroup(
                children: [
                  if (pushService?.firebaseEnabled != true)
                    SettingsTile(
                      title: Text(l10n.buildDoesNotSupportFirebase),
                      leading: Icon(
                        Icons.close,
                        color: theme.colorScheme.error,
                      ),
                    ),
                  if (PlatformInfos.isAndroid)
                    FutureBuilder(
                      future: controller.unifiedPushDistributors,
                      builder: (context, snapshot) {
                        final distributors = snapshot.data;
                        if (distributors == null || distributors.isEmpty) {
                          if (pushService?.firebaseEnabled == true &&
                              pushService?.fcmToken == null) {
                            return SettingsTile(
                              title: Text(
                                L10n.of(
                                  context,
                                ).unableToRegisterDeviceForFirebase,
                              ),
                              leading: Icon(
                                Icons.close,
                                color: theme.colorScheme.error,
                              ),
                            );
                          }
                          return const SizedBox.shrink();
                        }
                        return SettingsTile(
                          title: Text(L10n.of(context).unifiedPushDistributors),
                          leading: const Icon(Icons.info_outlined),
                          subtitle: SelectableText(distributors.join(', ')),
                          trailing: distributors.length >= 2
                              ? IconButton(
                                  onPressed: () => UnifiedPushUi(
                                    context: context,
                                    instances: ['default'],
                                    unifiedPushFunctions: UPFunctions(),
                                    showNoDistribDialog: false,
                                    onNoDistribDialogDismissed:
                                        () {}, // TODO: Implement me
                                  ).registerAppWithDialog(),
                                  icon: const Icon(Icons.edit_outlined),
                                  style: IconButton.styleFrom(
                                    backgroundColor:
                                        theme.colorScheme.primaryContainer,
                                    foregroundColor:
                                        theme.colorScheme.onPrimaryContainer,
                                  ),
                                )
                              : null,
                        );
                      },
                    ),
                ],
              ),
              SettingsSectionHeader(l10n.devices),
              FutureBuilder<List<Pusher>?>(
                future: controller.pusherFuture ??= Matrix.of(
                  context,
                ).client.getPushers(),
                builder: (context, snapshot) {
                  if (snapshot.hasError) {
                    Center(
                      child: Text(snapshot.error!.toLocalizedString(context)),
                    );
                  }
                  if (snapshot.connectionState != ConnectionState.done) {
                    const Center(
                      child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                    );
                  }
                  final pushers = snapshot.data ?? [];
                  if (pushers.isEmpty) {
                    return SettingsCaption(l10n.noOtherDevicesFound);
                  }
                  return SettingsGroup(
                    children: [
                      for (final pusher in pushers)
                        SettingsTile(
                          title: Text(pusher.appId),
                          subtitle: Text(pusher.data.url.toString()),
                          onTap: () => controller.onPusherTap(pusher),
                        ),
                    ],
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }
}
