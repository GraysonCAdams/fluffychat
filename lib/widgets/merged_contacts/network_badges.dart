// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:flutter/foundation.dart';
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
  List<Room> get distinct => distinctOf(networks);

  /// [networks] without nulls and repeats, in order.
  static List<Room> distinctOf(List<Room?> networks) {
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

/// The networks a chat is on as a row of small icons with their colour
/// taken out, for the trailing edge of a list row where the brand colours
/// would compete with the avatars.
class MonochromeNetworkIcons extends StatelessWidget {
  final List<Room> networks;
  final double size;

  const MonochromeNetworkIcons({
    required this.networks,
    this.size = 18,
    super.key,
  });

  /// Maps every colour to its luminance.
  static const _greyscale = ColorFilter.matrix(<double>[
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0.2126, 0.7152, 0.0722, 0, 0, //
    0, 0, 0, 1, 0, //
  ]);

  @override
  Widget build(BuildContext context) {
    final radius = BorderRadius.circular(size * 0.25);
    return Opacity(
      opacity: 0.6,
      child: ColorFiltered(
        colorFilter: _greyscale,
        child: Row(
          mainAxisSize: MainAxisSize.min,
          spacing: 6,
          children: [
            for (final network in networks)
              Avatar(
                borderRadius: radius,
                mxContent: network.avatar,
                size: size,
                name: network.getLocalizedDisplayname(),
              ),
          ],
        ),
      ),
    );
  }
}

/// The corner badge of a merged contact's avatar in the chat list: one
/// neutral link icon inside a ring split evenly between the contact's
/// networks, each segment in that network's bubble colour. Round, so it
/// cannot be taken for the square badge of a single network.
class MergedBadge extends StatelessWidget {
  final MergedContact contact;
  final double size;

  /// The colour behind the avatar, drawn around the badge to cut it out of
  /// the avatar.
  final Color outlineColor;
  final void Function()? onTap;

  const MergedBadge({
    required this.contact,
    required this.size,
    required this.outlineColor,
    this.onTap,
    super.key,
  });

  /// One colour per network of the contact, in room order. Networks without
  /// a known colour are left out.
  List<Color> get _ringColors {
    final seen = <String>{};
    return [
      for (final room in contact.rooms)
        if (NetworkColors.bridgeIdOf(room) case final id?)
          if (seen.add(id)) ?NetworkColors.colorFor(id),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: onTap,
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(color: outlineColor, shape: BoxShape.circle),
        padding: const EdgeInsets.all(2),
        child: CustomPaint(
          painter: _SplitRingPainter(
            colors: _ringColors,
            fill: theme.colorScheme.surfaceContainerHighest,
            gap: outlineColor,
          ),
          child: Center(
            child: Icon(
              Icons.link,
              size: size * 0.5,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// A filled disc with a ring just inside its edge, cut into equal arcs of
/// [colors] starting at the top.
class _SplitRingPainter extends CustomPainter {
  final List<Color> colors;
  final Color fill;
  final Color gap;

  const _SplitRingPainter({
    required this.colors,
    required this.fill,
    required this.gap,
  });

  static const double _ringWidth = 2;

  @override
  void paint(Canvas canvas, Size size) {
    final center = size.center(Offset.zero);
    final radius = size.shortestSide / 2;
    canvas.drawCircle(center, radius, Paint()..color = fill);
    if (colors.isEmpty) return;
    final ring = Rect.fromCircle(
      center: center,
      radius: radius - _ringWidth / 2,
    );
    final paint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = _ringWidth;
    final sweep = 2 * math.pi / colors.length;
    for (var i = 0; i < colors.length; i++) {
      canvas.drawArc(
        ring,
        -math.pi / 2 + sweep * i,
        sweep,
        false,
        paint..color = colors[i],
      );
    }
  }

  @override
  bool shouldRepaint(_SplitRingPainter old) =>
      !listEquals(old.colors, colors) || old.fill != fill || old.gap != gap;
}
