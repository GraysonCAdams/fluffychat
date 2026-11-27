// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_3pid/settings_3pid.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class Settings3PidView extends StatelessWidget {
  final Settings3PidController controller;

  const Settings3PidView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);

    controller.request ??= Matrix.of(context).client.getAccount3PIDs();
    return SettingsPage(
      title: l10n.passwordRecovery,
      nested: true,
      actions: [
        IconButton(
          icon: const Icon(Icons.add_outlined),
          onPressed: controller.add3PidAction,
          tooltip: l10n.addEmail,
        ),
      ],
      children: [
        FutureBuilder<List<ThirdPartyIdentifier>?>(
          future: controller.request,
          builder: (context, snapshot) {
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(SettingsMetrics.textInset),
                child: Text(
                  snapshot.error.toString(),
                  textAlign: TextAlign.center,
                ),
              );
            }
            if (!snapshot.hasData) {
              return const Padding(
                padding: EdgeInsets.all(SettingsMetrics.textInset),
                child: Center(
                  child: CircularProgressIndicator.adaptive(strokeWidth: 2),
                ),
              );
            }
            final identifier = snapshot.data!;
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                SettingsGroup(
                  children: [
                    SettingsTile(
                      leading: Icon(
                        identifier.isEmpty
                            ? Icons.warning_outlined
                            : Icons.info_outlined,
                        color: identifier.isEmpty ? Colors.orange : null,
                      ),
                      title: Text(
                        identifier.isEmpty
                            ? l10n.noPasswordRecoveryDescription
                            : l10n.withTheseAddressesRecoveryDescription,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                SettingsGroup(
                  children: [
                    for (final address in identifier)
                      SettingsTile(
                        leading: Icon(address.iconData),
                        title: Text(address.address),
                        trailing: IconButton(
                          tooltip: l10n.delete,
                          icon: const Icon(Icons.delete_forever_outlined),
                          color: theme.colorScheme.error,
                          onPressed: () => controller.delete3Pid(address),
                        ),
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

extension on ThirdPartyIdentifier {
  IconData get iconData {
    switch (medium) {
      case ThirdPartyIdentifierMedium.email:
        return Icons.mail_outline_rounded;
      case ThirdPartyIdentifierMedium.msisdn:
        return Icons.phone_android_outlined;
    }
  }
}
