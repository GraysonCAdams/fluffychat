// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/intro/flows/restore_backup_flow.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'package:fluffychat/widgets/onboarding/onboarding_step.dart';
import 'package:fluffychat/widgets/seam_mark.dart';
import 'package:fluffychat/widgets/seam_startup.dart';
import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:fluffychat/widgets/terms_acceptance_views.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:url_launcher/url_launcher_string.dart';

/// The welcome page: a cobalt band with the Seam mark, a line on what Seam
/// does, the Terms of use checkbox, and Sign in and Create an account.
///
/// On a phone the first welcome page after launch takes over from the
/// start screen (see [SeamStartup.handOff]): it begins as a full screen of
/// cobalt with the mark where the loader left it, then the cobalt shrinks
/// to the band and the rest of the page rises in.
class IntroPage extends StatefulWidget {
  final bool isLoading, hasPresetHomeserver;
  final String? loggingInToHomeserver, welcomeText;
  final VoidCallback login;

  const IntroPage({
    required this.isLoading,
    required this.loggingInToHomeserver,
    super.key,
    required this.hasPresetHomeserver,
    required this.welcomeText,
    required this.login,
    this.addingAccount = false,
  });

  /// Shown from Settings to add an account next to one already signed in.
  final bool addingAccount;

  /// Whether this run of the app has already shown the morph.
  @visibleForTesting
  static bool morphed = false;

  static const Duration morphDuration = Duration(milliseconds: 900);

  @override
  State<IntroPage> createState() => _IntroPageState();
}

class _IntroPageState extends State<IntroPage>
    with SingleTickerProviderStateMixin {
  late final AnimationController _morph = AnimationController(
    vsync: this,
    duration: IntroPage.morphDuration,
    value: 1,
  );
  bool _decided = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_decided) return;
    _decided = true;
    final morph =
        !IntroPage.morphed &&
        !widget.isLoading &&
        !MediaQuery.disableAnimationsOf(context) &&
        !FluffyThemes.isColumnModeByWidth(MediaQuery.sizeOf(context).width);
    IntroPage.morphed = true;
    if (!morph) return;
    _morph.value = 0;
    SeamStartup.handOff(() {
      if (mounted) _morph.forward();
    });
  }

  @override
  void dispose() {
    _morph.dispose();
    super.dispose();
  }

  void _signUp() => context.go('${GoRouterState.of(context).uri.path}/sign_up');

  @override
  Widget build(BuildContext context) {
    final columnMode = FluffyThemes.isColumnModeByWidth(
      MediaQuery.sizeOf(context).width,
    );
    if (columnMode) {
      return LoginScaffold(
        body: _WelcomeBody(
          page: widget,
          progress: const AlwaysStoppedAnimation(1),
          bandHeight: 250,
          markSize: 96,
          onSignUp: _signUp,
        ),
      );
    }
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        body: _WelcomeBody(
          page: widget,
          progress: CurvedAnimation(
            parent: _morph,
            curve: Curves.easeInOutCubicEmphasized,
          ),
          bandHeight: 360,
          markSize: 112,
          onSignUp: _signUp,
        ),
      ),
    );
  }
}

class _WelcomeBody extends StatelessWidget {
  final IntroPage page;
  final Animation<double> progress;
  final double bandHeight, markSize;
  final VoidCallback onSignUp;

  const _WelcomeBody({
    required this.page,
    required this.progress,
    required this.bandHeight,
    required this.markSize,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final bandColor = theme.brightness == Brightness.dark
        ? const Color(0xFF12347F)
        : AppConfig.primaryColor;
    final loggingInToHomeserver = page.loggingInToHomeserver;
    final padding = MediaQuery.paddingOf(context);

    return LayoutBuilder(
      builder: (context, constraints) => AnimatedBuilder(
        animation: progress,
        builder: (context, _) {
          final t = progress.value;
          // While loading, the band stays full height, as at launch.
          final settled = page.isLoading ? 0.0 : t;
          final band =
              constraints.maxHeight +
              (bandHeight + padding.top - constraints.maxHeight) * settled;
          final mark =
              SeamStartup.loaderSize +
              (markSize - SeamStartup.loaderSize) * settled;
          // The words come in over the last part of the motion.
          final rest = ((settled - .45) / .55).clamp(0.0, 1.0);
          return Stack(
            children: [
              // Laid out where the band ends up, under the band while it
              // shrinks, so nothing reflows during the motion.
              Positioned(
                top: bandHeight + padding.top,
                left: 0,
                right: 0,
                bottom: 0,
                child: Opacity(
                  opacity: rest,
                  child: Transform.translate(
                    offset: Offset(0, 24 * (1 - rest)),
                    child: _WelcomeActions(page: page, onSignUp: onSignUp),
                  ),
                ),
              ),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                height: band,
                child: Container(
                  decoration: BoxDecoration(
                    color: Color.lerp(
                      AppConfig.primaryColor,
                      bandColor,
                      settled,
                    ),
                    borderRadius: BorderRadius.vertical(
                      bottom: Radius.circular(32 * settled),
                    ),
                  ),
                  child: Stack(
                    children: [
                      Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            SizedBox(height: padding.top * settled),
                            SizedBox.square(
                              dimension: mark,
                              child: page.isLoading
                                  ? SeamStitchLoader(size: mark)
                                  : SeamMark(size: mark),
                            ),
                            ClipRect(
                              child: Align(
                                heightFactor: page.isLoading ? 1 : rest,
                                child: Opacity(
                                  opacity: page.isLoading ? 1 : rest,
                                  child: Padding(
                                    padding: const EdgeInsets.only(top: 12),
                                    child: page.isLoading
                                        ? Text(
                                            loggingInToHomeserver == null
                                                ? l10n.loadingPleaseWait
                                                : l10n.logInTo(
                                                    loggingInToHomeserver,
                                                  ),
                                            style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 16,
                                            ),
                                          )
                                        : Column(
                                            children: [
                                              Text(
                                                AppSettings
                                                    .applicationName
                                                    .value,
                                                style: theme
                                                    .textTheme
                                                    .displaySmall
                                                    ?.copyWith(
                                                      color: Colors.white,
                                                      fontWeight:
                                                          FontWeight.w600,
                                                    ),
                                              ),
                                              const SizedBox(height: 4),
                                              Text(
                                                l10n.welcomeTagline,
                                                style: const TextStyle(
                                                  color: Colors.white70,
                                                  fontSize: 16,
                                                ),
                                              ),
                                            ],
                                          ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (!page.isLoading && page.addingAccount)
                        PositionedDirectional(
                          top: padding.top + 4,
                          start: 4,
                          child: Opacity(
                            opacity: rest,
                            child: CloseButton(
                              color: Colors.white,
                              onPressed: () => context.go('/rooms'),
                            ),
                          ),
                        ),
                      if (!page.isLoading)
                        PositionedDirectional(
                          top: padding.top + 4,
                          end: 4,
                          child: Opacity(
                            opacity: rest,
                            child: const _WelcomeMenu(),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }
}

class _WelcomeActions extends StatelessWidget {
  final IntroPage page;
  final VoidCallback onSignUp;

  const _WelcomeActions({required this.page, required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(24, 24, 24, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: SingleChildScrollView(
                child: Text(
                  page.welcomeText ?? l10n.welcomeBody,
                  style: theme.textTheme.bodyLarge?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                ),
              ),
            ),
            SignInTermsGate(
              builder: (context, gate) => OnboardingButtonTheme(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: gate(page.login),
                      child: Text(l10n.signIn),
                    ),
                    if (!page.hasPresetHomeserver) ...[
                      const SizedBox(height: 8),
                      TextButton(
                        onPressed: gate(onSignUp),
                        child: Text(l10n.createAnAccount),
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Restore from a backup file, the privacy policy and About.
class _WelcomeMenu extends StatelessWidget {
  const _WelcomeMenu();

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    Widget item(IconData icon, String label) => Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 12,
      children: [
        Icon(icon),
        Flexible(
          child: Text(label, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
    return PopupMenuButton(
      useRootNavigator: true,
      tooltip: l10n.moreOptions,
      icon: const Icon(Icons.more_vert, color: Colors.white),
      itemBuilder: (_) => [
        PopupMenuItem(
          onTap: () => restoreBackupFlow(context),
          child: item(Icons.restore_page_outlined, l10n.hydrate),
        ),
        PopupMenuItem(
          onTap: () => launchUrlString(
            AppSettings.privacyPolicyPageUrl.value,
            mode: LaunchMode.externalApplication,
          ),
          child: item(Icons.privacy_tip_outlined, l10n.privacyPolicy),
        ),
        PopupMenuItem(
          onTap: () => PlatformInfos.showDialog(context),
          child: item(Icons.info_outlined, l10n.about),
        ),
      ],
    );
  }
}
