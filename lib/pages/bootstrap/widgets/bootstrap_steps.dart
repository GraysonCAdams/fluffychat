// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/bootstrap/view_model/bootstrap_view_model.dart';
import 'package:fluffychat/pages/bootstrap/widgets/recovery_key_grid.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/device_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/onboarding/onboarding_step.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';

/// "Not now": asks whether to skip recovery, and leaves for the chat list
/// if so.
Future<void> confirmSkipRecovery(
  BuildContext context,
  BootstrapViewModel viewModel,
) async {
  final l10n = L10n.of(context);
  final skip = await showModalBottomSheet<bool>(
    context: context,
    showDragHandle: true,
    builder: (context) {
      final colorScheme = Theme.of(context).colorScheme;
      return SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: OnboardingButtonTheme(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  l10n.skipRecoveryTitle,
                  style: Theme.of(context).textTheme.titleLarge,
                ),
                const SizedBox(height: 8),
                Text(
                  l10n.skipRecoveryBody,
                  style: TextStyle(
                    color: colorScheme.onSurfaceVariant,
                    fontSize: 15,
                    height: 1.4,
                  ),
                ),
                const SizedBox(height: 20),
                FilledButton(
                  onPressed: () => Navigator.of(context).pop(false),
                  child: Text(l10n.setItUpNow),
                ),
                const SizedBox(height: 8),
                TextButton(
                  style: TextButton.styleFrom(
                    foregroundColor: colorScheme.error,
                  ),
                  onPressed: () => Navigator.of(context).pop(true),
                  child: Text(l10n.skipForNow),
                ),
              ],
            ),
          ),
        ),
      );
    },
  );
  if (skip == true && context.mounted) viewModel.leave(context);
}

Widget _notNow(BuildContext context, BootstrapViewModel viewModel) =>
    TextButton(
      onPressed: () => confirmSkipRecovery(context, viewModel),
      child: Text(L10n.of(context).notNow),
    );

/// A new account (or a reset): what recovery is for, then create the key.
class ProtectStep extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const ProtectStep(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final busy = viewModel.value.isLoading;
    return OnboardingStep(
      leading: viewModel.reset
          ? CloseButton(onPressed: () => viewModel.leave(context))
          : null,
      actions: [if (!busy && !viewModel.reset) _notNow(context, viewModel)],
      hero: const OnboardingHeroIcon(Icons.shield_outlined),
      headline: l10n.protectMessagesTitle,
      body: l10n.protectMessagesBody,
      content: [
        OnboardingBullet(Icons.history, l10n.protectBenefitHistory),
        OnboardingBullet(
          Icons.verified_user_outlined,
          l10n.protectBenefitSignIns,
        ),
        OnboardingBullet(Icons.cloud_done_outlined, l10n.protectBenefitServer),
      ],
      primary: busy
          ? const OnboardingBusyButton()
          : FilledButton(
              onPressed: () => viewModel.setOrSkipPassphrase(null, context),
              child: Text(l10n.createRecoveryKey),
            ),
      secondary: [
        TextButton(
          onPressed: busy ? null : () => viewModel.choosePassphrase(true),
          child: Text(l10n.usePassphraseInstead),
        ),
      ],
    );
  }
}

/// The optional passphrase, with the rules it has to meet.
class PassphraseStep extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const PassphraseStep(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = viewModel.value;
    final canCreate =
        state.newPassphraseEqualsRepeatPassphrase &&
        state.newPassphraseNumbers &&
        state.newPassphraseSpecialCharacters &&
        state.newPassphraseUpperAndLowerCase &&
        state.newPassphraseLongEnough;
    Widget rule(bool met, String label) {
      final colorScheme = Theme.of(context).colorScheme;
      return Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Row(
          spacing: 8,
          children: [
            Icon(
              met ? Icons.check_circle : Icons.circle_outlined,
              size: 18,
              color: met ? colorScheme.primary : colorScheme.onSurfaceVariant,
            ),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return OnboardingStep(
      leading: BackButton(onPressed: () => viewModel.choosePassphrase(false)),
      headline: l10n.choosePassphraseTitle,
      body: l10n.choosePassphraseBody,
      content: [
        TextField(
          obscureText: state.obscureText,
          readOnly: state.isLoading,
          controller: viewModel.newPassphraseController,
          decoration: InputDecoration(
            labelText: l10n.newPassphrase,
            suffixIcon: IconButton(
              tooltip: l10n.newPassphrase,
              icon: Icon(
                state.obscureText
                    ? Icons.visibility_outlined
                    : Icons.visibility_off_outlined,
              ),
              onPressed: viewModel.toggleObscureText,
            ),
          ),
        ),
        const SizedBox(height: 16),
        TextField(
          obscureText: state.obscureText,
          readOnly: state.isLoading,
          controller: viewModel.repeatPassphraseController,
          decoration: InputDecoration(labelText: l10n.repeatPassphrase),
        ),
        const SizedBox(height: 16),
        rule(state.newPassphraseLongEnough, l10n.passphraseLengthRequirement),
        rule(
          state.newPassphraseUpperAndLowerCase,
          l10n.passphraseUpperAndLowerCaseRequirement,
        ),
        rule(state.newPassphraseNumbers, l10n.passphraseNumberRequirement),
        rule(
          state.newPassphraseSpecialCharacters,
          l10n.passphraseSpecialCharactersRequirement,
        ),
        rule(state.newPassphraseEqualsRepeatPassphrase, l10n.passphrasesMatch),
      ],
      primary: state.isLoading
          ? const OnboardingBusyButton()
          : FilledButton(
              onPressed: canCreate
                  ? () => viewModel.setOrSkipPassphrase(
                      viewModel.newPassphraseController.text,
                      context,
                    )
                  : null,
              child: Text(l10n.continueText),
            ),
    );
  }
}

/// The new recovery key, with ways to keep it.
class SaveKeyStep extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const SaveKeyStep(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = viewModel.value;
    final key = state.recoveryKey!;
    final colorScheme = Theme.of(context).colorScheme;
    final compact = FilledButton.styleFrom(
      padding: const EdgeInsets.symmetric(horizontal: 8),
      minimumSize: const Size(0, 48),
    );
    return OnboardingStep(
      headline: l10n.saveRecoveryKeyTitle,
      body: l10n.saveRecoveryKeyBody,
      content: [
        RecoveryKeyGrid(groups: RecoveryKeyGrid.groupsOf(key)),
        const SizedBox(height: 16),
        Row(
          spacing: 8,
          children: [
            Expanded(
              child: FilledButton.tonalIcon(
                style: compact,
                onPressed: () async {
                  await Clipboard.setData(ClipboardData(text: key));
                  viewModel.markKeyCopied();
                },
                icon: Icon(state.recoveryKeyCopied ? Icons.check : Icons.copy),
                label: Text(state.recoveryKeyCopied ? l10n.copied : l10n.copy),
              ),
            ),
            Expanded(
              child: FilledButton.tonalIcon(
                style: compact,
                onPressed: () =>
                    viewModel.toggleRecoveryKeyDownloaded(true, context),
                icon: Icon(
                  state.recoveryKeyDownloaded ? Icons.check : Icons.download,
                ),
                label: Text(l10n.save),
              ),
            ),
            if (PlatformInfos.isMobile)
              Expanded(
                child: Builder(
                  builder: (context) => FilledButton.tonalIcon(
                    style: compact,
                    onPressed: () async {
                      await FluffyShare.share(key, context);
                      viewModel.markKeyCopied();
                    },
                    icon: const Icon(Icons.share_outlined),
                    label: Text(l10n.share),
                  ),
                ),
              ),
          ],
        ),
        if (viewModel.supportsSecureStorage) ...[
          const SizedBox(height: 12),
          SwitchListTile(
            contentPadding: const EdgeInsets.symmetric(horizontal: 4),
            value: state.recoveryKeyStoredInSecureStorage,
            onChanged: viewModel.toggleRecoveryKeyStoredInSecureStorage,
            title: Text(l10n.keepInKeystore),
            subtitle: Text(
              l10n.keepInKeystoreSubtitle,
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
        ],
      ],
      primary: FilledButton(
        onPressed: state.recoveryKeyKept ? viewModel.startKeyCheck : null,
        child: Text(l10n.iveSavedIt),
      ),
    );
  }
}

/// Asks for one group of the key back, so a partial copy shows up now.
class CheckKeyStep extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const CheckKeyStep(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = viewModel.value;
    final groups = RecoveryKeyGrid.groupsOf(state.recoveryKey!);
    final asked = state.askedGroup!;
    final colorScheme = Theme.of(context).colorScheme;
    return OnboardingStep(
      leading: BackButton(onPressed: viewModel.backToKey),
      headline: l10n.checkYouHaveItTitle,
      body: l10n.checkYouHaveItBody,
      content: [
        RecoveryKeyGrid(
          groups: groups,
          hidden: true,
          asked: asked,
          askedChild: TextField(
            controller: viewModel.checkGroupController,
            autofocus: true,
            autocorrect: false,
            textAlign: TextAlign.center,
            maxLength: groups[asked].length,
            onSubmitted: (_) => viewModel.checkGroup(),
            style: RecoveryKeyGrid.monospace(),
            decoration: const InputDecoration(
              counterText: '',
              contentPadding: EdgeInsets.zero,
            ),
          ),
        ),
        const SizedBox(height: 12),
        Text(
          state.groupMismatch
              ? l10n.groupDoesNotMatch
              : l10n.groupNOfM('${asked + 1}', '${groups.length}'),
          style: TextStyle(
            color: state.groupMismatch
                ? colorScheme.error
                : colorScheme.onSurfaceVariant,
          ),
        ),
      ],
      primary: FilledButton(
        onPressed: viewModel.checkGroup,
        child: Text(l10n.confirm),
      ),
      secondary: [
        TextButton(
          onPressed: viewModel.backToKey,
          child: Text(l10n.showMyKeyAgain),
        ),
      ],
    );
  }
}

/// A status step that ends the flow: set up, or this device confirmed.
class FinishedStep extends StatelessWidget {
  final BootstrapViewModel viewModel;
  final String headline;
  final String body;
  final IconData icon;

  const FinishedStep(
    this.viewModel, {
    required this.headline,
    required this.body,
    required this.icon,
    super.key,
  });

  @override
  Widget build(BuildContext context) => OnboardingStep(
    centered: true,
    hero: Padding(
      padding: const EdgeInsets.only(top: 64),
      child: OnboardingHeroIcon(icon, tone: OnboardingTone.success, size: 96),
    ),
    headline: headline,
    body: body,
    primary: FilledButton(
      onPressed: () => viewModel.goToRoomsPageAfterSuccess(context),
      child: Text(L10n.of(context).startChatting),
    ),
  );
}

/// An existing account on a new device: confirm it from another device or
/// with the recovery key.
class ConfirmIdentityStep extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const ConfirmIdentityStep(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final devices = viewModel.value.connectedDevices ?? const [];
    return OnboardingStep(
      actions: [_notNow(context, viewModel)],
      hero: const OnboardingHeroIcon(Icons.devices_outlined),
      headline: l10n.confirmItsYouTitle,
      body: l10n.confirmItsYouBody,
      content: [
        if (devices.isNotEmpty) ...[
          OnboardingOption(
            icon: Icons.phonelink_lock_outlined,
            title: l10n.useAnotherDevice,
            subtitle: devices.map((device) => device.displayname).join('  ·  '),
            emphasized: true,
            onTap: viewModel.useAnotherDevice,
          ),
          const SizedBox(height: 12),
        ],
        OnboardingOption(
          icon: Icons.key_outlined,
          title: l10n.useRecoveryKey,
          subtitle: l10n.useRecoveryKeySubtitle,
          emphasized: devices.isEmpty,
          onTap: () => viewModel.enterRecoveryKey(true),
        ),
      ],
      secondary: [
        TextButton(
          style: TextButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: () async {
            final consent = await showOkCancelAlertDialog(
              context: context,
              title: l10n.resetIdentityTitle,
              message: l10n.resetIdentityBody,
              isDestructive: true,
              okLabel: l10n.reset,
            );
            if (consent != OkCancelResult.ok) return;
            viewModel.startResetAccount();
          },
          child: Text(l10n.cantConfirmReset),
        ),
      ],
    );
  }
}

/// Unlocking with the recovery key (or the passphrase).
class EnterKeyStep extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const EnterKeyStep(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = viewModel.value;
    final error = state.unlockWithError;
    return OnboardingStep(
      leading: BackButton(onPressed: () => viewModel.enterRecoveryKey(false)),
      headline: l10n.enterRecoveryKeyTitle,
      body: l10n.enterRecoveryKeyBody,
      content: [
        if (state.savedRecoveryKey != null &&
            viewModel.enterPassphraseOrRecovController.text.isEmpty) ...[
          OnboardingNotice(
            icon: Icons.key,
            tone: OnboardingTone.brand,
            text: l10n.savedKeyFound,
            actionLabel: l10n.useIt,
            onAction: () => viewModel.useSavedKey(context),
          ),
          const SizedBox(height: 16),
        ],
        TextField(
          controller: viewModel.enterPassphraseOrRecovController,
          readOnly: state.isLoading,
          autocorrect: false,
          minLines: 3,
          maxLines: 3,
          onSubmitted: (_) => viewModel.unlock(context),
          style: RecoveryKeyGrid.monospace(fontSize: 17, height: 1.5),
          decoration: InputDecoration(
            labelText: l10n.recoveryKeyOrPassphrase,
            alignLabelWithHint: true,
            errorText: error == null
                ? null
                : error is InvalidPassphraseException
                ? l10n.recoveryKeyMismatch
                : error.toLocalizedString(context),
            errorMaxLines: 3,
          ),
        ),
        const SizedBox(height: 12),
        Wrap(
          spacing: 8,
          children: [
            ActionChip(
              avatar: const Icon(Icons.content_paste, size: 18),
              label: Text(l10n.paste),
              onPressed: state.isLoading ? null : viewModel.pasteKey,
            ),
            ActionChip(
              avatar: const Icon(Icons.file_open_outlined, size: 18),
              label: Text(l10n.openFile),
              onPressed: state.isLoading
                  ? null
                  : () => viewModel.openRecoveryKeyFile(context),
            ),
          ],
        ),
      ],
      primary: state.isLoading
          ? const OnboardingBusyButton()
          : FilledButton(
              onPressed: state.passphraseOrRecoveryKeyEntered
                  ? () => viewModel.unlock(context)
                  : null,
              child: Text(l10n.unlock),
            ),
    );
  }
}

/// The request is out: waiting for one of the other devices to accept.
class WaitingForDeviceStep extends StatelessWidget {
  final BootstrapViewModel viewModel;
  const WaitingForDeviceStep(this.viewModel, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final state = viewModel.value;
    final colorScheme = Theme.of(context).colorScheme;
    final devices = (state.connectedDevices ?? const [])
        .map((device) => device.displayname)
        .join(', ');
    final failed =
        state.noSecretsreceived ||
        state.keyVerification?.state == KeyVerificationState.error;
    return OnboardingStep(
      leading: BackButton(onPressed: () => viewModel.enterRecoveryKey(false)),
      headline: l10n.openSeamOnOtherDevice,
      body: l10n.requestSentTo(devices),
      content: [
        Row(
          children: [
            if (failed)
              Icon(Icons.error_outline, color: colorScheme.error)
            else
              const SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator(strokeWidth: 2.5),
              ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                state.waitingForSecrets
                    ? l10n.waitingForKeys
                    : failed
                    ? l10n.noKeysTransmitted
                    : l10n.waitingForReply,
                style: TextStyle(color: colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ],
      primary: failed
          ? FilledButton(
              onPressed: viewModel.useAnotherDevice,
              child: Text(l10n.tryAgain),
            )
          : null,
      secondary: [
        TextButton(
          onPressed: () => viewModel.enterRecoveryKey(true),
          child: Text(l10n.useRecoveryKeyInstead),
        ),
      ],
    );
  }
}
