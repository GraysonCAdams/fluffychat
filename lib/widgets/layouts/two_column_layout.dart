// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:material_ui/material_ui.dart';

/// The column-mode layout: [mainView] (the rail and chat list, or settings)
/// on the base surface, and [sideView] as a floating card on
/// surfaceContainerLow, inset from the right and bottom window edges.
class TwoColumnLayout extends StatelessWidget {
  /// Gap between the card and the right and bottom window edges.
  static const double cardInset = 8.0;
  static const double cardRadius = 16.0;

  final Widget mainView;
  final Widget sideView;
  final bool hasNavigationRail;

  const TwoColumnLayout({
    super.key,
    required this.mainView,
    required this.sideView,
    this.hasNavigationRail = true,
  });
  @override
  Widget build(BuildContext context) {
    final cardTheme = FluffyThemes.cardPaneTheme(Theme.of(context));

    return ScaffoldMessenger(
      child: Scaffold(
        body: Row(
          children: [
            Container(
              clipBehavior: Clip.antiAlias,
              decoration: const BoxDecoration(),
              width:
                  FluffyThemes.columnWidth +
                  (hasNavigationRail ? FluffyThemes.navRailWidth : 0),
              child: mainView,
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.only(
                  right: cardInset,
                  bottom: cardInset,
                ),
                child: Theme(
                  data: cardTheme,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(cardRadius),
                    child: Material(
                      color: cardTheme.colorScheme.surface,
                      child: sideView,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
