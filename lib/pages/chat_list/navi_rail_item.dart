// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:badges/badges.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/unread_rooms_badge.dart';
import 'package:material_ui/material_ui.dart';

import '../../config/themes.dart';

class NaviRailItem extends StatelessWidget {
  final String toolTip;
  final bool isSelected;
  final void Function() onTap;
  final Widget icon;
  final Widget? selectedIcon;

  /// Unread chats to show on a badge, or null for no badge.
  final int? unreadCount;

  /// Opens the tile's menu at a global position: where a right click was,
  /// or beside the tile for a long press. Null for a tile with no menu.
  final void Function(Offset position)? onContextMenu;

  const NaviRailItem({
    required this.toolTip,
    required this.isSelected,
    required this.onTap,
    required this.icon,
    this.selectedIcon,
    this.unreadCount,
    this.onContextMenu,
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
    final unreadCount = this.unreadCount;
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
                      // A long press on a tile with a menu opens the menu,
                      // so on touch the name shows in the menu instead.
                      triggerMode: onContextMenu == null
                          ? null
                          : TooltipTriggerMode.manual,
                      child: InkWell(
                        borderRadius: borderRadius,
                        onTap: onTap,
                        onSecondaryTapUp: onContextMenu == null
                            ? null
                            : (details) =>
                                  onContextMenu!(details.globalPosition),
                        onLongPress: onContextMenu == null
                            ? null
                            : () {
                                // Beside the tile, at its right edge.
                                final box =
                                    context.findRenderObject()! as RenderBox;
                                onContextMenu!(
                                  box.localToGlobal(
                                    box.size.centerRight(Offset.zero),
                                  ),
                                );
                              },
                        child: unreadCount == null
                            ? icon
                            : UnreadRoomsBadge(
                                unreadCount: unreadCount,
                                badgePosition: BadgePosition.topEnd(
                                  top: -7,
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
