// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/services.dart';
import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

abstract class FluffyThemes {
  static const double columnWidth = 380.0;

  static const double maxTimelineWidth = columnWidth * 2;

  static const double navRailWidth = 80.0;

  static bool isColumnModeByWidth(double width) =>
      width > columnWidth * 2 + navRailWidth;

  static bool isColumnMode(BuildContext context) =>
      isColumnModeByWidth(MediaQuery.sizeOf(context).width);

  static bool isThreeColumnMode(BuildContext context) =>
      MediaQuery.sizeOf(context).width > FluffyThemes.columnWidth * 3.5;

  static LinearGradient backgroundGradient(BuildContext context, int alpha) {
    final colorScheme = Theme.of(context).colorScheme;
    return LinearGradient(
      begin: Alignment.topCenter,
      colors: [
        colorScheme.primaryContainer.withAlpha(alpha),
        colorScheme.secondaryContainer.withAlpha(alpha),
        colorScheme.tertiaryContainer.withAlpha(alpha),
        colorScheme.primaryContainer.withAlpha(alpha),
      ],
    );
  }

  static const Duration animationDuration = Duration(milliseconds: 250);
  static const Curve animationCurve = Curves.easeInOut;

  /// ColorScheme.fromSeed computes its tonal palettes from scratch and is
  /// costly. buildTheme runs for both brightnesses whenever the app root
  /// rebuilds (it reads the window width), usually with unchanged inputs.
  /// The immutable result depends only on brightness and seed. The default
  /// seed, Seam Cobalt, gets [seamCobaltScheme]; any other seed the user
  /// picks gets fromSeed's rainbow scheme.
  static final Map<(Brightness, Color), ColorScheme> _colorSchemeCache = {};

  static ColorScheme _colorSchemeFor(Brightness brightness, Color seed) {
    final key = (brightness, seed);
    final cached = _colorSchemeCache[key];
    if (cached != null) return cached;
    // Each pick in the color settings adds a seed; a handful covers the
    // light and dark schemes of the current and previous choices.
    if (_colorSchemeCache.length >= 8) _colorSchemeCache.clear();
    return _colorSchemeCache[key] = seed == AppConfig.primaryColor
        ? seamCobaltScheme(brightness)
        : ColorScheme.fromSeed(
            brightness: brightness,
            seedColor: seed,
            dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
          );
  }

  /// The HCT hue of Seam Cobalt's light tints, #7EA6FF. HCT keeps a
  /// colour's hue as its chroma falls, but the seed's own hue (about 271)
  /// reads lavender in the light, low-chroma tones that dark mode uses.
  static final double cobaltHue = Hct.fromInt(0xFF7EA6FF).hue;

  /// The scheme of the default seed: fromSeed's rainbow scheme, whose
  /// surfaces are neutral greys, with the primary and secondary roles
  /// retuned so the accent stays cobalt. The primary roles sit on
  /// [cobaltHue] at more chroma than fromSeed gives them, and the
  /// secondary roles, which fill the selected chat, are a quiet blue
  /// turned 15 degrees towards cyan, where low chroma reads slate rather
  /// than violet. In dark mode primary is tone 70 rather than 80, a cobalt
  /// tint rather than periwinkle, and the selection is tone 26 so primary
  /// text on it (someone typing) keeps 4.5:1.
  static ColorScheme seamCobaltScheme(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final primary = TonalPalette.of(cobaltHue, 56);
    final container = TonalPalette.of(cobaltHue, 36);
    final secondary = TonalPalette.of(cobaltHue - 15, 16);
    Color tone(TonalPalette palette, int tone) => Color(palette.get(tone));
    return ColorScheme.fromSeed(
      brightness: brightness,
      seedColor: AppConfig.primaryColor,
      dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
    ).copyWith(
      primary: tone(primary, dark ? 70 : 40),
      surfaceTint: tone(primary, dark ? 70 : 40),
      onPrimary: tone(primary, dark ? 15 : 100),
      primaryContainer: tone(container, dark ? 30 : 90),
      onPrimaryContainer: tone(container, dark ? 90 : 10),
      inversePrimary: tone(primary, dark ? 40 : 70),
      primaryFixed: tone(primary, 90),
      primaryFixedDim: tone(primary, 80),
      onPrimaryFixed: tone(primary, 10),
      onPrimaryFixedVariant: tone(primary, 30),
      secondary: tone(secondary, dark ? 80 : 40),
      onSecondary: tone(secondary, dark ? 20 : 100),
      secondaryContainer: tone(secondary, dark ? 26 : 90),
      onSecondaryContainer: tone(secondary, dark ? 90 : 10),
      secondaryFixed: tone(secondary, 90),
      secondaryFixedDim: tone(secondary, 80),
      onSecondaryFixed: tone(secondary, 10),
      onSecondaryFixedVariant: tone(secondary, 30),
    );
  }

  /// The colour of every menu: a step lighter than anything it opens over
  /// in dark mode (the chat pane, the received bubbles in
  /// surfaceContainerHigh), and white in light mode, where its shadow
  /// lifts it off the pane. No outline.
  static Color menuColor(ColorScheme colorScheme) =>
      colorScheme.brightness == Brightness.dark
      ? colorScheme.surfaceContainerHighest
      : colorScheme.surfaceContainerLowest;

  /// Material 3 elevation level 2, the level of menus.
  static const double menuElevation = 3;

  static ThemeData buildTheme(
    BuildContext context,
    Brightness brightness, [
    Color? seed,
  ]) {
    final colorScheme = _colorSchemeFor(
      brightness,
      seed ?? Color(AppSettings.colorSchemeSeedInt.value),
    );
    final isColumnMode = FluffyThemes.isColumnMode(context);
    final dividerColor = brightness == Brightness.dark
        ? colorScheme.surfaceContainerHighest
        : colorScheme.surfaceContainer;
    return ThemeData(
      // Bundled, so text looks and measures the same on every platform.
      fontFamily: 'GoogleSansFlex',
      visualDensity: VisualDensity.standard,
      useMaterial3: true,
      brightness: brightness,
      colorScheme: colorScheme,
      dividerColor: dividerColor,
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          iconColor: colorScheme.onSurface,
          disabledIconColor: colorScheme.onSurface,
        ),
      ),
      // Pages slide sideways and stay opaque, so the page underneath never
      // shows through the one leaving.
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {TargetPlatform.android: _SolidSlidePageTransitionsBuilder()},
      ),
      // Menus hang below the button that opened them rather than covering
      // it. Without room underneath, a menu opens above where it fits there
      // and otherwise shifts up to stay on screen.
      popupMenuTheme: PopupMenuThemeData(
        position: PopupMenuPosition.under,
        // Rounded like the app's bubbles and dialogs.
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
        color: menuColor(colorScheme),
        surfaceTintColor: Colors.transparent,
        elevation: menuElevation,
      ),
      // MenuAnchor menus look the same.
      menuTheme: MenuThemeData(
        style: MenuStyle(
          backgroundColor: WidgetStatePropertyAll(menuColor(colorScheme)),
          surfaceTintColor: const WidgetStatePropertyAll(Colors.transparent),
          elevation: const WidgetStatePropertyAll(menuElevation),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(AppConfig.borderRadius),
            ),
          ),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        selectionColor: colorScheme.onSurface.withAlpha(128),
        selectionHandleColor: colorScheme.secondary,
      ),
      inputDecorationTheme: InputDecorationTheme(
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
        ),
        contentPadding: const EdgeInsets.all(12),
      ),
      chipTheme: ChipThemeData(
        showCheckmark: false,
        // Outlined at rest, filled only when selected (Material 3 filter
        // chips), so the selected one is the only filled shape in a row.
        backgroundColor: colorScheme.surface,
        selectedColor: colorScheme.secondaryContainer,
        side: WidgetStateBorderSide.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? BorderSide.none
              : BorderSide(color: colorScheme.outlineVariant),
        ),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        ),
      ),
      appBarTheme: AppBarTheme(
        toolbarHeight: isColumnMode ? 72 : 56,
        surfaceTintColor: isColumnMode ? colorScheme.surface : null,
        backgroundColor: isColumnMode ? colorScheme.surface : null,
        actionsPadding: isColumnMode
            ? const EdgeInsets.symmetric(horizontal: 16.0)
            : null,
        systemOverlayStyle: SystemUiOverlayStyle(
          statusBarColor: Colors.transparent,
          statusBarIconBrightness: brightness.reversed,
          statusBarBrightness: brightness,
          systemNavigationBarIconBrightness: brightness.reversed,
          systemNavigationBarColor: colorScheme.surface,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          side: BorderSide(width: 1, color: colorScheme.primary),
          shape: RoundedRectangleBorder(
            side: BorderSide(color: colorScheme.primary),
            borderRadius: BorderRadius.circular(AppConfig.borderRadius / 2),
          ),
        ),
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        strokeCap: StrokeCap.round,
        color: colorScheme.primary,
        refreshBackgroundColor: colorScheme.primaryContainer,
      ),
      snackBarTheme: isColumnMode
          ? const SnackBarThemeData(
              showCloseIcon: true,
              behavior: SnackBarBehavior.floating,
              width: FluffyThemes.columnWidth * 1.5,
            )
          : const SnackBarThemeData(behavior: SnackBarBehavior.floating),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: colorScheme.secondaryContainer,
          foregroundColor: colorScheme.onSecondaryContainer,
          elevation: 0,
          padding: const EdgeInsets.all(16),
          textStyle: const TextStyle(fontSize: 16),
        ),
      ),
    );
  }

  /// The theme inside the column-mode chat card (TwoColumnLayout). The
  /// card's colour, surfaceContainerLow, stands in for surface, so scaffolds,
  /// app bars, chips and the composer's backdrop blend into the card.
  static ThemeData cardPaneTheme(ThemeData theme) {
    final cardColor = theme.colorScheme.surfaceContainerLow;
    return theme.copyWith(
      colorScheme: theme.colorScheme.copyWith(surface: cardColor),
      scaffoldBackgroundColor: cardColor,
      canvasColor: cardColor,
      appBarTheme: theme.appBarTheme.copyWith(
        backgroundColor: cardColor,
        surfaceTintColor: cardColor,
      ),
      chipTheme: theme.chipTheme.copyWith(backgroundColor: cardColor),
    );
  }
}

extension on Brightness {
  Brightness get reversed =>
      this == Brightness.dark ? Brightness.light : Brightness.dark;
}

extension BubbleColorTheme on ThemeData {
  Color get bubbleColor => brightness == Brightness.light
      ? colorScheme.primary
      : colorScheme.primaryContainer;

  Color get onBubbleColor => brightness == Brightness.light
      ? colorScheme.onPrimary
      : colorScheme.onPrimaryContainer;

  Color get secondaryBubbleColor => HSLColor.fromColor(
    brightness == Brightness.light
        ? colorScheme.tertiary
        : colorScheme.tertiaryContainer,
  ).withSaturation(0.5).toColor();
}

/// Slides a page in from the right and back out again without ever changing
/// its opacity, and leaves the page underneath untouched.
class _SolidSlidePageTransitionsBuilder extends PageTransitionsBuilder {
  const _SolidSlidePageTransitionsBuilder();

  static final _offset = Tween<Offset>(
    begin: const Offset(1, 0),
    end: Offset.zero,
  );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => SlideTransition(
    position: _offset.animate(
      CurvedAnimation(
        parent: animation,
        curve: Curves.easeOutCubic,
        reverseCurve: Curves.easeInCubic,
      ),
    ),
    child: child,
  );
}
