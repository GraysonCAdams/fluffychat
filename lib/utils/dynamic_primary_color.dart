// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:dynamic_color/dynamic_color.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Resolves the light primary color of the system's dynamic color scheme,
/// or null when the platform offers none.
///
/// This follows the lookup order of dynamic_color's DynamicColorBuilder
/// (Android core palette first, then the desktop accent color) and returns
/// the same `lightDynamic.primary` that builder would hand out. Resolving it
/// before runApp lets the first frame use the final theme. Swapping colors
/// once the platform replies would make MaterialApp animate the theme, and
/// rebuild the whole tree each frame, during startup.
Future<Color?> loadDynamicPrimaryColor() async {
  try {
    final corePalette = await DynamicColorPlugin.getCorePalette();
    if (corePalette != null) return corePalette.toColorScheme().primary;
  } on PlatformException {
    // Fall through to the accent color, as DynamicColorBuilder does.
  }

  try {
    final accentColor = await DynamicColorPlugin.getAccentColor();
    if (accentColor != null) {
      return ColorScheme.fromSeed(
        seedColor: accentColor,
        brightness: Brightness.light,
      ).primary;
    }
  } on PlatformException {
    // No dynamic color on this platform.
  }
  return null;
}
