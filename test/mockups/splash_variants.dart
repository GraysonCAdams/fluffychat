// Mockup prototypes of the welcome page, for review only.

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/widgets/layouts/login_scaffold.dart';
import 'package:fluffychat/widgets/onboarding/onboarding_step.dart';
import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:material_ui/material_ui.dart';

const _slogan = 'Where all your threads meet.';
const _body =
    'All your chats in one place. Sign in to your own Matrix account, and '
    'the bridges on your homeserver bring your other networks here.';
const _periwinkle = SeamStitchPainter.periwinkle;

/// The mark in the brand duotone: white, periwinkle above the seam.
class DuoMark extends StatelessWidget {
  final double size;
  const DuoMark(this.size, {super.key});

  @override
  Widget build(BuildContext context) => CustomPaint(
    size: Size.square(size),
    painter: SeamStitchPainter(
      motion: SeamStitchMotion()..land(),
      ink: Colors.white,
      pale: _periwinkle,
    ),
  );
}

Color _band(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark
    ? const Color(0xFF12347F)
    : AppConfig.primaryColor;

Widget _kebab([Color color = Colors.white]) => IconButton(
  onPressed: () {},
  icon: Icon(Icons.more_vert, color: color),
);

TextSpan _link(BuildContext context, String text) => TextSpan(
  text: text,
  style: TextStyle(
    color: Theme.of(context).colorScheme.primary,
    fontWeight: FontWeight.w600,
    decoration: TextDecoration.underline,
    decorationColor: Theme.of(context).colorScheme.primary,
  ),
);

Widget _checkbox(bool agreed) => SizedBox.square(
  dimension: 48,
  child: Checkbox(value: agreed, onChanged: (_) {}),
);

/// A: a tonal container holding a two-line list item, the links in the
/// supporting text.
class TermsTonal extends StatelessWidget {
  final bool agreed;
  const TermsTonal(this.agreed, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: agreed ? cs.secondaryContainer : cs.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 12, 16, 12),
        child: Row(
          children: [
            _checkbox(agreed),
            const SizedBox(width: 4),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'I agree to the Terms of use',
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: cs.onSurface,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text.rich(
                    TextSpan(
                      children: [
                        const TextSpan(text: 'Read the '),
                        _link(context, 'Terms of use'),
                        const TextSpan(text: ' and the '),
                        _link(context, 'Privacy policy'),
                        const TextSpan(text: '.'),
                      ],
                    ),
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: cs.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// B: an outlined card, the list item above a divider and the two
/// documents as text buttons with an open-in-browser icon.
class TermsOutlined extends StatelessWidget {
  final bool agreed;
  const TermsOutlined(this.agreed, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    Widget doc(String label) => TextButton.icon(
      onPressed: () {},
      iconAlignment: IconAlignment.end,
      icon: const Icon(Icons.open_in_new, size: 18),
      label: Text(label),
    );
    return Material(
      color: cs.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: agreed ? cs.primary : cs.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 16, 8),
            child: Row(
              children: [
                _checkbox(agreed),
                const SizedBox(width: 4),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'I agree to the Terms of use',
                        style: theme.textTheme.bodyLarge?.copyWith(
                          color: cs.onSurface,
                        ),
                      ),
                      Text(
                        'Needed before you sign in',
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: cs.outlineVariant),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Row(
              children: [doc('Terms of use'), doc('Privacy policy')],
            ),
          ),
        ],
      ),
    );
  }
}

/// C: a filled card with one sentence, the documents as inline links.
class TermsInline extends StatelessWidget {
  final bool agreed;
  const TermsInline(this.agreed, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    return Material(
      color: agreed ? cs.primaryContainer : cs.surfaceContainerHighest,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(4, 8, 16, 8),
        child: Row(
          children: [
            _checkbox(agreed),
            const SizedBox(width: 4),
            Expanded(
              child: Text.rich(
                TextSpan(
                  children: [
                    const TextSpan(text: 'I agree to the '),
                    _link(context, 'Terms of use'),
                    const TextSpan(text: ' and have read the '),
                    _link(context, 'Privacy policy'),
                    const TextSpan(text: '.'),
                  ],
                ),
                style: theme.textTheme.bodyLarge?.copyWith(
                  color: agreed ? cs.onPrimaryContainer : cs.onSurface,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

enum Secondary { text, tonal, outlined }

class Actions extends StatelessWidget {
  final bool agreed;
  final Secondary secondary;
  const Actions(this.agreed, this.secondary, {super.key});

  @override
  Widget build(BuildContext context) {
    final onPressed = agreed ? () {} : null;
    const label = Text('Create an account');
    return OnboardingButtonTheme(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          FilledButton(onPressed: onPressed, child: const Text('Sign in')),
          const SizedBox(height: 8),
          switch (secondary) {
            Secondary.text => TextButton(onPressed: onPressed, child: label),
            Secondary.tonal => FilledButton.tonal(
              onPressed: onPressed,
              style: FilledButton.styleFrom(
                minimumSize: const Size.fromHeight(56),
              ),
              child: label,
            ),
            Secondary.outlined => OutlinedButton(
              onPressed: onPressed,
              child: label,
            ),
          },
        ],
      ),
    );
  }
}

Widget _bodyText(BuildContext context, {Color? color, TextAlign? align}) =>
    Text(
      _body,
      textAlign: align,
      style: Theme.of(context).textTheme.bodyLarge?.copyWith(
        color: color ?? Theme.of(context).colorScheme.onSurfaceVariant,
        height: 1.5,
      ),
    );

/// A. Hero band: today's structure with the band grown to hold a
/// hero-scale duotone mark and the slogan as a headline.
class VariantA extends StatelessWidget {
  final bool agreed, wide;
  const VariantA({required this.agreed, this.wide = false, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final top = MediaQuery.paddingOf(context).top;
    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          height: (wide ? 300 : 440) + top,
          padding: EdgeInsets.only(top: top),
          decoration: BoxDecoration(
            color: _band(context),
            borderRadius: const BorderRadius.vertical(
              bottom: Radius.circular(28),
            ),
          ),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    DuoMark(wide ? 128 : 176),
                    const SizedBox(height: 16),
                    Text(
                      'Seam',
                      style: theme.textTheme.displaySmall?.copyWith(
                        color: Colors.white,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      _slogan,
                      style: theme.textTheme.titleLarge?.copyWith(
                        color: _periwinkle,
                      ),
                    ),
                  ],
                ),
              ),
              PositionedDirectional(top: 4, end: 4, child: _kebab()),
            ],
          ),
        ),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(24, 24, 24, 0),
            child: _bodyText(context),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              TermsTonal(agreed),
              const SizedBox(height: 16),
              Actions(agreed, Secondary.text),
            ],
          ),
        ),
      ],
    );
    if (wide) return LoginScaffold(body: body);
    return Scaffold(body: SafeArea(top: false, child: body));
  }
}

Widget _sloganRich(
  BuildContext context,
  TextStyle? style, {
  required Color color,
  required Color accent,
  TextAlign align = TextAlign.start,
}) => Text.rich(
  TextSpan(
    children: [
      const TextSpan(text: 'Where all your '),
      TextSpan(
        text: 'threads',
        style: TextStyle(color: accent),
      ),
      const TextSpan(text: ' meet.'),
    ],
  ),
  textAlign: align,
  style: style?.copyWith(
    color: color,
    fontWeight: FontWeight.w600,
    letterSpacing: -.5,
  ),
);

/// B. Full cobalt: the start screen's cobalt stays, the mark keeps the
/// loader's 192 dp, the slogan is the display line and the actions sit on
/// a surface sheet with the bottom sheet's 28 dp top corners.
class VariantB extends StatelessWidget {
  final bool agreed, wide;
  const VariantB({required this.agreed, this.wide = false, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final (start, end) = LoginScaffold.backgroundColors(theme.brightness);
    final padding = MediaQuery.paddingOf(context);
    final actions = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        TermsOutlined(agreed),
        const SizedBox(height: 16),
        Actions(agreed, Secondary.tonal),
      ],
    );
    Widget hero(double mark, TextStyle? display, CrossAxisAlignment cross) =>
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: cross,
          children: [
            DuoMark(mark),
            const SizedBox(height: 24),
            _sloganRich(
              context,
              display,
              color: Colors.white,
              accent: _periwinkle,
              align: cross == CrossAxisAlignment.center
                  ? TextAlign.center
                  : TextAlign.start,
            ),
            const SizedBox(height: 12),
            _bodyText(
              context,
              color: Colors.white.withValues(alpha: .8),
              align: cross == CrossAxisAlignment.center
                  ? TextAlign.center
                  : TextAlign.start,
            ),
          ],
        );
    final background = BoxDecoration(
      gradient: LinearGradient(
        colors: [start, end],
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
      ),
    );
    if (wide) {
      return Scaffold(
        body: DecoratedBox(
          decoration: background,
          child: Stack(
            children: [
              Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 1040),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 24),
                    child: Row(
                      children: [
                        Expanded(
                          child: hero(
                            224,
                            theme.textTheme.displayMedium,
                            CrossAxisAlignment.start,
                          ),
                        ),
                        const SizedBox(width: 72),
                        Material(
                          color: cs.surface,
                          borderRadius: BorderRadius.circular(28),
                          elevation: 8,
                          shadowColor: Colors.black54,
                          child: SizedBox(
                            width: 440,
                            child: Padding(
                              padding: const EdgeInsets.all(24),
                              child: actions,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ),
              PositionedDirectional(top: 8, end: 8, child: _kebab()),
            ],
          ),
        ),
      );
    }
    return Scaffold(
      body: DecoratedBox(
        decoration: background,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(
              child: Stack(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(24, padding.top, 24, 0),
                    child: Center(
                      child: hero(
                        192,
                        theme.textTheme.displaySmall,
                        CrossAxisAlignment.center,
                      ),
                    ),
                  ),
                  PositionedDirectional(
                    top: padding.top + 4,
                    end: 4,
                    child: _kebab(),
                  ),
                ],
              ),
            ),
            Material(
              color: cs.surface,
              borderRadius: const BorderRadius.vertical(
                top: Radius.circular(28),
              ),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, 24, 16, 16 + padding.bottom),
                child: actions,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// C. Editorial: a cobalt hero card inset by the window margin, then the
/// slogan left-aligned on the surface as the display line, "threads" in
/// primary as on the site.
class VariantC extends StatelessWidget {
  final bool agreed, wide;
  const VariantC({required this.agreed, this.wide = false, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final top = MediaQuery.paddingOf(context).top;
    final margin = wide ? 24.0 : 16.0;
    final body = Padding(
      padding: EdgeInsets.fromLTRB(margin, top + (wide ? 24 : 8), margin, 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            height: wide ? 200 : 304,
            decoration: BoxDecoration(
              color: _band(context),
              borderRadius: BorderRadius.circular(28),
            ),
            child: Stack(
              children: [
                Center(child: DuoMark(wide ? 136 : 208)),
                PositionedDirectional(top: 4, end: 4, child: _kebab()),
              ],
            ),
          ),
          SizedBox(height: wide ? 24 : 32),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8),
            child: _sloganRich(
              context,
              wide
                  ? theme.textTheme.headlineLarge
                  : theme.textTheme.displaySmall,
              color: cs.onSurface,
              accent: cs.primary,
            ),
          ),
          const SizedBox(height: 12),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _bodyText(context),
            ),
          ),
          TermsInline(agreed),
          const SizedBox(height: 16),
          Actions(agreed, Secondary.outlined),
        ],
      ),
    );
    if (wide) return LoginScaffold(body: body);
    return Scaffold(body: SafeArea(top: false, child: body));
  }
}
