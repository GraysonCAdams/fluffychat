// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';

/// One button of a [NetworkToggleGroup]: a network, drawn with its logo.
class NetworkToggle {
  final String id;
  final String name;
  final Uri? avatar;

  /// Whether the network can be picked. A disabled one is drawn faded.
  final bool enabled;

  const NetworkToggle({
    required this.id,
    required this.name,
    required this.avatar,
    this.enabled = true,
  });
}

/// A person's networks as a Material connected button group of toggle
/// icon buttons: extra-small buttons (32 high, 20 icon) 2 apart, the
/// group's outer corners fully round and its inner corners 8. The selected
/// button takes the brighter fill. [trailing], such as a
/// [DashedAddSegment], is the group's last segment.
///
/// The chat's app bar shows the merged contact's networks with it, and the
/// compose screen the networks of the person in its To field.
class NetworkToggleGroup extends StatelessWidget {
  final List<NetworkToggle> networks;
  final String? selectedId;

  /// Called with a network's [NetworkToggle.id] when it is tapped. Null
  /// leaves every button unresponsive.
  final void Function(String id)? onSelect;
  final Widget? trailing;
  final double height;
  final double width;
  final double iconSize;

  const NetworkToggleGroup({
    required this.networks,
    required this.selectedId,
    required this.onSelect,
    this.trailing,
    this.height = defaultHeight,
    this.width = defaultWidth,
    this.iconSize = 20,
    super.key,
  });

  static const defaultHeight = 32.0;
  static const defaultWidth = 40.0;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final trailing = this.trailing;
    return Row(
      mainAxisSize: MainAxisSize.min,
      spacing: 2,
      children: [
        for (final (index, network) in networks.indexed)
          _button(
            theme,
            network,
            first: index == 0,
            last: trailing == null && index == networks.length - 1,
          ),
        ?trailing,
      ],
    );
  }

  Widget _button(
    ThemeData theme,
    NetworkToggle network, {
    required bool first,
    required bool last,
  }) {
    final outer = Radius.circular(height / 2);
    const inner = Radius.circular(8);
    final radius = BorderRadius.horizontal(
      left: first ? outer : inner,
      right: last ? outer : inner,
    );
    final selected = network.id == selectedId;
    final onSelect = this.onSelect;
    return Tooltip(
      message: network.name,
      child: AnimatedContainer(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        height: height,
        width: width,
        decoration: BoxDecoration(
          // Quieter than the spec's selected tonal color, which outshines
          // a network's own logo.
          color: selected
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHigh,
          borderRadius: radius,
        ),
        clipBehavior: Clip.antiAlias,
        child: Material(
          type: MaterialType.transparency,
          child: InkWell(
            onTap: onSelect != null && !selected && network.enabled
                ? () => onSelect(network.id)
                : null,
            child: Center(
              child: Opacity(
                opacity: network.enabled ? 1 : 0.38,
                child: Avatar(
                  mxContent: network.avatar,
                  name: network.name,
                  size: iconSize,
                  borderRadius: BorderRadius.circular(iconSize / 4),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The closing segment of a [NetworkToggleGroup]: a dashed plus, a small
/// corner towards the networks and fully round on the outside.
class DashedAddSegment extends StatelessWidget {
  final String tooltip;
  final void Function() onTap;
  final double width;
  final double height;

  const DashedAddSegment({
    required this.tooltip,
    required this.onTap,
    required this.width,
    required this.height,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final radius = BorderRadius.horizontal(
      left: const Radius.circular(8),
      right: Radius.circular(height / 2),
    );
    return Tooltip(
      message: tooltip,
      child: InkWell(
        borderRadius: radius,
        onTap: onTap,
        child: CustomPaint(
          painter: _DashedBorderPainter(
            color: theme.colorScheme.outline,
            radius: radius,
          ),
          child: SizedBox(
            width: width,
            height: height,
            child: Icon(
              Icons.add,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }
}

/// A dashed rounded outline, to set an action apart from the filled network
/// buttons beside it.
class _DashedBorderPainter extends CustomPainter {
  final Color color;
  final BorderRadius radius;

  const _DashedBorderPainter({required this.color, required this.radius});

  static const double _dash = 4;
  static const double _gap = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2;
    final outline = Path()
      ..addRRect(radius.toRRect((Offset.zero & size).deflate(0.6)));
    for (final metric in outline.computeMetrics()) {
      for (var at = 0.0; at < metric.length; at += _dash + _gap) {
        canvas.drawPath(metric.extractPath(at, at + _dash), paint);
      }
    }
  }

  @override
  bool shouldRepaint(_DashedBorderPainter old) =>
      old.color != color || old.radius != radius;
}
