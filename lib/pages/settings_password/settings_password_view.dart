// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/settings_password/settings_password.dart';
import 'package:fluffychat/widgets/settings_list.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

class SettingsPasswordView extends StatelessWidget {
  final SettingsPasswordController controller;
  const SettingsPasswordView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SettingsPage(
      title: l10n.changePassword,
      nested: true,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: SettingsMetrics.pageMargin,
            vertical: 8,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TextField(
                controller: controller.oldPasswordController,
                obscureText: true,
                autocorrect: false,
                autofocus: true,
                readOnly: controller.loading,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_outlined),
                  hintText: '********',
                  labelText: l10n.pleaseEnterYourCurrentPassword,
                  errorText: controller.oldPasswordError,
                ),
              ),
              const SizedBox(height: 32),
              TextField(
                controller: controller.newPassword1Controller,
                obscureText: true,
                autocorrect: false,
                readOnly: controller.loading,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.lock_reset_outlined),
                  hintText: '********',
                  labelText: l10n.newPassword,
                  errorText: controller.newPassword1Error,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: controller.newPassword2Controller,
                obscureText: true,
                autocorrect: false,
                readOnly: controller.loading,
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.repeat_outlined),
                  hintText: '********',
                  labelText: l10n.repeatPassword,
                  errorText: controller.newPassword2Error,
                ),
              ),
              const SizedBox(height: 24),
              FilledButton(
                onPressed: controller.loading
                    ? null
                    : controller.changePassword,
                child: controller.loading
                    ? const LinearProgressIndicator()
                    : Text(l10n.changePassword),
              ),
              const SizedBox(height: 8),
              TextButton(
                child: Text(l10n.passwordRecoverySettings),
                onPressed: () => context.go('/rooms/settings/security/3pid'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
