// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/device_settings/device_settings.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'user_device_list_item.dart';

class DevicesSettingsView extends StatelessWidget {
  final DevicesSettingsController controller;

  const DevicesSettingsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);

    Widget device(Device device) => UserDeviceListItem(
      device,
      rename: controller.renameDeviceAction,
      remove: (d) => controller.removeDevicesAction([d]),
      verify: controller.verifyDeviceAction,
      block: controller.blockDeviceAction,
      unblock: controller.unblockDeviceAction,
    );

    return SettingsPage(
      title: l10n.devices,
      children: [
        FutureBuilder<bool>(
          future: controller.loadUserDevices(context),
          builder: (BuildContext context, snapshot) {
            final theme = Theme.of(context);
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(SettingsMetrics.textInset),
                child: Column(
                  mainAxisSize: .min,
                  children: <Widget>[
                    const Icon(Icons.error_outlined),
                    Text(snapshot.error.toString()),
                  ],
                ),
              );
            }
            if (!snapshot.hasData || controller.devices == null) {
              return const Padding(
                padding: EdgeInsets.all(SettingsMetrics.textInset),
                child: Center(
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              );
            }
            final thisDevice = controller.thisDevice;
            final otherDevices = controller.notThisDevice;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (controller.chatBackupEnabled == false)
                  SettingsGroup(
                    children: [
                      SettingsTile(
                        leading: const Icon(Icons.info_outlined),
                        title: Text(
                          l10n.noticeChatBackupDeviceVerification,
                          style: theme.textTheme.bodyMedium,
                        ),
                      ),
                    ],
                  ),
                if (thisDevice != null) ...[
                  SettingsSectionHeader(l10n.thisDevice),
                  SettingsGroup(children: [device(thisDevice)]),
                ],
                if (otherDevices.isEmpty)
                  SettingsCaption(l10n.noOtherDevicesFound)
                else ...[
                  SettingsSectionHeader(l10n.settingsOtherDevices),
                  SettingsGroup(
                    children: [for (final other in otherDevices) device(other)],
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      SettingsMetrics.pageMargin,
                      16,
                      SettingsMetrics.pageMargin,
                      0,
                    ),
                    child: FilledButton.tonalIcon(
                      label: Text(l10n.removeAllOtherDevices),
                      style: FilledButton.styleFrom(
                        iconColor: theme.colorScheme.onErrorContainer,
                        foregroundColor: theme.colorScheme.onErrorContainer,
                        backgroundColor: theme.colorScheme.errorContainer,
                      ),
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () =>
                          controller.removeDevicesAction(otherDevices),
                    ),
                  ),
                ],
              ],
            );
          },
        ),
      ],
    );
  }
}
