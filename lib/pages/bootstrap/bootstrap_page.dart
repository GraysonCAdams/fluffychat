// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/bootstrap/view_model/bootstrap_view_model.dart';
import 'package:fluffychat/pages/bootstrap/widgets/bootstrap_steps.dart';
import 'package:fluffychat/pages/key_verification/key_verification_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/onboarding/onboarding_step.dart';
import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:fluffychat/widgets/view_model_builder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';

/// Encryption setup after sign-in: a new account creates and saves its
/// recovery key; a new device of an existing account is confirmed by
/// another device or the recovery key. [reset] starts over with a new
/// identity (from Settings, or "Can't confirm?").
class BootstrapPage extends StatelessWidget {
  final bool reset;
  const BootstrapPage({required this.reset, super.key});

  @override
  Widget build(BuildContext context) {
    return ViewModelBuilder(
      create: () =>
          BootstrapViewModel(client: Matrix.of(context).client, reset: reset),
      builder: (context, viewModel, _) => BootstrapStepView(viewModel),
    );
  }
}

class BootstrapStepView extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const BootstrapStepView(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final step = viewModel.step;

    if (step == BootstrapStep.leave) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => viewModel.goToRoomsPageAfterSuccess(context),
      );
    }
    final keyVerification = viewModel.value.keyVerification;
    if (step == BootstrapStep.waitingForDevice &&
        keyVerification?.state == KeyVerificationState.askSas &&
        viewModel.takeSasPrompt()) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => KeyVerificationDialog(request: keyVerification!).show(context),
      );
    }

    return switch (step) {
      BootstrapStep.loading || BootstrapStep.leave => OnboardingStep(
        centered: true,
        hero: Padding(
          padding: const EdgeInsets.only(top: 96),
          child: SeamStitchLoader(
            size: 120,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        headline: l10n.loadingPleaseWait,
      ),
      BootstrapStep.protect => ProtectStep(viewModel),
      BootstrapStep.passphrase => PassphraseStep(viewModel),
      BootstrapStep.saveKey => SaveKeyStep(viewModel),
      BootstrapStep.checkKey => CheckKeyStep(viewModel),
      BootstrapStep.setupDone => FinishedStep(
        viewModel,
        icon: Icons.check_rounded,
        headline: l10n.allSetTitle,
        body: l10n.allSetBody,
      ),
      BootstrapStep.confirmIdentity => ConfirmIdentityStep(viewModel),
      BootstrapStep.waitingForDevice => WaitingForDeviceStep(viewModel),
      BootstrapStep.enterKey => EnterKeyStep(viewModel),
      BootstrapStep.confirmed => FinishedStep(
        viewModel,
        icon: Icons.verified_user_rounded,
        headline: l10n.deviceConfirmedTitle,
        body: l10n.deviceConfirmedBody,
      ),
    };
  }
}
