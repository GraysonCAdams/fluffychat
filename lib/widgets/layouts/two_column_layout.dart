// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat_list/title_bar_search.dart';
import 'package:material_ui/material_ui.dart';

/// The column-mode layout: [mainView] (the rail and chat list, or settings)
/// on the base surface, and [sideView] as a floating card on
/// surfaceContainerLow, inset from the right and bottom window edges. Under
/// the Windows title bar, which lies over the top of the window, the card
/// starts below the bar so its top corners stay in sight.
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
    // The Windows title bar adds its height to the top padding.
    final barHeight = TitleBarSearch.maybeOf(context) == null
        ? 0.0
        : MediaQuery.paddingOf(context).top;

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
                padding: EdgeInsets.only(
                  top: barHeight,
                  right: cardInset,
                  bottom: cardInset,
                ),
                child: Theme(
                  data: cardTheme,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(cardRadius),
                    child: Material(
                      color: cardTheme.colorScheme.surface,
                      // The card already starts below the bar.
                      child: MediaQuery.removePadding(
                        context: context,
                        removeTop: barHeight > 0,
                        child: sideView,
                      ),
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
