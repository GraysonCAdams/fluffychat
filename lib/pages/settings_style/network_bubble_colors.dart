// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/settings_switch_list_tile.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The style settings for bubble colours by network: a switch between one
/// colour per network and the theme's single colour, and a colour picker for
/// each bridged network the account has direct chats on.
class NetworkBubbleColors extends StatefulWidget {
  final Client client;

  const NetworkBubbleColors({required this.client, super.key});

  @override
  State<NetworkBubbleColors> createState() => _NetworkBubbleColorsState();
}

class _NetworkBubbleColorsState extends State<NetworkBubbleColors> {
  static const _swatchSize = 32.0;

  /// Bridge ID to (name, space) for each network with a direct chat.
  Map<String, (String, Room?)> _networks(MatrixLocals locals) {
    final spaces = spacesByChild(widget.client);
    final networks = <String, (String, Room?)>{};
    for (final room in widget.client.rooms) {
      if (room.isSpace || !room.isDirectChat) continue;
      final bridgeId = NetworkColors.bridgeIdOf(room);
      if (bridgeId == null || networks.containsKey(bridgeId)) continue;
      final space = spaces[room.id];
      networks[bridgeId] = (networkName(room, space, locals), space);
    }
    return networks;
  }

  Widget _swatch(String bridgeId, Color? color, {required bool selected}) {
    final theme = Theme.of(context);
    final shown = color ?? NetworkColors.defaults[bridgeId];
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 8),
      child: Tooltip(
        message: color == null ? L10n.of(context).networkDefaultColor : '',
        child: InkWell(
          borderRadius: BorderRadius.circular(_swatchSize),
          onTap: () async {
            await NetworkColors.pick(bridgeId, color);
            if (mounted) setState(() {});
          },
          child: Material(
            color: shown ?? theme.colorScheme.surfaceContainerHighest,
            elevation: 3,
            shape: CircleBorder(
              side: color == null
                  ? BorderSide(color: theme.colorScheme.outline, width: 2)
                  : BorderSide.none,
            ),
            child: SizedBox.square(
              dimension: _swatchSize,
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 16,
                      // Black or white, whichever reads on the swatch.
                      color: shown == null
                          ? theme.colorScheme.onSurface
                          : ThemeData.estimateBrightnessForColor(shown) ==
                                Brightness.dark
                          ? Colors.white
                          : Colors.black,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final networks = _networks(MatrixLocals(l10n));
    if (networks.isEmpty) return const SizedBox.shrink();
    final perNetwork = AppSettings.networkBubbleColors.value;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Divider(color: theme.dividerColor),
        ListTile(
          title: Text(
            l10n.networkBubbleColorsTitle,
            style: TextStyle(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        SettingsSwitchListTile.adaptive(
          title: l10n.networkBubbleColors,
          subtitle: l10n.networkBubbleColorsDescription,
          setting: AppSettings.networkBubbleColors,
          onChanged: (_) => setState(() {}),
        ),
        if (perNetwork)
          for (final MapEntry(key: bridgeId, value: (name, space))
              in networks.entries) ...[
            ListTile(
              dense: true,
              leading: Avatar(
                mxContent: space?.avatar,
                name: name,
                size: 28,
                borderRadius: BorderRadius.circular(7),
              ),
              title: Text(name),
            ),
            SizedBox(
              height: _swatchSize + 16,
              child: ListView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 10),
                children: [
                  _swatch(
                    bridgeId,
                    null,
                    selected: NetworkColors.pickedFor(bridgeId) == null,
                  ),
                  for (final color in Colors.primaries)
                    _swatch(
                      bridgeId,
                      Color(color.toARGB32()),
                      selected:
                          NetworkColors.pickedFor(bridgeId)?.toARGB32() ==
                          color.toARGB32(),
                    ),
                ],
              ),
            ),
          ],
      ],
    );
  }
}
