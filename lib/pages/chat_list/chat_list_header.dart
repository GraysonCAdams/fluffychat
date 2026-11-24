// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';

class ChatListHeader extends StatelessWidget implements PreferredSizeWidget {
  final ChatListController controller;
  final bool globalSearch;

  const ChatListHeader({
    super.key,
    required this.controller,
    this.globalSearch = true,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final client = Matrix.of(context).client;
    final isColumnMode = FluffyThemes.isColumnMode(context);

    return SliverAppBar(
      floating: true,
      toolbarHeight: 72,
      pinned: isColumnMode,
      scrolledUnderElevation: 0,
      backgroundColor: isColumnMode
          ? theme.colorScheme.surface.withAlpha(240)
          : Colors.transparent,
      automaticallyImplyLeading: false,
      // The account button sits beside the search field, not inside it.
      title: Row(
        children: [
          Expanded(
            child: TextField(
              // Centres the text in the shortened field.
              textAlignVertical: TextAlignVertical.center,
              controller: controller.searchController,
              focusNode: controller.searchFocusNode,
              textInputAction: TextInputAction.search,
              onChanged: (text) =>
                  controller.onSearchEnter(text, globalSearch: globalSearch),
              decoration: InputDecoration(
                // Slimmer than the default 48 so the bar reads as a pill.
                isDense: true,
                contentPadding: EdgeInsets.zero,
                constraints: const BoxConstraints(maxHeight: 42),
                filled: true,
                fillColor: theme.colorScheme.secondaryContainer,
                border: OutlineInputBorder(
                  borderSide: BorderSide.none,
                  borderRadius: BorderRadius.circular(99),
                ),
                // The hint is the same Text the decorator would build from a
                // hint text (style, one line, ellipsis), but as a widget of its
                // own only it rebuilds when the sync status changes.
                hint: _SyncStatusBuilder(
                  client: client,
                  builder: (context, status, hide) => Text(
                    hide
                        ? L10n.of(context).search
                        : status.calcLocalizedString(context),
                    style: theme.textTheme.bodyLarge!.merge(
                      TextStyle(
                        color: theme.colorScheme.onPrimaryContainer,
                        fontWeight: FontWeight.normal,
                      ),
                    ),
                    overflow: TextOverflow.ellipsis,
                    textAlign: TextAlign.start,
                    maxLines: 1,
                  ),
                ),
                prefixIcon: _SyncStatusBuilder(
                  client: client,
                  builder: (context, status, hide) => hide
                      ? controller.isSearchMode
                            ? IconButton(
                                tooltip: L10n.of(context).cancel,
                                icon: const Icon(Icons.close_outlined),
                                onPressed: controller.cancelSearch,
                                color: theme.colorScheme.onPrimaryContainer,
                              )
                            // Sources are picked from the filter chips, so narrow
                            // layouts have no navigation rail to open.
                            : true
                            ? IconButton(
                                tooltip: L10n.of(context).search,
                                onPressed: controller.startSearch,
                                icon: Icon(
                                  Icons.search_outlined,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              )
                            : IconButton(
                                tooltip: L10n.of(context).displayNavigationRail,
                                onPressed: controller.openNavrail,
                                icon: Icon(
                                  Icons.menu,
                                  color: theme.colorScheme.onPrimaryContainer,
                                ),
                              )
                      : SizedBox(
                          width: 8,
                          height: 8,
                          child: Center(
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                              value: status.progress,
                            ),
                          ),
                        ),
                ),
                suffixIcon: controller.isSearchMode && globalSearch
                    ? controller.isSearching
                          ? const Padding(
                              padding: EdgeInsets.symmetric(
                                vertical: 10.0,
                                horizontal: 12,
                              ),
                              child: SizedBox.square(
                                dimension: 24,
                                child: CircularProgressIndicator.adaptive(
                                  strokeWidth: 2,
                                ),
                              ),
                            )
                          : TextButton.icon(
                              onPressed: controller.setServer,
                              style: TextButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(99),
                                ),
                                textStyle: const TextStyle(fontSize: 12),
                              ),
                              icon: const Icon(Icons.edit_outlined, size: 16),
                              label: Text(
                                controller.searchServer ??
                                    Matrix.of(context).client.homeserver!.host,
                                maxLines: 2,
                              ),
                            )
                    : null,
              ),
            ),
          ),
          if (!controller.isSearchMode) ...[
            const SizedBox(width: 8),
            ClientChooserButton(controller),
          ],
        ],
      ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

/// Builds a part of the search field that shows the sync status: the hint
/// and the leading icon.
///
/// The client reports several status updates per sync loop, and most leave
/// the field as it was once the first sync is done. Each update is reduced to
/// the inputs these parts read, and only a different result rebuilds them.
/// The text field itself is outside the builder, so a status change never
/// rebuilds it.
class _SyncStatusBuilder extends StatefulWidget {
  final Client client;

  /// Gets the current status and whether it is hidden, which it is once the
  /// client has synced and while no error is reported.
  final Widget Function(
    BuildContext context,
    SyncStatusUpdate status,
    bool hide,
  )
  builder;

  const _SyncStatusBuilder({required this.client, required this.builder});

  @override
  State<_SyncStatusBuilder> createState() => _SyncStatusBuilderState();
}

class _SyncStatusBuilderState extends State<_SyncStatusBuilder> {
  StreamSubscription<SyncStatusUpdate>? _subscription;
  Object? _shown;

  SyncStatusUpdate get _status =>
      widget.client.onSyncStatus.value ??
      const SyncStatusUpdate(SyncStatus.waitingForResponse);

  bool _hide(SyncStatusUpdate status) {
    final client = widget.client;
    return client.onSync.value != null &&
        status.status != SyncStatus.error &&
        client.prevBatch != null;
  }

  /// Everything the built parts take from the sync state: whether the
  /// status is hidden, the status text and progress while it is not, and
  /// whether there are spaces, which picks the leading button.
  Object? _displayedState() {
    final status = _status;
    final hide = _hide(status);
    return (
      hide,
      hide ? null : status.status,
      hide ? null : status.error?.exception,
      hide ? null : status.progress,
      widget.client.rooms.any((room) => room.isSpace),
    );
  }

  void _subscribe() {
    _subscription?.cancel();
    _shown = _displayedState();
    _subscription = widget.client.onSyncStatus.stream.listen((_) {
      if (!mounted) return;
      final state = _displayedState();
      if (state == _shown) return;
      setState(() => _shown = state);
    });
  }

  @override
  void initState() {
    super.initState();
    _subscribe();
  }

  @override
  void didUpdateWidget(covariant _SyncStatusBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.client != widget.client) _subscribe();
  }

  @override
  void dispose() {
    _subscription?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // A rebuild from the parent can follow changes no status update
    // reported, so start comparing from what is about to be shown.
    _shown = _displayedState();
    final status = _status;
    return widget.builder(context, status, _hide(status));
  }
}
