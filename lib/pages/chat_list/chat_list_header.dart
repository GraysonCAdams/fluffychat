// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

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
      // The account button sits beside the search field, not inside it. On a
      // phone the field stays folded into a search button until it is used,
      // leaving the screen to the chats.
      title: !isColumnMode && !controller.isSearchMode
          ? Row(
              children: [
                Expanded(
                  child: Text(
                    L10n.of(context).chats,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: L10n.of(context).search,
                  onPressed: controller.startSearch,
                  icon: const Icon(Icons.search_outlined),
                ),
                const SizedBox(width: 4),
                ClientChooserButton(controller),
              ],
            )
          : Row(
              children: [
                Expanded(child: _SearchField(controller, globalSearch)),
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

class _SearchField extends StatelessWidget {
  final ChatListController controller;
  final bool globalSearch;

  const _SearchField(this.controller, this.globalSearch);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onField = theme.colorScheme.onSurfaceVariant;
    return TextField(
      // Centres the text in the shortened field.
      textAlignVertical: TextAlignVertical.center,
      controller: controller.searchController,
      focusNode: controller.searchFocusNode,
      // On a phone the field only appears once search starts.
      autofocus: !FluffyThemes.isColumnMode(context),
      textInputAction: TextInputAction.search,
      onChanged: (text) =>
          controller.onSearchEnter(text, globalSearch: globalSearch),
      decoration: InputDecoration(
        // Slimmer than the default 48 so the bar reads as a pill.
        isDense: true,
        contentPadding: EdgeInsets.zero,
        constraints: const BoxConstraints(maxHeight: 42),
        filled: true,
        // A neutral container at rest: secondaryContainer marks selection.
        fillColor: theme.colorScheme.surfaceContainerHigh,
        border: OutlineInputBorder(
          borderSide: BorderSide.none,
          borderRadius: BorderRadius.circular(99),
        ),
        hintText: L10n.of(context).search,
        hintStyle: theme.textTheme.bodyLarge!.copyWith(color: onField),
        prefixIcon: controller.isSearchMode
            ? IconButton(
                tooltip: L10n.of(context).cancel,
                icon: const Icon(Icons.close_outlined),
                onPressed: controller.cancelSearch,
                color: onField,
              )
            : IconButton(
                tooltip: L10n.of(context).search,
                onPressed: controller.startSearch,
                icon: Icon(Icons.search_outlined, color: onField),
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
    );
  }
}

/// A slim strip under the chat list header while the app is not in step
/// with the server: during the first sync, and while syncing fails. It holds
/// no space once the client is in step.
class SyncStatusStrip extends StatelessWidget {
  const SyncStatusStrip({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dark = theme.brightness == Brightness.dark;
    final foreground = dark ? Colors.amber.shade200 : Colors.amber.shade900;
    return _SyncStatusBuilder(
      client: Matrix.of(context).client,
      builder: (context, status, hide) => AnimatedSize(
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        alignment: Alignment.topCenter,
        child: hide
            ? const SizedBox(width: double.infinity)
            : Container(
                width: double.infinity,
                color: Colors.amber.withAlpha(dark ? 40 : 60),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    SizedBox.square(
                      dimension: 14,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: foreground,
                        value: status.progress,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Text(
                        status.calcLocalizedString(context),
                        style: theme.textTheme.bodyMedium!.copyWith(
                          color: foreground,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
      ),
    );
  }
}

/// Builds the parts of the chat list that show the sync status.
///
/// The client reports several status updates per sync loop, and most leave
/// the display as it was once the first sync is done. Each update is reduced
/// to the inputs the parts read, and only a different result rebuilds them.
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
  /// status is hidden, and the status text and progress while it is not.
  Object? _displayedState() {
    final status = _status;
    final hide = _hide(status);
    return (
      hide,
      hide ? null : status.status,
      hide ? null : status.error?.exception,
      hide ? null : status.progress,
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
