// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sign_in_flows/oidc_login.dart';
import 'package:fluffychat/utils/sign_in_flows/sign_in_method.dart';
import 'package:fluffychat/utils/sign_in_flows/sso_login.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/onboarding/onboarding_step.dart';
import 'package:fluffychat/widgets/onboarding/server_chip.dart';
import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// What the server step found, handed to [BrowserSignInPage].
class BrowserSignInArgs {
  final Client client;
  final SignInMethod method;
  final List<LoginFlow> loginFlows;
  final bool signUp;

  /// The server as typed or picked, remembered for next time on success.
  final String homeserverInput;

  const BrowserSignInArgs({
    required this.client,
    required this.method,
    required this.loginFlows,
    required this.signUp,
    required this.homeserverInput,
  });

  String get serverLabel => client.homeserver?.host ?? homeserverInput;
}

/// The step before the browser opens for OIDC or SSO sign-in: says where
/// the person is going and why, then waits while they sign in there.
///
/// A server with several SSO identity providers gets a button for each in
/// place of the single Continue.
class BrowserSignInPage extends StatefulWidget {
  final BrowserSignInArgs args;

  /// Runs the browser sign-in; defaults to the OIDC or SSO flow. Returns
  /// once the client is signed in, and throws if that fails.
  final Future<void> Function(BuildContext context, SsoIdentityProvider?)?
  signIn;

  const BrowserSignInPage({required this.args, this.signIn, super.key});

  @override
  State<BrowserSignInPage> createState() => BrowserSignInPageState();
}

class BrowserSignInPageState extends State<BrowserSignInPage> {
  bool _waiting = false;
  Object? _error;
  SsoIdentityProvider? _provider;

  /// Bumped on every start and cancel, so an attempt that was given up on
  /// changes nothing when its browser finally returns.
  int _attempt = 0;

  Future<void> _defaultSignIn(
    BuildContext context,
    SsoIdentityProvider? provider,
  ) {
    final args = widget.args;
    return args.method == SignInMethod.oidc
        ? oidcLoginFlow(args.client, context, args.signUp)
        : ssoLoginFlow(args.client, args.signUp, provider: provider);
  }

  Future<void> _start([SsoIdentityProvider? provider]) async {
    final attempt = ++_attempt;
    setState(() {
      _waiting = true;
      _error = null;
      _provider = provider;
    });
    try {
      await (widget.signIn ?? _defaultSignIn)(context, provider);
      if (attempt != _attempt || !mounted) return;
      await AppSettings.defaultHomeserver.setItem(widget.args.homeserverInput);
      if (!mounted || kIsWeb) return;
      context.go(Matrix.of(context).afterSignInLocation);
    } catch (e, s) {
      if (attempt != _attempt || !mounted) return;
      // Closing the browser without finishing is not an error.
      final cancelled = e is PlatformException && e.code == 'CANCELED';
      if (!cancelled) Logs().w('Browser sign-in failed', e, s);
      setState(() {
        _waiting = false;
        _error = cancelled ? null : e;
      });
    }
  }

  void _cancel() {
    _attempt++;
    setState(() => _waiting = false);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final args = widget.args;
    final server = args.serverLabel;
    final providers = args.method == SignInMethod.sso
        ? SsoIdentityProvider.of(args.loginFlows)
        : const <SsoIdentityProvider>[];

    if (_waiting) {
      return OnboardingStep(
        leading: CloseButton(onPressed: _cancel),
        centered: true,
        hero: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: SeamStitchLoader(
            size: 120,
            color: Theme.of(context).colorScheme.primary,
          ),
        ),
        headline: l10n.finishSigningInBrowser,
        body: l10n.waitingForServerBody(server),
        secondary: [
          OutlinedButton(
            onPressed: () => _start(_provider),
            child: Text(l10n.openSignInPageAgain),
          ),
          TextButton(onPressed: _cancel, child: Text(l10n.cancel)),
        ],
      );
    }

    final error = _error;
    final content = <Widget>[
      ServerChip(server: server),
      const SizedBox(height: 20),
      if (error != null) ...[
        OnboardingNotice(
          icon: Icons.error_outline,
          tone: OnboardingTone.error,
          text: error.toLocalizedString(context),
        ),
        const SizedBox(height: 16),
      ],
    ];

    if (providers.length > 1) {
      return OnboardingStep(
        leading: BackButton(onPressed: Navigator.of(context).pop),
        headline: l10n.chooseHowToSignIn,
        body: l10n.serverOffersTheseOptions(server),
        content: [
          ...content,
          OnboardingButtonTheme(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              spacing: 12,
              children: [
                for (final provider in providers)
                  OutlinedButton(
                    onPressed: () => _start(provider),
                    child: Text(l10n.continueWithProvider(provider.name)),
                  ),
              ],
            ),
          ),
        ],
      );
    }

    return OnboardingStep(
      leading: BackButton(onPressed: Navigator.of(context).pop),
      hero: const OnboardingHeroIcon(Icons.open_in_browser),
      headline: l10n.signInOnServerPageTitle,
      body: l10n.signInOnServerPageBody(server),
      content: [
        ...content,
        OnboardingBullet(Icons.key_outlined, l10n.passkeysWorkThere),
        OnboardingBullet(Icons.lock_outline, l10n.seamNeverSeesPassword),
        // Web and Linux sign in through a separate browser window, so the
        // page says what signing in there shares.
        if (kIsWeb || PlatformInfos.isLinux)
          Text(
            l10n.appWantsToUseForLoginDescription,
            style: TextStyle(
              fontSize: 13,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
      ],
      primary: FilledButton.icon(
        onPressed: () => _start(providers.singleOrNull),
        icon: const Icon(Icons.open_in_new),
        label: Text(l10n.continueToSignInPage),
      ),
    );
  }
}
