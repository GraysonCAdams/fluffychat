// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

/// The row in chat settings for the networks taken off the chat list's
/// rail with Hide from rail: their names, and a sheet that puts each back.
/// Nothing shows while none is hidden.
class HiddenRailSpacesTile extends StatefulWidget {
  const HiddenRailSpacesTile({super.key});

  @override
  State<HiddenRailSpacesTile> createState() => _HiddenRailSpacesTileState();
}

class _HiddenRailSpacesTileState extends State<HiddenRailSpacesTile> {
  /// The name of the space [id], or the ID of one the account has left.
  String _name(String id) {
    final room = Matrix.of(context).client.getRoomById(id);
    return room?.getLocalizedDisplayname(MatrixLocals(L10n.of(context))) ?? id;
  }

  Future<void> _show(String id) async {
    await AppSettings.railHiddenSpaces.setItem(
      AppSettings.railHiddenSpaces.value
          .where((hidden) => hidden != id)
          .toList(),
    );
    if (mounted) setState(() {});
  }

  Future<void> _openSheet() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    builder: (context) => StatefulBuilder(
      builder: (context, setSheetState) {
        final hidden = AppSettings.railHiddenSpaces.value;
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (final id in hidden)
                ListTile(
                  title: Text(_name(id)),
                  trailing: TextButton(
                    onPressed: () async {
                      await _show(id);
                      if (!context.mounted) return;
                      if (AppSettings.railHiddenSpaces.value.isEmpty) {
                        Navigator.of(context).pop();
                      } else {
                        setSheetState(() {});
                      }
                    },
                    child: Text(L10n.of(context).showOnRail),
                  ),
                ),
              const SizedBox(height: 16),
            ],
          ),
        );
      },
    ),
  );

  @override
  Widget build(BuildContext context) {
    final hidden = AppSettings.railHiddenSpaces.value;
    if (hidden.isEmpty) return const SizedBox.shrink();
    return ListTile(
      title: Text(L10n.of(context).hiddenFromRail),
      subtitle: Text(hidden.map(_name).join(', ')),
      onTap: _openSheet,
      trailing: const Padding(
        padding: EdgeInsets.all(16.0),
        child: Icon(Icons.chevron_right_outlined),
      ),
    );
  }
}
