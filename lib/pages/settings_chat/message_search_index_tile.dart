// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/message_search/index_operation.dart';
import 'package:fluffychat/utils/message_search/message_search_indexer.dart';
import 'package:fluffychat/utils/size_string.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

/// Shows what the local message search index of the active account costs on
/// disk, and lets the user build it anew.
///
/// Takes no space on platforms without a local index.
class MessageSearchIndexTile extends StatefulWidget {
  const MessageSearchIndexTile({super.key});

  @override
  State<MessageSearchIndexTile> createState() => _MessageSearchIndexTileState();
}

class _MessageSearchIndexTileState extends State<MessageSearchIndexTile> {
  MessageSearchIndexer? _indexer;
  LocalMessageIndexStats? _stats;
  bool _rebuilding = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final indexer = MessageSearchIndexer.of(Matrix.of(context).client);
    if (indexer == _indexer) return;
    _indexer = indexer;
    _stats = null;
    _loadStats();
  }

  Future<void> _loadStats() async {
    final indexer = _indexer;
    final stats = await indexer?.stats();
    if (!mounted || indexer != _indexer) return;
    setState(() => _stats = stats);
  }

  Future<void> _rebuild() async {
    setState(() => _rebuilding = true);
    await _indexer?.rebuild();
    if (!mounted) return;
    setState(() => _rebuilding = false);
    await _loadStats();
  }

  @override
  Widget build(BuildContext context) {
    final stats = _stats;
    if (stats == null) return const SizedBox.shrink();
    final l10n = L10n.of(context);
    return ListTile(
      title: Text(l10n.messageSearchIndex),
      subtitle: Text(
        '${l10n.messageSearchIndexSize(stats.messages, stats.bytes.sizeString)}\n'
        '${l10n.messageSearchIndexDescription}',
      ),
      isThreeLine: true,
      trailing: _rebuilding
          ? const Padding(
              padding: EdgeInsets.all(16),
              child: SizedBox.square(
                dimension: 18,
                child: CircularProgressIndicator.adaptive(strokeWidth: 2),
              ),
            )
          : TextButton(
              onPressed: _rebuild,
              child: Text(l10n.messageSearchIndexRebuild),
            ),
    );
  }
}
