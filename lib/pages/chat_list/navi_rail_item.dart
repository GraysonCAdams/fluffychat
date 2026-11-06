// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:badges/badges.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../config/themes.dart';

class NaviRailItem extends StatelessWidget {
  final String toolTip;
  final bool isSelected;
  final void Function() onTap;
  final Widget icon;
  final Widget? selectedIcon;
  final bool Function(Room)? unreadBadgeFilter;

  const NaviRailItem({
    required this.toolTip,
    required this.isSelected,
    required this.onTap,
    required this.icon,
    this.selectedIcon,
    this.unreadBadgeFilter,
    super.key,
  });
  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final borderRadius = BorderRadius.circular(AppConfig.borderRadius);
    final indicatorWidth = isSelected
        ? FluffyThemes.isColumnMode(context)
              ? 8.0
              : 4.0
        : 0.0;
    final icon = isSelected ? selectedIcon ?? this.icon : this.icon;
    final unreadBadgeFilter = this.unreadBadgeFilter;
    return HoverBuilder(
      builder: (context, hovered) {
        return SizedBox(
          height: 64,
          width: FluffyThemes.navRailWidth,
          child: Stack(
            children: [
              // A full pill twice the indicator's width with its left half
              // clipped off by the Stack. Impeller caps a corner radius at
              // half the box width, so rounding only the right corners of a
              // narrow bar leaves its left half square at both ends.
              AnimatedPositioned(
                top: 8,
                bottom: 8,
                left: -indicatorWidth,
                duration: FluffyThemes.animationDuration,
                curve: FluffyThemes.animationCurve,
                child: AnimatedContainer(
                  width: indicatorWidth * 2,
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  decoration: BoxDecoration(
                    color: theme.colorScheme.primary,
                    borderRadius: BorderRadius.circular(indicatorWidth),
                  ),
                ),
              ),
              Center(
                child: AnimatedScale(
                  scale: hovered ? 1.1 : 1.0,
                  duration: FluffyThemes.animationDuration,
                  curve: FluffyThemes.animationCurve,
                  child: Material(
                    borderRadius: borderRadius,
                    color: isSelected
                        ? theme.colorScheme.secondaryContainer
                        : theme.colorScheme.surfaceContainerHighest,
                    child: Tooltip(
                      message: toolTip,
                      child: InkWell(
                        borderRadius: borderRadius,
                        onTap: onTap,
                        child: unreadBadgeFilter == null
                            ? icon
                            : UnreadRoomsBadge(
                                filter: unreadBadgeFilter,
                                badgePosition: BadgePosition.topEnd(
                                  top: -12,
                                  end: -8,
                                ),
                                child: icon,
                              ),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
