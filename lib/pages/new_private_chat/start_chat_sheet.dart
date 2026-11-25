// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/bridge_directory.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The network the user picked in [StartChatSheet], with what that bridge
/// resolved the person to.
class StartChatChoice {
  final BridgeInfo bridge;
  final String identifier;
  final BridgeUser resolved;

  const StartChatChoice(this.bridge, this.identifier, this.resolved);
}

/// Asks which of [client]'s networks to start a chat with [person] on, in
/// a [StartChatSheet]. Null when the user closes the sheet or [client] has
/// no bridges to ask.
Future<StartChatChoice?> pickStartChatNetwork(
  BuildContext context,
  Client client,
  NewChatPerson person,
) async {
  final directory = BridgeDirectory.forClient(client);
  if (directory == null) return null;
  final bridges = await directory.bridges();
  if (!context.mounted) return null;
  return showAdaptiveBottomSheet<StartChatChoice>(
    context: context,
    builder: (_) => StartChatSheet(
      person: person,
      bridges: bridges,
      resolve: directory.api.resolveIdentifier,
    ),
  );
}

/// A bottom sheet listing the user's networks for [person], one row each,
/// iMessage first and then Google Messages. Each network is asked whether
/// it can reach the person (`resolve_identifier`, which starts nothing);
/// the ones that can are tappable and pop a [StartChatChoice].
class StartChatSheet extends StatefulWidget {
  final NewChatPerson person;
  final List<BridgeInfo> bridges;

  /// Resolves an identifier on a bridge; null when the bridge does not know
  /// it.
  final Future<BridgeUser?> Function(BridgeInfo bridge, String identifier)
  resolve;

  const StartChatSheet({
    required this.person,
    required this.bridges,
    required this.resolve,
    super.key,
  });

  @override
  State<StartChatSheet> createState() => _StartChatSheetState();
}

class _StartChatSheetState extends State<StartChatSheet> {
  late final List<BridgeInfo> _bridges;

  /// Each bridge's answer: absent while asking, null when it cannot reach
  /// the person.
  final Map<String, BridgeUser?> _resolved = {};

  @override
  void initState() {
    super.initState();
    _bridges = [
      for (final bridge in orderBridgesForPicker(widget.bridges))
        if (identifierForBridge(widget.person, bridge) != null) bridge,
    ];
    for (final bridge in _bridges) {
      _resolve(bridge);
    }
  }

  Future<void> _resolve(BridgeInfo bridge) async {
    BridgeUser? user;
    try {
      user = await widget.resolve(
        bridge,
        identifierForBridge(widget.person, bridge)!,
      );
    } catch (_) {
      user = null;
    }
    if (mounted) setState(() => _resolved[bridge.name] = user);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final unreachable = _bridges.every(
      (bridge) =>
          _resolved.containsKey(bridge.name) && _resolved[bridge.name] == null,
    );
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          ListTile(
            title: Text(
              widget.person.name,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.titleMedium,
            ),
            subtitle: Text(l10n.startChatOn),
          ),
          for (final bridge in _bridges)
            Builder(
              builder: (context) {
                final asked = _resolved.containsKey(bridge.name);
                final user = _resolved[bridge.name];
                return ListTile(
                  enabled: user != null,
                  leading: Avatar(
                    mxContent: bridge.icon,
                    name: bridge.displayName,
                    size: 32,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  title: Text(bridge.displayName),
                  subtitle: asked && user == null
                      ? Text(l10n.notOnThisNetwork)
                      : null,
                  trailing: asked
                      ? null
                      : const SizedBox.square(
                          dimension: 20,
                          child: CircularProgressIndicator.adaptive(
                            strokeWidth: 2,
                          ),
                        ),
                  onTap: user == null
                      ? null
                      : () => Navigator.of(context).pop(
                          StartChatChoice(
                            bridge,
                            identifierForBridge(widget.person, bridge)!,
                            user,
                          ),
                        ),
                );
              },
            ),
          if (unreachable)
            Padding(
              padding: const EdgeInsets.all(16),
              child: Text(
                l10n.noNetworkCanReach,
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ),
          const SizedBox(height: 8),
        ],
      ),
    );
  }
}
