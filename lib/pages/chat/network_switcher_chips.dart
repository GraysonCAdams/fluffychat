// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';

/// One network of a [NetworkSwitcherChips], drawn with its logo.
class NetworkSwitcherOption {
  /// What [NetworkSwitcherChips.onPick] is called with, such as the room the
  /// message goes to on this network.
  final String id;
  final String name;
  final Uri? avatar;

  /// Why the network cannot be picked, as its tooltip; null when it can. A
  /// network with a reason is drawn faded.
  final String? blockedReason;

  const NetworkSwitcherOption({
    required this.id,
    required this.name,
    required this.avatar,
    this.blockedReason,
  });
}

/// A row of network buttons joined into one Material connected button group
/// of toggle icon buttons: extra-small buttons (32 high, 20 icon) 2 apart,
/// the group's outer corners fully round and its inner corners 8. The
/// network of [selectedId] takes the brighter fill, and a tap on another
/// one picks it through [onPick]. Without [onPick] the buttons only show
/// the networks. A faded network does not pick; a tap on it goes to
/// [onBlockedTap]. [trailing], such as the chat's add-chat plus, is the
/// group's last segment.
///
/// The chat's app bar shows the chat's networks with it, and the compose
/// screen's header the networks of the first person in its To field.
class NetworkSwitcherChips extends StatelessWidget {
  final List<NetworkSwitcherOption> networks;
  final String? selectedId;
  final void Function(String id)? onPick;
  final void Function(NetworkSwitcherOption network)? onBlockedTap;
  final Widget? trailing;

  const NetworkSwitcherChips({
    required this.networks,
    required this.selectedId,
    required this.onPick,
    this.onBlockedTap,
    this.trailing,
    super.key,
  });

  static const height = 32.0;
  static const width = 40.0;
  static const _iconSize = 20.0;
  static const _outer = Radius.circular(height / 2);
  static const _inner = Radius.circular(8);

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
    NetworkSwitcherOption network, {
    required bool first,
    required bool last,
  }) {
    final radius = BorderRadius.horizontal(
      left: first ? _outer : _inner,
      right: last ? _outer : _inner,
    );
    final selected = network.id == selectedId;
    final blocked = network.blockedReason != null;
    final onPick = this.onPick;
    final onBlockedTap = this.onBlockedTap;
    return Tooltip(
      message: network.blockedReason ?? network.name,
      child: AnimatedContainer(
        key: ValueKey('network-${network.id}'),
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
            onTap: blocked
                ? onBlockedTap == null
                      ? null
                      : () => onBlockedTap(network)
                : onPick != null && !selected
                ? () => onPick(network.id)
                : null,
            child: Center(
              child: Opacity(
                opacity: blocked ? 0.38 : 1,
                child: Avatar(
                  mxContent: network.avatar,
                  name: network.name,
                  size: _iconSize,
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
