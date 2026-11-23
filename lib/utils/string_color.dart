// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

extension StringColor on String {
  // The seed colour only depends on which of 12 hues the string falls in, so
  // there are only 12 possible schemes. Keying the cache by hue instead of
  // by string keeps it at 12 entries however many names are seen.
  static final _colorSchemeCache = List<ColorScheme?>.filled(12, null);

  ColorScheme get colorScheme {
    final hue = _hueBucket;
    return _colorSchemeCache[hue] ??= ColorScheme.fromSeed(
      seedColor: HSLColor.fromAHSL(0.75, hue * 25.5, 1, 0.3).toColor(),
      dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
    );
  }

  /// The sum of the UTF-16 code units, modulo 12.
  int get _hueBucket {
    var number = 0;
    for (var i = 0; i < length; i++) {
      number += codeUnitAt(i);
    }
    return number % 12;
  }
}
