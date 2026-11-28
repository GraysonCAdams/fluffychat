// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'package:material_ui/material_ui.dart';

/// The layout every onboarding step shares, from the server step to device
/// verification: an optional hero, a headline, body text, the step's own
/// [content], and the actions pinned to the bottom, one filled [primary]
/// button with quieter [secondary] ones under it.
///
/// It sits in a [LoginScaffold], so on a wide window it becomes the
/// centred card on the brand background.
class OnboardingStep extends StatelessWidget {
  final Widget? leading;
  final List<Widget> actions;
  final String? appBarTitle;
  final Widget? hero;
  final String headline;
  final String? body;
  final List<Widget> content;
  final Widget? primary;
  final List<Widget> secondary;

  /// Centres the hero, headline and body: for status steps (waiting,
  /// done) rather than steps that ask for something.
  final bool centered;

  const OnboardingStep({
    super.key,
    this.leading,
    this.actions = const [],
    this.appBarTitle,
    this.hero,
    required this.headline,
    this.body,
    this.content = const [],
    this.primary,
    this.secondary = const [],
    this.centered = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textAlign = centered ? TextAlign.center : TextAlign.start;
    final hero = this.hero;
    final body = this.body;
    final primary = this.primary;
    return LoginScaffold(
      appBar: AppBar(
        leading: leading,
        automaticallyImplyLeading: false,
        title: appBarTitle == null ? null : Text(appBarTitle!),
        titleTextStyle: theme.textTheme.titleMedium,
        centerTitle: true,
        actions: actions,
        backgroundColor: colorScheme.surface,
        surfaceTintColor: colorScheme.surface,
        scrolledUnderElevation: 0,
      ),
      body: Column(
        children: [
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 16),
              child: Column(
                crossAxisAlignment: centered
                    ? CrossAxisAlignment.center
                    : CrossAxisAlignment.stretch,
                children: [
                  if (hero != null) ...[
                    Align(
                      alignment: centered
                          ? Alignment.center
                          : AlignmentDirectional.centerStart,
                      child: hero,
                    ),
                    const SizedBox(height: 24),
                  ],
                  Text(
                    headline,
                    textAlign: textAlign,
                    style: theme.textTheme.headlineSmall?.copyWith(
                      fontWeight: FontWeight.w600,
                      color: colorScheme.onSurface,
                    ),
                  ),
                  if (body != null) ...[
                    const SizedBox(height: 12),
                    Text(
                      body,
                      textAlign: textAlign,
                      style: theme.textTheme.bodyLarge?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        height: 1.4,
                      ),
                    ),
                  ],
                  if (content.isNotEmpty) const SizedBox(height: 24),
                  ...content,
                ],
              ),
            ),
          ),
          if (primary != null || secondary.isNotEmpty)
            Padding(
              padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
              child: OnboardingButtonTheme(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  spacing: 8,
                  children: [?primary, ...secondary],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// Full-width step actions: filled and outlined buttons 56 dp tall, text
/// buttons 48 dp, all with the label in a semibold 16.
class OnboardingButtonTheme extends StatelessWidget {
  final Widget child;
  const OnboardingButtonTheme({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelLarge?.copyWith(
      fontSize: 16,
      fontWeight: FontWeight.w600,
    );
    return Theme(
      data: theme.copyWith(
        filledButtonTheme: FilledButtonThemeData(
          style: FilledButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: label,
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(56),
            textStyle: label,
            shape: const StadiumBorder(),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            minimumSize: const Size.fromHeight(48),
            textStyle: label,
          ),
        ),
      ),
      child: child,
    );
  }
}

/// How a hero icon or notice is coloured.
enum OnboardingTone { brand, success, error, neutral }

(Color, Color) _toneColors(BuildContext context, OnboardingTone tone) {
  final colorScheme = Theme.of(context).colorScheme;
  final dark = Theme.of(context).brightness == Brightness.dark;
  return switch (tone) {
    OnboardingTone.brand => (
      colorScheme.primaryContainer,
      colorScheme.onPrimaryContainer,
    ),
    // Material has no success role; these are a green tonal pair at the
    // same tones as the containers.
    OnboardingTone.success => (
      dark ? const Color(0xFF1E4A2E) : const Color(0xFFCDEFD6),
      dark ? const Color(0xFFB6F2C6) : const Color(0xFF0F3D1E),
    ),
    OnboardingTone.error => (
      colorScheme.errorContainer,
      colorScheme.onErrorContainer,
    ),
    OnboardingTone.neutral => (
      colorScheme.surfaceContainerHigh,
      colorScheme.onSurface,
    ),
  };
}

/// An icon in a rounded tonal square, the hero of most steps.
class OnboardingHeroIcon extends StatelessWidget {
  final IconData icon;
  final OnboardingTone tone;
  final double size;

  const OnboardingHeroIcon(
    this.icon, {
    super.key,
    this.tone = OnboardingTone.brand,
    this.size = 72,
  });

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _toneColors(context, tone);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(size * .32),
      ),
      child: Icon(icon, color: foreground, size: size * .5),
    );
  }
}

/// A short inline message in a tonal card, with an optional action.
class OnboardingNotice extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;
  final OnboardingTone tone;

  const OnboardingNotice({
    super.key,
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
    this.tone = OnboardingTone.neutral,
  });

  @override
  Widget build(BuildContext context) {
    final (background, foreground) = _toneColors(context, tone);
    final actionLabel = this.actionLabel;
    return Container(
      padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 8, 12),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Row(
        children: [
          Icon(icon, color: foreground, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: TextStyle(color: foreground, fontSize: 14, height: 1.35),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                foregroundColor: foreground,
                minimumSize: const Size(0, 40),
              ),
              child: Text(actionLabel),
            ),
        ],
      ),
    );
  }
}

/// A large tappable choice: an icon, a title and a line of detail.
class OnboardingOption extends StatelessWidget {
  final IconData icon;
  final String title;
  final String subtitle;
  final bool emphasized;
  final VoidCallback? onTap;

  const OnboardingOption({
    super.key,
    required this.icon,
    required this.title,
    required this.subtitle,
    this.emphasized = false,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final foreground = emphasized
        ? colorScheme.onPrimaryContainer
        : colorScheme.onSurface;
    return Material(
      color: emphasized
          ? colorScheme.primaryContainer
          : colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.hardEdge,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Icon(
                icon,
                size: 28,
                color: emphasized ? foreground : colorScheme.primary,
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: foreground,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13.5,
                        color: emphasized
                            ? foreground
                            : colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(Icons.chevron_right, color: colorScheme.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

/// One benefit line: an icon in the primary colour and a sentence.
class OnboardingBullet extends StatelessWidget {
  final IconData icon;
  final String text;

  const OnboardingBullet(this.icon, this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 22, color: colorScheme.primary),
          const SizedBox(width: 14),
          Expanded(
            child: Text(
              text,
              style: TextStyle(
                fontSize: 15,
                height: 1.35,
                color: colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The filled button that is busy: a small spinner in place of its label.
class OnboardingBusyButton extends StatelessWidget {
  const OnboardingBusyButton({super.key});

  @override
  Widget build(BuildContext context) => const FilledButton(
    onPressed: null,
    child: SizedBox.square(
      dimension: 22,
      child: CircularProgressIndicator(strokeWidth: 2.5),
    ),
  );
}
