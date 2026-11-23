// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/merged_network_menu.dart';
import 'package:fluffychat/utils/merged_contacts/send_router.dart';
import 'package:material_ui/material_ui.dart';

/// The send-via chip left of the composer's text field in a merged
/// contact's chat: the network the next message goes out on.
///
/// Tapping lists the contact's networks and [onPick] switches to the one
/// picked for this message; long pressing does the same and [onSetDefault]
/// also makes it the contact's default. While [target] is locked (replying,
/// editing, in a thread) the chip shows the network of the message being
/// answered and cannot be changed, so it is clear the answer does not use
/// the default.
class SendViaChip extends StatelessWidget {
  final List<MergedNetwork> networks;
  final SendTarget target;
  final String defaultRoomId;
  final void Function(String roomId) onPick;
  final void Function(String roomId) onSetDefault;

  /// Shows a warning on the chip: the target network is not encrypted while
  /// another network of the contact is.
  final bool unencryptedWarning;

  const SendViaChip({
    required this.networks,
    required this.target,
    required this.defaultRoomId,
    required this.onPick,
    required this.onSetDefault,
    this.unencryptedWarning = false,
    super.key,
  });

  Future<void> _choose(BuildContext context, {required bool setDefault}) async {
    final picked = await showMergedNetworkMenu(
      context,
      networks: networks,
      selectedRoomId: target.roomId,
      defaultRoomId: defaultRoomId,
    );
    if (picked == null) return;
    if (setDefault) onSetDefault(picked);
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
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: !locked,
        enabled: !locked,
        label: tooltip,
        excludeSemantics: true,
        child: Material(
          color: locked
              ? theme.colorScheme.surfaceContainerHighest
              : theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            key: const Key('send_via_chip'),
            borderRadius: BorderRadius.circular(16),
            onTap: locked ? null : () => _choose(context, setDefault: false),
            onLongPress: locked
                ? null
                : () => _choose(context, setDefault: true),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(4, 4, 8, 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                spacing: 4,
                children: [
                  network.icon(size: 20),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 88),
                    child: Text(
                      network.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: locked
                            ? theme.colorScheme.onSurfaceVariant
                            : theme.colorScheme.onSecondaryContainer,
                      ),
                    ),
                  ),
                  if (locked)
                    Icon(
                      Icons.lock_outline,
                      size: 14,
                      color: theme.colorScheme.onSurfaceVariant,
                    )
                  else if (unencryptedWarning)
                    Icon(
                      Icons.no_encryption_outlined,
                      size: 14,
                      color: theme.colorScheme.error,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
