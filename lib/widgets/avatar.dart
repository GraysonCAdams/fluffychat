// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:fluffychat/widgets/presence_builder.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class Avatar extends StatelessWidget {
  final Uri? mxContent;
  final String? name;
  final double size;
  final void Function()? onTap;
  static const double defaultSize = 48;
  final Client? client;
  final String? presenceUserId;
  final Color? presenceBackgroundColor;
  final BorderRadius? borderRadius;
  final IconData? icon;
  final ShapeBorder? shapeBorder;
  final Color? backgroundColor;
  final Color? textColor;
  final bool animated;

  const Avatar({
    this.mxContent,
    this.name,
    this.size = defaultSize,
    this.onTap,
    this.client,
    this.presenceUserId,
    this.presenceBackgroundColor,
    this.borderRadius,
    this.shapeBorder,
    this.icon,
    this.backgroundColor,
    this.textColor,
    this.animated = false,
    super.key,
  });

  static final _phoneCharacters = RegExp(r'^\+?[\d\s().\-]+$');
  static final _parenthesized = RegExp(r'\([^)]*\)?');

  /// The initials shown for [rawName] when there is no picture. Also used
  /// for Windows notification images.
  static String calcFallbackLetters(String? rawName) {
    final name = rawName?.replaceAll(_parenthesized, ' ').trim();
    if (name == null || name.isEmpty) return '@';
    final words = name.split(' ').where((word) => word.isNotEmpty).toList();
    if (words.length <= 1) return name.characters.first;
    return '${words.first.characters.first}${words.last.characters.first}';
  }

  /// Bridged SMS chats are often named after a bare number: a short code
  /// (a business sender) or the phone number of an unsaved contact. Initials
  /// of digits say nothing, so those get an icon instead.
  static IconData? numberIcon(String? rawName) {
    final name = rawName?.trim();
    if (name == null || !_phoneCharacters.hasMatch(name)) return null;
    final digits = name.replaceAll(RegExp(r'\D'), '').length;
    if (!name.startsWith('+') && digits >= 3 && digits <= 6) {
      return Icons.storefront_outlined;
    }
    if (digits >= 7) return Icons.person_outline;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final fallbackLetters = calcFallbackLetters(name);
    final numberIcon = icon == null ? Avatar.numberIcon(name) : null;

    final noPic =
        mxContent == null ||
        mxContent.toString().isEmpty ||
        mxContent.toString() == 'null';
    final borderRadius = this.borderRadius ?? BorderRadius.circular(size / 2);
    // Online dots only mean something between Matrix users.
    final presenceUserId =
        this.presenceUserId != null &&
            MatrixFeatures.forClient(
              client ?? Matrix.of(context).client,
            ).isRelevant(MatrixFeature.status)
        ? this.presenceUserId
        : null;
    final shape =
        shapeBorder ??
        RoundedSuperellipseBorder(
          borderRadius: borderRadius,
          side: BorderSide.none,
        );
    final container = Stack(
      children: [
        SizedBox(
          width: size,
          height: size,
          // Only the border is painted outside the clip. A fill under the
          // clipped picture would have an anti-aliased edge of its own on
          // the same path, and the two partly covered edge pixels let it
          // show through as a dark (or light) fringe around the avatar.
          child: Material(
            type: MaterialType.transparency,
            shape: shape,
            // The picture reaches the middle of the border, so both edges of
            // the border lie over opaque paint: clipped to the outer path
            // the picture would show through the border's outer edge, and
            // clipped to the inner path the background would show between
            // the picture and the border.
            child: ClipPath(
              clipper: _InnerShapeClipper(
                _halfBorder(shape),
                Directionality.of(context),
              ),
              // Without a picture there is nothing to load or fade to:
              // MxcImage would only cross-fade from this same placeholder to
              // itself, so the placeholder is shown on its own.
              child: noPic
                  ? Container(
                      decoration: BoxDecoration(
                        color:
                            backgroundColor ??
                            fallbackLetters.avatarColors.fill,
                      ),
                      alignment: Alignment.center,
                      child: numberIcon != null
                          ? Icon(
                              numberIcon,
                              color:
                                  textColor ??
                                  fallbackLetters.avatarColors.onFill,
                              size: (size / 2).roundToDouble(),
                            )
                          // The initials only stand for the name, which a
                          // screen reader hears from the row or button the
                          // avatar sits in.
                          : Text(
                              fallbackLetters,
                              semanticsLabel: '',
                              textAlign: TextAlign.center,
                              // The theme's font, as everywhere else.
                              style: TextStyle(
                                color:
                                    textColor ??
                                    fallbackLetters.avatarColors.onFill,
                                fontWeight: FontWeight.bold,
                                fontSize: (size / 2.5).roundToDouble(),
                              ),
                            ),
                    )
                  // Behind a picture with transparent parts, and the
                  // placeholder. The ClipPath above is the only clip: a
                  // second one on the picture's own edge would let this
                  // backdrop show through it.
                  : ColoredBox(
                      color: theme.brightness == Brightness.light
                          ? Colors.white
                          : Colors.black,
                      child: MxcImage(
                        client: client,
                        key: ValueKey(mxContent.toString()),
                        cacheKey:
                            '${mxContent}_${size}_${animated ? 'animated' : 'static'}',
                        uri: mxContent,
                        isThumbnail: !animated,
                        animated: animated,
                        fit: BoxFit.cover,
                        width: size,
                        height: size,
                        placeholder: (_) => Center(
                          child: Icon(
                            Icons.person_2,
                            color: theme.colorScheme.tertiary,
                            size: size / 1.5,
                          ),
                        ),
                      ),
                    ),
            ),
          ),
        ),
        if (presenceUserId != null)
          PresenceBuilder(
            client: client,
            userId: presenceUserId,
            builder: (context, presence) {
              if (presence == null ||
                  (presence.presence == PresenceType.offline &&
                      presence.lastActiveTimestamp == null)) {
                return const SizedBox.shrink();
              }
              final dotColor = presence.presence.isOnline
                  ? Colors.green
                  : presence.presence.isUnavailable
                  ? Colors.orange
                  : Colors.grey;
              return Positioned(
                bottom: -3,
                right: -3,
                child: Container(
                  width: 16,
                  height: 16,
                  decoration: BoxDecoration(
                    color: presenceBackgroundColor ?? theme.colorScheme.surface,
                    borderRadius: BorderRadius.circular(32),
                  ),
                  alignment: Alignment.center,
                  child: Container(
                    width: 10,
                    height: 10,
                    decoration: BoxDecoration(
                      color: dotColor,
                      borderRadius: BorderRadius.circular(16),
                      border: Border.all(
                        width: 1,
                        color: theme.colorScheme.surface,
                      ),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
    if (onTap == null) return container;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: container),
    );
  }
}

/// [shape] with its border half as wide, whose inner path runs along the
/// middle of [shape]'s border. Shapes other than an [OutlinedBorder] are
/// returned as they are.
ShapeBorder _halfBorder(ShapeBorder shape) => shape is OutlinedBorder
    ? shape.copyWith(side: shape.side.copyWith(width: shape.side.width / 2))
    : shape;

class _InnerShapeClipper extends CustomClipper<Path> {
  final ShapeBorder shape;
  final TextDirection textDirection;

  const _InnerShapeClipper(this.shape, this.textDirection);

  @override
  Path getClip(Size size) =>
      shape.getInnerPath(Offset.zero & size, textDirection: textDirection);

  @override
  bool shouldReclip(_InnerShapeClipper oldClipper) =>
      oldClipper.shape != shape || oldClipper.textDirection != textDirection;
}
