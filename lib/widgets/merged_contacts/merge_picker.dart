// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Lets the user pick direct chats to merge, several at once. Returns the
/// picked room IDs, or null when cancelled. Rooms in [exclude] are not
/// offered.
Future<List<String>?> showMergePicker(
  BuildContext context, {
  required Client client,
  Set<String> exclude = const {},
}) => showAdaptiveBottomSheet<List<String>>(
  context: context,
  builder: (context) => _MergePicker(client: client, exclude: exclude),
);

class _MergePicker extends StatefulWidget {
  final Client client;
  final Set<String> exclude;

  const _MergePicker({required this.client, required this.exclude});

  @override
  State<_MergePicker> createState() => _MergePickerState();
}

class _Candidate {
  final Room room;
  final Room? network;
  final String name;
  final String networkName;

  /// Name and network in lower case, built once so a keystroke in the search
  /// field only compares strings.
  final String searchText;

  _Candidate(this.room, this.network, this.name, this.networkName)
    : searchText = '${name.toLowerCase()}\n${networkName.toLowerCase()}';
}

class _MergePickerState extends State<_MergePicker> {
  late final List<_Candidate> _candidates;
  final Set<String> _picked = {};
  String _query = '';

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_initialized) return;
    _initialized = true;
    final locals = MatrixLocals(L10n.of(context));
    final spaces = spacesByChild(widget.client);
    _candidates = [
      for (final room in widget.client.rooms)
        if (room.membership == Membership.join &&
            room.isDirectChat &&
            !room.isSpace &&
            !widget.exclude.contains(room.id))
          _Candidate(
            room,
            spaces[room.id],
            room.getLocalizedDisplayname(locals),
            networkName(room, spaces[room.id], locals),
          ),
    ];
  }

  bool _initialized = false;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final query = _query;
    final shown = query.isEmpty
        ? _candidates
        : _candidates.where((c) => c.searchText.contains(query)).toList();
    return Scaffold(
      appBar: AppBar(
        leading: const CloseButton(),
        title: Text(l10n.chooseChatsToMerge),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 8),
            child: FilledButton(
              onPressed: _picked.isEmpty
                  ? null
                  : () => Navigator.of(context).pop(_picked.toList()),
              child: Text(l10n.merge),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
            child: TextField(
              autofocus: true,
              decoration: InputDecoration(
                prefixIcon: const Icon(Icons.search_outlined),
                hintText: l10n.search,
              ),
              onChanged: (text) =>
                  setState(() => _query = text.trim().toLowerCase()),
            ),
          ),
          Expanded(
            child: shown.isEmpty
                ? Center(child: Text(l10n.noChatsFoundHere))
                : ListView.builder(
                    itemCount: shown.length,
                    itemBuilder: (context, i) {
                      final candidate = shown[i];
                      final network = candidate.network;
                      final picked = _picked.contains(candidate.room.id);
                      return CheckboxListTile(
                        value: picked,
                        onChanged: (value) => setState(
                          () => value == true
                              ? _picked.add(candidate.room.id)
                              : _picked.remove(candidate.room.id),
                        ),
                        secondary: SizedBox(
                          width: Avatar.defaultSize,
                          height: Avatar.defaultSize,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Avatar(
                                mxContent: candidate.room.avatar,
                                name: candidate.name,
                              ),
                              if (network != null)
                                Positioned(
                                  right: -4,
                                  bottom: -4,
                                  child: Avatar(
                                    mxContent: network.avatar,
                                    name: candidate.networkName,
                                    size: Avatar.defaultSize * 0.42,
                                    borderRadius: BorderRadius.circular(5),
                                  ),
                                ),
                            ],
                          ),
                        ),
                        title: Text(
                          candidate.name,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        subtitle: Text(
                          candidate.networkName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            color: theme.colorScheme.onSurfaceVariant,
                          ),
                        ),
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
