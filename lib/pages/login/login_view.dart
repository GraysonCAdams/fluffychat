// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/onboarding/onboarding_step.dart';
import 'package:fluffychat/widgets/onboarding/server_chip.dart';
import 'package:material_ui/material_ui.dart';

import 'login.dart';
import 'login_error.dart';

/// The password step: the server as a chip, username and password, and
/// errors in place (wrong password under the field, too many tries as a
/// notice with a countdown on the button, no answer as a notice with
/// Retry).
class LoginView extends StatelessWidget {
  final LoginController controller;

  const LoginView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final homeserver = controller.widget.client.homeserver;
    final server = homeserver == null
        ? null
        : homeserver.hasPort
        ? '${homeserver.host}:${homeserver.port}'
        : homeserver.host;
    final notice = controller.notice;
    final wait = controller.rateLimitRemaining;
    final typed = controller.usernameController.text;

    return AutofillGroup(
      child: OnboardingStep(
        leading: controller.loading
            ? null
            : BackButton(onPressed: Navigator.of(context).pop),
        headline: l10n.signIn,
        content: [
          if (server != null) ...[
            ServerChip(server: server),
            const SizedBox(height: 20),
          ],
          if (notice != null) ...[
            switch (notice.kind) {
              LoginErrorKind.unreachable => OnboardingNotice(
                icon: Icons.cloud_off_outlined,
                tone: OnboardingTone.error,
                text: l10n.cantReachServerNow(server ?? ''),
                actionLabel: l10n.tryAgain,
                onAction: controller.login,
              ),
              _ => OnboardingNotice(
                icon: Icons.timer_outlined,
                text: l10n.tooManyTries,
              ),
            },
            const SizedBox(height: 16),
          ],
          ListenableBuilder(
            listenable: controller.usernameController,
            builder: (context, _) {
              final text = controller.usernameController.text;
              // A bare username is completed with the server; a full
              // Matrix ID, email address or phone number stands as typed.
              final showServerSuffix =
                  server != null && !text.contains('@') && !text.contains(':');
              return TextField(
                readOnly: controller.loading,
                autocorrect: false,
                autofocus: typed.isEmpty,
                onChanged: controller.checkWellKnownWithCoolDown,
                controller: controller.usernameController,
                textInputAction: TextInputAction.next,
                autofillHints: controller.loading
                    ? null
                    : [AutofillHints.username],
                decoration: InputDecoration(
                  prefixIcon: const Icon(Icons.person_outline),
                  errorText: controller.usernameError,
                  errorMaxLines: 3,
                  labelText: l10n.usernameLabel,
                  suffixText: showServerSuffix ? ':$server' : null,
                ),
              );
            },
          ),
          const SizedBox(height: 16),
          TextField(
            readOnly: controller.loading,
            autocorrect: false,
            autofocus: typed.isNotEmpty,
            autofillHints: controller.loading ? null : [AutofillHints.password],
            controller: controller.passwordController,
            textInputAction: TextInputAction.go,
            obscureText: !controller.showPassword,
            onSubmitted: (_) => controller.login(),
            decoration: InputDecoration(
              prefixIcon: const Icon(Icons.lock_outline),
              errorText: controller.passwordError,
              errorMaxLines: 3,
              suffixIcon: IconButton(
                onPressed: controller.toggleShowPassword,
                tooltip: l10n.password,
                icon: Icon(
                  controller.showPassword
                      ? Icons.visibility_off_outlined
                      : Icons.visibility_outlined,
                ),
              ),
              labelText: l10n.password,
            ),
          ),
          if (server != null)
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: TextButton(
                onPressed: controller.loading
                    ? null
                    : controller.passwordForgotten,
                child: Text(l10n.forgotPasswordQuestion),
              ),
            ),
        ],
        primary: controller.loading
            ? const OnboardingBusyButton()
            : FilledButton(
                onPressed: wait == null ? controller.login : null,
                child: Text(
                  wait == null
                      ? l10n.signIn
                      : l10n.tryAgainIn(formatCountdown(wait)),
                ),
              ),
      ),
    );
  }
}
