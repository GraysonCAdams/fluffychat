// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:material_ui/material_ui.dart';

/// A recovery key as its groups of four characters, in a grid of tiles in
/// a monospace face, so it can be read out or copied by hand.
///
/// For the check step, [hidden] shows every group as dots and [asked]
/// puts [askedChild] (the field to type the group into) in its place.
class RecoveryKeyGrid extends StatelessWidget {
  final List<String> groups;
  final bool hidden;
  final int? asked;
  final Widget? askedChild;

  const RecoveryKeyGrid({
    required this.groups,
    this.hidden = false,
    this.asked,
    this.askedChild,
    super.key,
  });

  /// A monospace face the platform has: Consolas on Windows, Menlo on
  /// Apple platforms, and the generic monospace elsewhere.
  static TextStyle monospace({double fontSize = 19, double? height}) =>
      TextStyle(
        fontFamily: PlatformInfos.isWindows
            ? 'Consolas'
            : PlatformInfos.isMacOS || PlatformInfos.isIOS
            ? 'Menlo'
            : 'monospace',
        fontSize: fontSize,
        height: height,
      );

  /// The groups of [recoveryKey]: as spaced, or in fours if unspaced.
  static List<String> groupsOf(String recoveryKey) {
    final spaced = recoveryKey.trim().split(RegExp(r'\s+'));
    if (spaced.length > 1) return spaced;
    final key = spaced.single;
    return [
      for (var i = 0; i < key.length; i += 4)
        key.substring(i, i + 4 > key.length ? key.length : i + 4),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final style = monospace().copyWith(
      letterSpacing: 1,
      color: colorScheme.onSurface,
    );
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Wrap(
        alignment: WrapAlignment.center,
        spacing: 8,
        runSpacing: 10,
        children: [
          for (var i = 0; i < groups.length; i++)
            SizedBox(
              width: 82,
              height: 44,
              child: i == asked && askedChild != null
                  ? askedChild
                  : Container(
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: colorScheme.surface,
                        borderRadius: BorderRadius.circular(10),
                      ),
                      child: hidden
                          ? Text('••••', style: style)
                          : SelectableText(groups[i], style: style),
                    ),
            ),
        ],
      ),
    );
  }
}
