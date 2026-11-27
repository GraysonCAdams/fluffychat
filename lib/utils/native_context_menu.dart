// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// One row of a menu that the operating system draws.
sealed class NativeMenuEntry {
  const NativeMenuEntry();
}

class NativeMenuItem extends NativeMenuEntry {
  final String label;

  /// The letter of the item's Ctrl shortcut, shown beside the label.
  final String? ctrlKey;

  /// Runs when the item is chosen. Without it the item is greyed out.
  final VoidCallback? onSelected;

  const NativeMenuItem({required this.label, this.ctrlKey, this.onSelected});
}

class NativeMenuSeparator extends NativeMenuEntry {
  const NativeMenuSeparator();
}

/// Shows [NativeMenuEntry] lists as Windows popup menus, drawn by Windows
/// itself (windows/runner/context_menu.cpp).
abstract final class NativeContextMenu {
  static const channel = MethodChannel('chat.fluffy.fluffychat/context_menu');

  static bool get isSupported => PlatformInfos.isWindows;

  /// The channel arguments for [entries], opened at [position] in physical
  /// pixels of the Flutter view. Each item's id is its index plus one, since
  /// Windows reports a dismissed menu as 0.
  static Map<String, Object?> encode(
    List<NativeMenuEntry> entries, {
    required Offset position,
    required bool dark,
  }) => {
    'x': position.dx,
    'y': position.dy,
    'dark': dark,
    'items': [
      for (final (index, entry) in entries.indexed)
        switch (entry) {
          NativeMenuSeparator() => {'separator': true},
          NativeMenuItem() => {
            'id': index + 1,
            // A single & marks the next letter as the item's access key.
            'label': entry.label.replaceAll('&', '&&'),
            'enabled': entry.onSelected != null,
            'ctrlKey': ?entry.ctrlKey,
          },
        },
    ],
  };

  /// Runs the `onSelected` of the entry the channel answered with, if any.
  static bool dispatch(List<NativeMenuEntry> entries, Object? chosen) {
    if (chosen is! int || chosen < 1 || chosen > entries.length) return false;
    final entry = entries[chosen - 1];
    if (entry is! NativeMenuItem || entry.onSelected == null) return false;
    entry.onSelected!();
    return true;
  }

  /// Opens [entries] at [globalPosition], in logical pixels of [context]'s
  /// view, and runs the chosen item. The menu follows the app's brightness.
  static Future<bool> show(
    BuildContext context,
    List<NativeMenuEntry> entries, {
    required Offset globalPosition,
  }) async {
    final arguments = encode(
      entries,
      position: globalPosition * View.of(context).devicePixelRatio,
      dark: Theme.of(context).brightness == Brightness.dark,
    );
    final chosen = await channel.invokeMethod<int>('show', arguments);
    return dispatch(entries, chosen);
  }
}
