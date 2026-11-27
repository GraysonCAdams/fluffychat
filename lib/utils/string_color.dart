// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_color_utilities/material_color_utilities.dart';
import 'package:material_ui/material_ui.dart';

extension StringColor on String {
  /// The HCT hue and chroma of each of the 12 initials colours. Warm hues,
  /// greens and blues around the app's cobalt, a slate and a near-neutral
  /// grey, so neighbouring contacts stay apart; no pinks or violets, which
  /// clash with the cobalt accent.
  static const _hues = <(double, double)>[
    (40, 36), // coral
    (60, 36), // orange
    (90, 36), // amber
    (120, 36), // lime
    (145, 36), // green
    (175, 30), // mint
    (200, 30), // teal
    (225, 30), // sky
    (250, 30), // azure
    (268, 36), // cobalt
    (250, 12), // slate
    (250, 4), // grey
  ];

  static final _cache = List<({Color fill, Color onFill})?>.filled(
    _hues.length,
    null,
  );

  /// The colours of initials for this string: a light [fill] (tone 90) and
  /// dark letters on it ([onFill], tone 30), the same in light and dark
  /// mode. Picked from 12 by the string, so the same name always gets the
  /// same colour.
  ({Color fill, Color onFill}) get avatarColors {
    final index = _bucket;
    return _cache[index] ??= () {
      final (hue, chroma) = _hues[index];
      final palette = TonalPalette.of(hue, chroma);
      return (fill: Color(palette.get(90)), onFill: Color(palette.get(30)));
    }();
  }

  /// The sum of the UTF-16 code units, modulo the number of colours.
  int get _bucket {
    var number = 0;
    for (var i = 0; i < length; i++) {
      number += codeUnitAt(i);
    }
    return number % _hues.length;
  }
}
