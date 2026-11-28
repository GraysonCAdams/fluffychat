// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/terms_acceptance.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:url_launcher/url_launcher_string.dart';

void _openInBrowser(String url) =>
    launchUrlString(url, mode: LaunchMode.externalApplication);

/// The Terms of use and Privacy policy as two text buttons, each opening
/// the page in the browser.
class TermsLinks extends StatelessWidget {
  final WrapAlignment alignment;

  const TermsLinks({this.alignment = WrapAlignment.center, super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Wrap(
      alignment: alignment,
      children: [
        TextButton(
          onPressed: () => _openInBrowser(AppSettings.termsOfUseUrl.value),
          child: Text(l10n.termsOfUse),
        ),
        TextButton(
          onPressed: () =>
              _openInBrowser(AppSettings.privacyPolicyPageUrl.value),
          child: Text(l10n.privacyPolicy),
        ),
      ],
    );
  }
}

/// The "I agree to the Terms of use" checkbox above the sign-in buttons.
///
/// [builder] gets a `gate` function to wrap each button's callback in: it
/// returns null (a disabled button) until the box is ticked, and afterwards
/// a callback that records the agreement on the device before running the
/// button's own action. The account copy follows after sign-in
/// (TermsAcceptance.settle).
class SignInTermsGate extends StatefulWidget {
  final Widget Function(
    BuildContext context,
    VoidCallback? Function(VoidCallback? action) gate,
  )
  builder;

  const SignInTermsGate({required this.builder, super.key});

  @override
  State<SignInTermsGate> createState() => _SignInTermsGateState();
}

class _SignInTermsGateState extends State<SignInTermsGate> {
  bool _agreed = false;

  VoidCallback? _gate(VoidCallback? action) {
    if (!_agreed || action == null) return null;
    return () async {
      await TermsAcceptance.recordOnDevice();
      action();
    };
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        Material(
          color: colorScheme.surfaceContainerLow,
          borderRadius: BorderRadius.circular(16),
          clipBehavior: Clip.hardEdge,
          child: Column(
            mainAxisSize: .min,
            crossAxisAlignment: .stretch,
            children: [
              CheckboxListTile(
                key: const Key('terms_agree_checkbox'),
                value: _agreed,
                onChanged: (value) => setState(() => _agreed = value ?? false),
                controlAffinity: ListTileControlAffinity.leading,
                contentPadding: const EdgeInsetsDirectional.only(start: 4),
                title: Text(l10n.agreeToTermsOfUse),
              ),
              const Padding(
                padding: EdgeInsetsDirectional.only(start: 48, bottom: 4),
                child: TermsLinks(alignment: WrapAlignment.start),
              ),
            ],
          ),
        ),
        widget.builder(context, _gate),
      ],
    );
  }
}

/// Asks an account that has not agreed to the current terms to do so, once
/// its account data is known. Shown over whatever screen is open.
Future<void> promptForTermsIfNeeded(
  Client client,
  BuildContext Function() context,
) async {
  final terms = TermsAcceptance.of(client);
  if (await terms.settle()) return;
  await WidgetsBinding.instance.endOfFrame;
  final dialogContext = context();
  if (!dialogContext.mounted || terms.value) return;
  await showTermsUpdateDialog(dialogContext, terms);
}

/// The accounts whose terms dialog is up, so it is never shown twice.
final _dialogsOpen = <TermsAcceptance>{};

/// The dialog for an account that has not agreed to the current terms: it
/// cannot be dismissed, only answered with Agree or Sign out, and closes by
/// itself if the agreement arrives from another device meanwhile.
Future<void> showTermsUpdateDialog(
  BuildContext context,
  TermsAcceptance terms,
) async {
  if (terms.value || !_dialogsOpen.add(terms)) return;
  try {
    await showDialog<void>(
      context: context,
      useRootNavigator: true,
      barrierDismissible: false,
      builder: (context) => TermsUpdateDialog(terms: terms),
    );
  } finally {
    _dialogsOpen.remove(terms);
  }
}

class TermsUpdateDialog extends StatefulWidget {
  final TermsAcceptance terms;

  const TermsUpdateDialog({required this.terms, super.key});

  @override
  State<TermsUpdateDialog> createState() => _TermsUpdateDialogState();
}

class _TermsUpdateDialogState extends State<TermsUpdateDialog> {
  @override
  void initState() {
    super.initState();
    widget.terms.addListener(_closeOnceAccepted);
  }

  @override
  void dispose() {
    widget.terms.removeListener(_closeOnceAccepted);
    super.dispose();
  }

  void _closeOnceAccepted() {
    if (widget.terms.value && mounted) Navigator.of(context).pop();
  }

  Future<void> _signOut() async {
    final l10n = L10n.of(context);
    final client = widget.terms.client;
    final identity = await client.getCryptoIdentityState();
    if (!mounted) return;
    final consent = await showOkCancelAlertDialog(
      context: context,
      title: l10n.areYouSureYouWantToLogout,
      message: identity.initialized && identity.connected
          ? null
          : l10n.noBackupWarning,
      okLabel: l10n.signOut,
      cancelLabel: l10n.cancel,
      isDestructive: true,
    );
    if (consent != OkCancelResult.ok || !mounted) return;
    final navigator = Navigator.of(context);
    final result = await showFutureLoadingDialog(
      context: context,
      future: client.logout,
    );
    if (result.error == null && mounted) navigator.pop();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return PopScope(
      canPop: false,
      child: AlertDialog(
        icon: const Icon(Icons.policy_outlined),
        title: Text(l10n.termsUpdateTitle),
        content: Column(
          mainAxisSize: .min,
          crossAxisAlignment: .start,
          children: [
            Text(
              l10n.termsUpdateBody,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            const TermsLinks(alignment: WrapAlignment.start),
          ],
        ),
        actions: [
          TextButton(
            key: const Key('terms_sign_out_button'),
            onPressed: _signOut,
            child: Text(l10n.signOut),
          ),
          TextButton(
            key: const Key('terms_agree_button'),
            onPressed: widget.terms.accept,
            child: Text(l10n.agree),
          ),
        ],
      ),
    );
  }
}

/// Shows [child] (the composer) once [client] has agreed to the current
/// terms, and until then a disabled bar in its place with a button that
/// opens the terms dialog.
class TermsComposerGate extends StatelessWidget {
  final Client client;
  final Widget child;

  const TermsComposerGate({
    required this.client,
    required this.child,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final terms = TermsAcceptance.of(client);
    return ValueListenableBuilder<bool>(
      valueListenable: terms,
      builder: (context, accepted, _) {
        if (accepted) return child;
        final theme = Theme.of(context);
        final l10n = L10n.of(context);
        return Material(
          key: const Key('terms_composer_gate'),
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(28),
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 56),
            child: Padding(
              padding: const EdgeInsetsDirectional.only(start: 16, end: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.policy_outlined,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Text(
                      l10n.termsComposerNotice,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                  TextButton(
                    onPressed: () => showTermsUpdateDialog(context, terms),
                    child: Text(l10n.review),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}
