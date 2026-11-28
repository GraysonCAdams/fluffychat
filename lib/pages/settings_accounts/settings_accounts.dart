// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Settings > Accounts: every account signed in on this device, whether
/// this device is confirmed for it, and Add account. Tapping an account
/// switches to it.
class SettingsAccounts extends StatelessWidget {
  const SettingsAccounts({super.key});

  /// Whether this device is confirmed (cross-signed) for [client]'s
  /// account.
  static bool deviceConfirmed(Client client) =>
      client
          .userDeviceKeys[client.userID]
          ?.deviceKeys[client.deviceID]
          ?.verified ??
      false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final matrix = Matrix.of(context);
    final clients = matrix.widget.clients
        .where((client) => client.isLogged())
        .toList();
    final scheme = Theme.of(context).colorScheme;
    return SettingsPage(
      title: l10n.accounts,
      children: [
        SettingsGroup(
          children: [
            for (final client in clients)
              FutureBuilder(
                future: client.fetchOwnProfile(),
                builder: (context, snapshot) {
                  final profile = snapshot.data;
                  final confirmed = deviceConfirmed(client);
                  final active = identical(client, matrix.client);
                  return SettingsTile(
                    leading: Avatar(
                      mxContent: profile?.avatarUrl,
                      name: profile?.displayName ?? client.userID,
                      size: 40,
                    ),
                    title: Text(
                      profile?.displayName ?? client.userID!.localpart!,
                    ),
                    subtitle: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(client.userID!),
                        const SizedBox(height: 2),
                        Row(
                          spacing: 4,
                          children: [
                            Icon(
                              confirmed
                                  ? Icons.verified_user_outlined
                                  : Icons.error_outline,
                              size: 16,
                              color: confirmed ? scheme.primary : scheme.error,
                            ),
                            Flexible(
                              child: Text(
                                confirmed
                                    ? l10n.thisDeviceIsConfirmed
                                    : l10n.confirmItsYouTitle,
                                style: TextStyle(
                                  color: confirmed
                                      ? scheme.primary
                                      : scheme.error,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                    trailing: active
                        ? Icon(Icons.check, color: scheme.primary)
                        : SettingsTile.chevron,
                    onTap: () {
                      matrix.setActiveClient(client);
                      if (!confirmed) {
                        context.go('/backup');
                        return;
                      }
                      context.go('/rooms');
                    },
                  );
                },
              ),
          ],
        ),
        SettingsGroup(
          children: [
            SettingsTile(
              leading: const Icon(Icons.person_add_outlined),
              title: Text(l10n.addAccount),
              subtitle: Text(l10n.addAccountAnyServer),
              onTap: () => context.go('/rooms/settings/addaccount'),
            ),
          ],
        ),
      ],
    );
  }
}
