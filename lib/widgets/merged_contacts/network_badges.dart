// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The network badges of a merged contact for the corner of its avatar: up
/// to two network (space) avatars overlapping each other, and a "+N" pill
/// when there are more. Each badge is outlined in [outlineColor], the color
/// behind the avatar, so the badges read as separate from it and from each
/// other.
///
/// A single network looks exactly like the one badge an ordinary chat tile
/// shows, so merging does not change how a chat's corner looks until it
/// spans networks.
class NetworkBadges extends StatelessWidget {
  /// The contact's networks in room order. Rooms outside any space are null
  /// and get no badge; a network shared by two rooms gets one.
  final List<Room?> networks;
  final double size;
  final Color outlineColor;
  final void Function()? onTap;

  static const int maxBadges = 2;

  const NetworkBadges({
    required this.networks,
    required this.size,
    required this.outlineColor,
    this.onTap,
    super.key,
  });

  /// The distinct networks, in order.
  List<Room> get distinct {
    final seen = <String>{};
    return [
      for (final network in networks)
        if (network != null && seen.add(network.id)) network,
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final shown = distinct;
    if (shown.isEmpty) return const SizedBox.shrink();
    final badges = shown.take(maxBadges).toList();
    final extra = shown.length - badges.length;
    // Each further badge is shifted left by most of a badge, so the newest
    // badge on the right still shows whole.
    final step = size * 0.62;
    final width =
        size + step * (badges.length - 1) + (extra > 0 ? size * 0.7 : 0);
    final radius = BorderRadius.circular(AppConfig.spaceBorderRadius * 0.5);
    return SizedBox(
      width: width,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (var i = badges.length - 1; i >= 0; i--)
            Positioned(
              right: step * i + (extra > 0 ? size * 0.7 : 0),
              top: 0,
              child: Avatar(
                shapeBorder: RoundedSuperellipseBorder(
                  side: BorderSide(width: 2, color: outlineColor),
                  borderRadius: radius,
                ),
                borderRadius: radius,
                mxContent: badges[i].avatar,
                size: size,
                name: badges[i].getLocalizedDisplayname(),
                onTap: onTap,
              ),
            ),
          if (extra > 0)
            Positioned(
              right: 0,
              top: size * 0.1,
              child: Container(
                height: size * 0.8,
                constraints: BoxConstraints(minWidth: size * 0.8),
                alignment: Alignment.center,
                padding: const EdgeInsets.symmetric(horizontal: 3),
                decoration: BoxDecoration(
                  color: theme.colorScheme.secondaryContainer,
                  borderRadius: BorderRadius.circular(size),
                  border: Border.all(color: outlineColor, width: 2),
                ),
                child: Text(
                  '+$extra',
                  style: TextStyle(
                    fontSize: size * 0.38,
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSecondaryContainer,
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
