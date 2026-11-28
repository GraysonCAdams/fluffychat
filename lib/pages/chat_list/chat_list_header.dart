// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' show lerpDouble;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_filter_menu.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/pages/chat_list/search_scope.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/shown_sync_status.dart';
import 'package:fluffychat/utils/sync_status_localization.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/matrix.dart';

/// The colour of a bar that floats over the chat list: the surface while
/// it sits at the top, and the surface container once the list scrolls
/// under it, as Material's top app bar does. Never see-through, so a bar
/// that floats back in over the middle of the list hides the rows below.
WidgetStateColor chatListBarColor(ColorScheme colors) =>
    WidgetStateColor.resolveWith(
      (states) => states.contains(WidgetState.scrolledUnder)
          ? colors.surfaceContainer
          : colors.surface,
    );

/// The height of the chat list's bar below the status bar: Material's small
/// top app bar on a phone, which keeps the pinned row close under the
/// title, and a taller bar beside the chats in a wide layout.
double chatListHeaderHeight(BuildContext context) =>
    FluffyThemes.isColumnMode(context) ? 72 : 64;

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
    // A phone's search keeps its field at the top while the results scroll
    // under it, on the bar colour of a list scrolled under, which also
    // fills in behind the status bar.
    final phoneSearch = !isColumnMode && controller.isSearchMode;

    return SliverAppBar(
      floating: true,
      toolbarHeight: chatListHeaderHeight(context),
      pinned: isColumnMode || phoneSearch,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      backgroundColor: isColumnMode
          ? theme.colorScheme.surface.withAlpha(240)
          : phoneSearch
          ? theme.colorScheme.surfaceContainer
          : chatListBarColor(theme.colorScheme),
      automaticallyImplyLeading: false,
      // The account button sits beside the search field, not inside it. On a
      // phone the field stays folded into a search button until it is used,
      // leaving the screen to the chats.
      title: isColumnMode
          ? Row(
              children: [
                if (!controller.isSearchMode) ...[
                  ChatFilterButton(
                    controller: controller,
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(width: 8),
                ],
                Expanded(child: _SearchField(controller, globalSearch)),
                if (!controller.isSearchMode) ...[
                  const SizedBox(width: 8),
                  ClientChooserButton(controller),
                ],
              ],
            )
          : _PhoneTitle(
              // The bar is rebuilt when search pins it, and the key carries
              // the title, its animation and the focused field over.
              key: controller.phoneTitleKey,
              controller: controller,
              searching: controller.isSearchMode,
              globalSearch: globalSearch,
            ),
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(56);
}

/// The phone header's content. At rest: the filter dropdown as its title
/// (see [ChatFilterButton]), a search button and the account button. While
/// searching: a pill search field from the start of the bar to the search
/// icon, which stays where it was and becomes the end of the field, with
/// the Search in button at the field's start (see [SearchScopeButton]), and
/// a close button in the account button's place.
///
/// Opening takes 400 ms (medium 4) in Material's emphasized decelerate
/// easing: the field appears behind the search icon and grows leftwards to
/// the start of the bar, the title fades out and drifts 12 towards the
/// start in the first 30% of it, and the account button shrinks, turns a
/// quarter and fades while the close button turns in. Closing runs the same
/// motion back in 250 ms (medium 1), emphasized accelerate. With animations
/// turned off in the system settings, both happen at once, and so does the
/// close behind a chat opened from the search (see
/// [ChatListController.closesSearchInstantly]).
class _PhoneTitle extends StatefulWidget {
  final ChatListController controller;
  final bool searching;
  final bool globalSearch;

  const _PhoneTitle({
    required this.controller,
    super.key,
    required this.searching,
    required this.globalSearch,
  });

  /// The part of the field that is revealed while it opens.
  static const revealKey = ValueKey('chat_list_search_reveal');

  /// The pill behind the search field.
  static const pillKey = ValueKey('chat_list_search_pill');

  @override
  State<_PhoneTitle> createState() => _PhoneTitleState();
}

class _PhoneTitleState extends State<_PhoneTitle>
    with SingleTickerProviderStateMixin {
  late final AnimationController _open = AnimationController(
    vsync: this,
    duration: Durations.medium4,
    reverseDuration: Durations.medium1,
    value: widget.searching ? 1 : 0,
  );

  late final Animation<double> _grow = CurvedAnimation(
    parent: _open,
    curve: Easing.emphasizedDecelerate,
    reverseCurve: Easing.emphasizedAccelerate,
  );

  /// The parts that come and go, by the share of the motion's time they
  /// take. The field's fill shows at once behind the search icon; what the
  /// field holds fades in once the pill has grown clear of the icon.
  static const _titleOut = Interval(0, 0.3, curve: Easing.standard);
  static const _fillIn = Interval(0, 0.1);
  static const _contentIn = Interval(0.15, 0.5);
  static const _accountOut = Interval(0, 0.5, curve: Easing.standard);
  static const _closeIn = Interval(0.3, 1, curve: Easing.standard);

  /// The width of an icon button, and the gap between the search button
  /// and the account button.
  static const _slot = 48.0;
  static const _gap = 4.0;

  @override
  void didUpdateWidget(_PhoneTitle oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.searching == oldWidget.searching) return;
    if (MediaQuery.disableAnimationsOf(context) ||
        widget.controller.closesSearchInstantly) {
      _open.value = widget.searching ? 1 : 0;
    } else if (widget.searching) {
      _open.forward();
    } else {
      _open.reverse();
    }
  }

  @override
  void dispose() {
    _open.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final l10n = L10n.of(context);
    final colors = Theme.of(context).colorScheme;
    final towardsStart = Directionality.of(context) == TextDirection.rtl
        ? 1
        : -1;
    final title = ChatFilterButton(controller: controller);
    final account = Center(child: ClientChooserButton(controller));
    // Buttons sit centred in their slots rather than filling them: given the
    // slot's tight 48, an icon button would draw its state layer 48 across
    // instead of Material's 40 circle.
    final close = Center(
      child: IconButton(
        tooltip: l10n.cancel,
        icon: const Icon(Icons.close_outlined),
        onPressed: controller.cancelSearch,
      ),
    );
    final field = _PhoneSearchField(controller, widget.globalSearch);
    // The search icon's distance from the end of the bar, which is where
    // the field ends.
    const fieldEnd = _slot + _gap;
    return SizedBox(
      height: _slot,
      width: double.infinity,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final fullWidth = constraints.maxWidth - fieldEnd;
          return AnimatedBuilder(
            animation: _open,
            builder: (context, _) {
              final searching = widget.searching;
              final value = _open.value;
              final titleOut = _titleOut.transform(value);
              final accountOut = _accountOut.transform(value);
              final closeIn = _closeIn.transform(value);
              // Every child is keyed, so each keeps its element while the
              // others come and go. The field in particular is one element
              // for the whole animation, so its focus, text and keyboard
              // carry through it: rebuilt, it would drop the keyboard.
              return Stack(
                children: [
                  if (value < 1)
                    PositionedDirectional(
                      key: const ValueKey('title'),
                      start: 0,
                      end: fieldEnd + _slot,
                      top: 0,
                      bottom: 0,
                      child: IgnorePointer(
                        ignoring: searching,
                        child: Opacity(
                          opacity: 1 - titleOut,
                          child: Transform.translate(
                            offset: Offset(towardsStart * 12 * titleOut, 0),
                            child: Align(
                              alignment: AlignmentDirectional.centerStart,
                              child: title,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (value > 0 || searching)
                    PositionedDirectional(
                      key: const ValueKey('field'),
                      end: fieldEnd,
                      top: 0,
                      bottom: 0,
                      width: lerpDouble(_slot, fullWidth, _grow.value),
                      child: IgnorePointer(
                        ignoring: !searching,
                        // The pill is the Material the field's buttons
                        // draw their ink on.
                        child: Material(
                          key: _PhoneTitle.pillKey,
                          animationDuration: Duration.zero,
                          color: colors.surfaceContainerHigh.withValues(
                            alpha: _fillIn.transform(value),
                          ),
                          shape: const StadiumBorder(),
                          child: ClipRect(
                            key: _PhoneTitle.revealKey,
                            // Laid out at its full width from the start and
                            // revealed from the end, so nothing in it moves
                            // while the pill grows.
                            child: OverflowBox(
                              alignment: AlignmentDirectional.centerEnd,
                              minWidth: fullWidth,
                              maxWidth: fullWidth,
                              child: Opacity(
                                opacity: _contentIn.transform(value),
                                child: field,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                  PositionedDirectional(
                    key: const ValueKey('search'),
                    end: fieldEnd,
                    top: 0,
                    bottom: 0,
                    width: _slot,
                    child: searching
                        // The end of the field, which is already focused.
                        ? ExcludeSemantics(
                            child: Center(
                              child: Icon(
                                Icons.search_outlined,
                                color: colors.onSurfaceVariant,
                              ),
                            ),
                          )
                        : Center(
                            child: IconButton(
                              tooltip: l10n.search,
                              onPressed: controller.startSearch,
                              icon: const Icon(Icons.search_outlined),
                            ),
                          ),
                  ),
                  if (value < 1)
                    PositionedDirectional(
                      key: const ValueKey('account'),
                      end: 0,
                      top: 0,
                      bottom: 0,
                      width: _slot,
                      child: IgnorePointer(
                        ignoring: searching,
                        child: Opacity(
                          opacity: 1 - accountOut,
                          child: Transform.rotate(
                            angle: accountOut * math.pi / 2,
                            child: Transform.scale(
                              scale: 1 - accountOut / 2,
                              child: account,
                            ),
                          ),
                        ),
                      ),
                    ),
                  if (value > 0 || searching)
                    PositionedDirectional(
                      key: const ValueKey('close'),
                      end: 0,
                      top: 0,
                      bottom: 0,
                      width: _slot,
                      child: IgnorePointer(
                        ignoring: !searching,
                        child: Opacity(
                          opacity: closeIn,
                          child: Transform.rotate(
                            angle: (closeIn - 1) * math.pi / 2,
                            child: Transform.scale(
                              scale: 0.5 + closeIn / 2,
                              child: close,
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              );
            },
          );
        },
      ),
    );
  }
}

/// The phone's search field, in the pill of [_PhoneTitle]: the Search in
/// button or chip at its start, the text, and room at its end for the
/// search icon, which [_PhoneTitle] places there.
class _PhoneSearchField extends StatelessWidget {
  final ChatListController controller;
  final bool globalSearch;

  const _PhoneSearchField(this.controller, this.globalSearch);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final onField = theme.colorScheme.onSurfaceVariant;
    return Row(
      children: [
        SearchScopeButton(controller: controller),
        Expanded(
          child: TextField(
            textAlignVertical: TextAlignVertical.center,
            controller: controller.searchController,
            focusNode: controller.searchFocusNode,
            // The field only exists once search starts.
            autofocus: true,
            textInputAction: TextInputAction.search,
            onChanged: (text) =>
                controller.onSearchEnter(text, globalSearch: globalSearch),
            style: theme.textTheme.bodyLarge,
            decoration: InputDecoration(
              isDense: true,
              contentPadding: const EdgeInsetsDirectional.only(start: 4),
              border: InputBorder.none,
              hintText: controller.searchScope.hint(L10n.of(context)),
              hintStyle: theme.textTheme.bodyLarge!.copyWith(color: onField),
            ),
          ),
        ),
        if (globalSearch) ?_searchProgressOrServer(context, controller),
        const SizedBox(width: 48),
      ],
    );
  }
}

/// The end of a search field while it searches the server: progress while
/// the server answers, then the server whose public rooms are listed, which
/// a tap changes. The server only matters while public rooms are searched
/// at all, so without them there is nothing after the progress.
Widget? _searchProgressOrServer(
  BuildContext context,
  ChatListController controller,
) {
  if (controller.isSearching) {
    return const Padding(
      padding: EdgeInsets.symmetric(vertical: 10.0, horizontal: 12),
      child: SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
      ),
    );
  }
  final explore = MatrixFeatures.forClient(
    Matrix.of(context).client,
  ).isRelevant(MatrixFeature.explore);
  if (!explore) return null;
  final theme = Theme.of(context);
  return TextButton.icon(
    onPressed: controller.setServer,
    style: TextButton.styleFrom(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(99)),
      // The theme's label style, so the text keeps the app font.
      textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 12),
    ),
    icon: const Icon(Icons.edit_outlined, size: 16),
    label: Text(
      controller.searchServer ?? Matrix.of(context).client.homeserver!.host,
      maxLines: 2,
    ),
  );
}

/// The search field of the wide layout, which is always shown: a search
/// button at its start that turns into a close button while searching.
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
            ? _searchProgressOrServer(context, controller)
            : null,
      ),
    );
  }
}

/// A pill near the bottom of the chat list while the app is not in step with
/// the server: during the first sync, and while syncing fails. Nothing moves
/// in the list when it comes or goes.
class SyncStatusToast extends StatelessWidget {
  const SyncStatusToast({super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final foreground = theme.colorScheme.onInverseSurface;
    return _SyncStatusBuilder(
      builder: (context, status, hide) => AnimatedSwitcher(
        duration: FluffyThemes.animationDuration,
        child: hide
            ? const SizedBox.shrink()
            : Material(
                color: theme.colorScheme.inverseSurface,
                elevation: 3,
                shape: const StadiumBorder(),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(14, 10, 18, 10),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox.square(
                        dimension: 16,
                        // Spins rather than showing the sync progress, which
                        // is near zero while the server cannot be reached.
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: foreground,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Flexible(
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
      ),
    );
  }
}

/// Builds the parts of the chat list that show the sync status.
///
/// The client reports several status updates per sync loop, and most leave
/// the display as it was once the first sync is done. Each update is reduced
/// to the inputs the parts read, and only a different result rebuilds them.
///
/// The status is the active account's. [Matrix] tells no one when the active
/// account changes, so each build reads it again, and the bound account
/// signing out rebuilds the parts, which then show the account that is left.
class _SyncStatusBuilder extends StatefulWidget {
  /// Gets the current status and whether it is hidden, which it is once the
  /// client has synced and while no error is reported.
  final Widget Function(
    BuildContext context,
    SyncStatusUpdate status,
    bool hide,
  )
  builder;

  const _SyncStatusBuilder({required this.builder});

  @override
  State<_SyncStatusBuilder> createState() => _SyncStatusBuilderState();
}

class _SyncStatusBuilderState extends State<_SyncStatusBuilder> {
  Client? _client;
  ShownSyncStatus? _source;
  StreamSubscription<LoginState>? _signOut;
  Object? _shown;

  /// The status as the app shows it (see [ShownSyncStatus]), which leaves
  /// out a failure from while the app was away.
  ShownSyncStatus get _sync => _source!;

  SyncStatusUpdate get _status => _sync.failure ?? _sync.latest;

  bool _hide(SyncStatusUpdate status) {
    final client = _client!;
    return _sync.failure == null &&
        client.onSync.value != null &&
        status.status != SyncStatus.error &&
        client.prevBatch != null;
  }

  /// Everything the built parts take from the sync state: whether the
  /// status is hidden, and the status text while it is not.
  Object? _displayedState() {
    final status = _status;
    final hide = _hide(status);
    return (
      hide,
      hide ? null : status.status,
      hide ? null : status.error?.exception,
    );
  }

  void _onStatus() {
    if (!mounted) return;
    final state = _displayedState();
    if (state == _shown) return;
    setState(() => _shown = state);
  }

  /// Rebuilds once [Matrix] has dropped the signed-out account, which it
  /// does from its own listener, so the next build reads the account left.
  /// Nothing is left to show after the last account signs out.
  void _onSignOut(LoginState _) => Future.microtask(() {
    if (!mounted || !Matrix.of(context).hasClients) return;
    setState(() {});
  });

  /// Watches [client] when it is not the account watched already.
  void _bind(Client client) {
    if (client == _client) return;
    _source?.removeListener(_onStatus);
    _signOut?.cancel();
    _client = client;
    _source = ShownSyncStatus.of(client)..addListener(_onStatus);
    _signOut = client.onLoginStateChanged.stream
        .where((state) => state == LoginState.loggedOut)
        .listen(_onSignOut);
  }

  @override
  void initState() {
    super.initState();
    _bind(Matrix.of(context).client);
    _shown = _displayedState();
  }

  @override
  void dispose() {
    _source?.removeListener(_onStatus);
    _signOut?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _bind(Matrix.of(context).client);
    // A rebuild from the parent can follow changes no status update
    // reported, so start comparing from what is about to be shown.
    _shown = _displayedState();
    final status = _status;
    return widget.builder(context, status, _hide(status));
  }
}
