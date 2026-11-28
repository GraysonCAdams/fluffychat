// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// The server being signed in to, on the steps after the server step.
/// Its edit icon goes back to change it.
class ServerChip extends StatelessWidget {
  final String server;
  final VoidCallback? onChange;

  const ServerChip({required this.server, this.onChange, super.key});

  @override
  Widget build(BuildContext context) => Align(
    alignment: AlignmentDirectional.centerStart,
    child: InputChip(
      avatar: Icon(
        Icons.hub_outlined,
        size: 18,
        color: Theme.of(context).colorScheme.primary,
      ),
      label: Text(server),
      deleteIcon: const Icon(Icons.edit_outlined, size: 18),
      deleteButtonTooltipMessage: L10n.of(context).changeServer,
      onDeleted: onChange ?? () => Navigator.of(context).maybePop(),
      onPressed: onChange ?? () => Navigator.of(context).maybePop(),
    ),
  );
}
