// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:material_ui/material_ui.dart';

import '../../widgets/matrix.dart';
import 'settings_ignore_list.dart';

class SettingsIgnoreListView extends StatelessWidget {
  final SettingsIgnoreListController controller;

  const SettingsIgnoreListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final client = Matrix.of(context).client;
    return SettingsPage(
      title: l10n.blockedUsers,
      nested: true,
      children: [
        StreamBuilder(
          stream: controller.ignoreListUpdates,
          builder: (context, asyncSnapshot) {
            if (client.prevBatch == null) {
              return const Padding(
                padding: EdgeInsets.all(SettingsMetrics.textInset),
                child: Center(child: CircularProgressIndicator.adaptive()),
              );
            }
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: SettingsMetrics.pageMargin,
                    vertical: 8,
                  ),
                  child: TextField(
                    controller: controller.controller,
                    autocorrect: false,
                    textInputAction: TextInputAction.done,
                    onSubmitted: (_) => controller.ignoreUser(context),
                    decoration: InputDecoration(
                      errorText: controller.errorText,
                      hintText: '@bad_guy:domain.abc',
                      floatingLabelBehavior: FloatingLabelBehavior.always,
                      labelText: l10n.blockUsername,
                      suffixIcon: IconButton(
                        tooltip: l10n.block,
                        icon: const Icon(Icons.add),
                        onPressed: () => controller.ignoreUser(context),
                      ),
                    ),
                  ),
                ),
                SettingsCaption(
                  l10n.blockListDescription,
                  color: Colors.orange,
                ),
                const SizedBox(height: 8),
                SettingsGroup(
                  children: [
                    for (final userId in client.ignoredUsers)
                      SettingsTile(
                        title: Text(userId),
                        trailing: IconButton(
                          tooltip: l10n.delete,
                          icon: const Icon(Icons.delete_outlined),
                          onPressed: () => showFutureLoadingDialog(
                            context: context,
                            future: () => client.unignoreUser(userId),
                          ),
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
