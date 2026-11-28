// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

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

/// The welcome page: the Seam mark, the slogan and a line on what Seam
/// does on cobalt, and a surface sheet with the Terms of use card, Sign in
/// and Create an account.
///
/// A portrait or narrow window stacks the two, the sheet at the bottom. A
/// wide window, or a landscape one at least [twoPaneMinWidth] dp wide,
/// puts them side by side with the sheet as a card.
///
/// The first stacked welcome page after launch takes over from the start
/// screen (see [SeamStartup.handOff]): it begins as a full screen of
/// cobalt with the mark where the loader left it, then the sheet slides
/// up, the mark rises with the space left above it and the words come in.
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
  });

  /// Whether this run of the app has already shown the morph.
  @visibleForTesting
  static bool morphed = false;

  static const Duration morphDuration = Duration(milliseconds: 900);

  /// The narrowest window that gets two panes: the Material 3 medium
  /// window class starts here.
  static const double twoPaneMinWidth = 600;

  /// The stacked mark's size: the loader's, so it only moves during the
  /// morph, or [compactMarkSize], with a smaller slogan, in a window under
  /// [compactHeight] dp tall.
  static const double markSize = SeamStartup.loaderSize;
  static const double compactMarkSize = 128;
  static const double compactHeight = 700;

  /// Whether a window of [size] shows the two panes side by side.
  static bool isTwoPane(Size size) =>
      size.width >= twoPaneMinWidth &&
      (FluffyThemes.isColumnModeByWidth(size.width) ||
          size.width > size.height);

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
        !IntroPage.isTwoPane(MediaQuery.sizeOf(context));
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
    final twoPane = IntroPage.isTwoPane(MediaQuery.sizeOf(context));
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(
        statusBarColor: Colors.transparent,
      ),
      child: Scaffold(
        // While loading, both layouts are the loader centred on cobalt.
        body: twoPane && !widget.isLoading
            ? _TwoPaneWelcome(page: widget, onSignUp: _signUp)
            : _StackedWelcome(
                page: widget,
                progress: CurvedAnimation(
                  parent: _morph,
                  curve: Curves.easeInOutCubicEmphasized,
                ),
                gradientAtStart: twoPane,
                onSignUp: _signUp,
              ),
      ),
    );
  }
}

BoxDecoration _background(BuildContext context, [double blend = 1]) {
  final (start, end) = LoginScaffold.backgroundColors(
    Theme.of(context).brightness,
  );
  return BoxDecoration(
    gradient: LinearGradient(
      colors: [
        Color.lerp(SeamStartup.cobalt, start, blend)!,
        Color.lerp(SeamStartup.cobalt, end, blend)!,
      ],
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
    ),
  );
}

/// The hero and the sheet in one column.
class _StackedWelcome extends StatelessWidget {
  final IntroPage page;
  final Animation<double> progress;

  /// Whether the background is the brand gradient from the first frame
  /// rather than the start screen's flat cobalt.
  final bool gradientAtStart;
  final VoidCallback onSignUp;

  const _StackedWelcome({
    required this.page,
    required this.progress,
    required this.gradientAtStart,
    required this.onSignUp,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.paddingOf(context);
    final compact = MediaQuery.sizeOf(context).height < IntroPage.compactHeight;
    final restMark = compact ? IntroPage.compactMarkSize : IntroPage.markSize;
    // Built once: the sheet keeps its state (the ticked box) through the
    // motion.
    final sheet = Center(
      child: ConstrainedBox(
        // A bottom sheet is at most 640 dp wide.
        constraints: const BoxConstraints(maxWidth: 640),
        child: Material(
          color: theme.colorScheme.surface,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          child: Padding(
            padding: EdgeInsets.fromLTRB(16, 24, 16, 16 + padding.bottom),
            child: _WelcomeActions(page: page, onSignUp: onSignUp),
          ),
        ),
      ),
    );
    return AnimatedBuilder(
      animation: progress,
      builder: (context, _) {
        // While loading, the page stays as the start screen left it.
        final settled = page.isLoading ? 0.0 : progress.value;
        final mark =
            SeamStartup.loaderSize +
            (restMark - SeamStartup.loaderSize) * settled;
        // The words come in over the last part of the motion.
        final rest = ((settled - .45) / .55).clamp(0.0, 1.0);
        return DecoratedBox(
          decoration: _background(context, gradientAtStart ? 1 : settled),
          child: Stack(
            children: [
              // Scrolls when the window is too short for both, at a large
              // text size for one.
              LayoutBuilder(
                builder: (context, constraints) => SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    // The empty first child makes the spare height fall
                    // evenly above and below the hero: the mark starts
                    // at the centre of the window, where the loader drew
                    // it, and rises as the sheet comes up.
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        const SizedBox.shrink(),
                        Padding(
                          padding: EdgeInsets.fromLTRB(
                            24,
                            padding.top * settled,
                            24,
                            24 * settled,
                          ),
                          child: Center(
                            child: _WelcomeHero(
                              page: page,
                              markSize: mark,
                              rest: rest,
                              centered: true,
                              display: compact
                                  ? theme.textTheme.headlineMedium
                                  : theme.textTheme.displaySmall,
                            ),
                          ),
                        ),
                        ClipRect(
                          child: Align(
                            alignment: Alignment.topCenter,
                            heightFactor: settled,
                            child: sheet,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              if (!page.isLoading)
                PositionedDirectional(
                  top: padding.top + 4,
                  end: 4,
                  child: Opacity(opacity: rest, child: const _WelcomeMenu()),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The hero at the start and the sheet as a card at the end.
class _TwoPaneWelcome extends StatelessWidget {
  final IntroPage page;
  final VoidCallback onSignUp;

  const _TwoPaneWelcome({required this.page, required this.onSignUp});

  static const double maxWidth = 1040;
  static const double cardWidth = LoginScaffold.cardWidth;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final padding = MediaQuery.paddingOf(context);
    return DecoratedBox(
      decoration: _background(context),
      child: Stack(
        children: [
          LayoutBuilder(
            builder: (context, constraints) {
              // Medium and expanded windows have 24 dp margins.
              final inner =
                  constraints.maxWidth.clamp(0.0, maxWidth) -
                  48 -
                  padding.horizontal;
              final roomy = inner >= 900;
              final gap = roomy ? 72.0 : 24.0;
              final card = ((inner - gap) * .55).clamp(0.0, cardWidth);
              return SingleChildScrollView(
                child: ConstrainedBox(
                  constraints: BoxConstraints(minHeight: constraints.maxHeight),
                  child: Center(
                    child: Padding(
                      padding: padding + const EdgeInsets.all(24),
                      child: SizedBox(
                        width: inner,
                        child: Row(
                          children: [
                            Expanded(
                              child: _WelcomeHero(
                                page: page,
                                markSize: roomy ? 224 : 144,
                                rest: 1,
                                centered: false,
                                display: roomy
                                    ? theme.textTheme.displayMedium
                                    : theme.textTheme.headlineLarge,
                              ),
                            ),
                            SizedBox(width: gap),
                            SizedBox(
                              width: card,
                              child: Material(
                                color: theme.colorScheme.surface,
                                borderRadius: BorderRadius.circular(28),
                                elevation: 8,
                                shadowColor: Colors.black54,
                                child: Padding(
                                  padding: const EdgeInsets.all(24),
                                  child: _WelcomeActions(
                                    page: page,
                                    onSignUp: onSignUp,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
          PositionedDirectional(
            top: padding.top + 8,
            end: 8,
            child: const _WelcomeMenu(),
          ),
        ],
      ),
    );
  }
}

/// The mark in the brand duotone with the slogan and the body text under
/// it, or, while signing in, the stitch loader and what it is waiting for.
///
/// [rest] runs from 0 to 1 as the words come in: at 0 only the mark shows,
/// as the loader leaves it.
class _WelcomeHero extends StatelessWidget {
  final IntroPage page;
  final double markSize, rest;
  final bool centered;
  final TextStyle? display;

  const _WelcomeHero({
    required this.page,
    required this.markSize,
    required this.rest,
    required this.centered,
    required this.display,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final loggingInToHomeserver = page.loggingInToHomeserver;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    final tagline = l10n.welcomeTagline;
    final accent = l10n.welcomeTaglineAccent;
    final accentAt = accent.isEmpty ? -1 : tagline.indexOf(accent);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: centered
          ? CrossAxisAlignment.center
          : CrossAxisAlignment.start,
      children: [
        SizedBox.square(
          dimension: markSize,
          child: page.isLoading
              ? SeamStitchLoader(
                  size: markSize,
                  pale: SeamStitchPainter.periwinkle,
                )
              : SeamMark(
                  size: markSize,
                  pale: SeamStitchPainter.periwinkle,
                ),
        ),
        if (page.isLoading)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(
              loggingInToHomeserver == null
                  ? l10n.loadingPleaseWait
                  : l10n.logInTo(loggingInToHomeserver),
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: Colors.white),
            ),
          )
        else
          ClipRect(
            child: Align(
              heightFactor: rest,
              child: Opacity(
                opacity: rest,
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 480),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: centered
                        ? CrossAxisAlignment.center
                        : CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 24),
                      Semantics(
                        header: true,
                        child: Text.rich(
                          accentAt < 0
                              ? TextSpan(text: tagline)
                              : TextSpan(
                                  children: [
                                    TextSpan(
                                      text: tagline.substring(0, accentAt),
                                    ),
                                    TextSpan(
                                      text: accent,
                                      style: const TextStyle(
                                        color: SeamStitchPainter.periwinkle,
                                      ),
                                    ),
                                    TextSpan(
                                      text: tagline.substring(
                                        accentAt + accent.length,
                                      ),
                                    ),
                                  ],
                                ),
                          textAlign: textAlign,
                          style: display?.copyWith(
                            color: Colors.white,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -.5,
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        page.welcomeText ?? l10n.welcomeBody,
                        textAlign: textAlign,
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: Colors.white.withValues(alpha: .8),
                          height: 1.5,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

/// The Terms of use card over Sign in and, unless the homeserver is
/// preset, Create an account.
class _WelcomeActions extends StatelessWidget {
  final IntroPage page;
  final VoidCallback onSignUp;

  const _WelcomeActions({required this.page, required this.onSignUp});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return SignInTermsGate(
      builder: (context, gate) => OnboardingButtonTheme(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const SizedBox(height: 16),
            FilledButton(onPressed: gate(page.login), child: Text(l10n.signIn)),
            if (!page.hasPresetHomeserver) ...[
              const SizedBox(height: 8),
              FilledButton.tonal(
                onPressed: gate(onSignUp),
                child: Text(l10n.createAnAccount),
              ),
            ],
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
