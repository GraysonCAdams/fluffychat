// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

class DummyChatListItem extends StatelessWidget {
  final double opacity;
  final bool animate;

  const DummyChatListItem({
    required this.opacity,
    required this.animate,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final textColor = theme.textTheme.bodyLarge!.color!;
    // The fade is applied to each colour instead of through an Opacity over
    // the whole tile, which would composite the tile in its own layer. The
    // shapes do not overlap, so the result is the same.
    final titleColor = textColor.withValues(alpha: 100 / 255 * opacity);
    final subtitleColor = textColor.withValues(alpha: 50 / 255 * opacity);
    return ListTile(
      leading: animate
          // The spinner is drawn over the circle, and fading the two as one
          // group differs from fading each, so this part keeps its layer.
          ? Opacity(
              opacity: opacity,
              child: CircleAvatar(
                backgroundColor: textColor.withAlpha(100),
                child: CircularProgressIndicator(
                  strokeWidth: 1,
                  color: textColor,
                ),
              ),
            )
          : CircleAvatar(
              backgroundColor: titleColor,
              child: const SizedBox.shrink(),
            ),
      title: Row(
        children: [
          Expanded(
            child: Container(
              height: 14,
              decoration: BoxDecoration(
                color: titleColor,
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),
          const SizedBox(width: 36),
          Container(
            height: 14,
            width: 14,
            decoration: BoxDecoration(
              color: subtitleColor,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
          const SizedBox(width: 12),
          Container(
            height: 14,
            width: 14,
            decoration: BoxDecoration(
              color: subtitleColor,
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ],
      ),
      subtitle: Container(
        decoration: BoxDecoration(
          color: subtitleColor,
          borderRadius: BorderRadius.circular(3),
        ),
        height: 12,
        margin: const EdgeInsets.only(right: 22),
      ),
    );
  }
}
