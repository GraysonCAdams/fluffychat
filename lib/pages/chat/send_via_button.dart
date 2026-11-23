// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/merged_network_menu.dart';
import 'package:fluffychat/utils/merged_contacts/send_router.dart';
import 'package:material_ui/material_ui.dart';

/// The send-via button at the start of the composer, before the attachment
/// button, in a merged
/// contact's chat: the icon of the network the next message goes out on. The
/// network's name is in the field's hint, so the button carries no label.
///
/// Tapping lists the contact's networks; the one picked becomes the
/// contact's network from then on ([onSetDefault]) and [onPick] switches the
/// composer to it. While [target] is locked (replying,
/// editing, in a thread) the button shows the network of the message being
/// answered with a lock and cannot be changed, so it is clear the answer does
/// not use the default.
class SendViaButton extends StatelessWidget {
  final List<MergedNetwork> networks;
  final SendTarget target;
  final String defaultRoomId;
  final void Function(String roomId) onPick;
  final void Function(String roomId) onSetDefault;

  /// Shows a warning on the button: the target network is not encrypted while
  /// another network of the contact is.
  final bool unencryptedWarning;

  const SendViaButton({
    required this.networks,
    required this.target,
    required this.defaultRoomId,
    required this.onPick,
    required this.onSetDefault,
    this.unencryptedWarning = false,
    super.key,
  });

  Future<void> _choose(BuildContext context) async {
    final picked = await showMergedNetworkMenu(
      context,
      networks: networks,
      selectedRoomId: target.roomId,
      defaultRoomId: defaultRoomId,
    );
    if (picked == null) return;
    // Picking is remembered for the contact, whether or not a message
    // follows.
    onSetDefault(picked);
    if (picked != target.roomId) onPick(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final network = networks.firstWhere(
      (n) => n.room.id == target.roomId,
      orElse: () => networks.first,
    );
    final locked = target.locked;
    final tooltip = locked
        ? l10n.replySendsVia(network.name)
        : unencryptedWarning
        ? l10n.sendViaUnencryptedWarning(network.name)
        : l10n.sendVia(network.name);
    final badge = locked
        ? Icons.lock
        : unencryptedWarning
        ? Icons.no_encryption
        : null;
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: !locked,
        enabled: !locked,
        label: tooltip,
        excludeSemantics: true,
        child: InkResponse(
          key: const Key('send_via_button'),
          radius: 20,
          onTap: locked ? null : () => _choose(context),
          child: SizedBox.square(
            dimension: 40,
            child: Stack(
              alignment: Alignment.center,
              children: [
                network.icon(size: 24),
                if (badge != null)
                  Positioned(
                    right: 3,
                    bottom: 3,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surfaceContainerHigh,
                        shape: BoxShape.circle,
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(1.5),
                        child: Icon(
                          badge,
                          size: 11,
                          color: locked
                              ? theme.colorScheme.onSurfaceVariant
                              : theme.colorScheme.error,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
