// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart';
import 'package:collection/collection.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/client_chooser_button.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// Links a window title bar that holds the chat list's search field and
/// account button to the chat list they act on. The title bar sits above
/// the app's router, so the list registers itself here, and the field's
/// text and focus live here rather than in any one list: the list is built
/// anew when the window crosses into or out of the column layout, and it is
/// not built at all while settings fill the column layout.
class TitleBarSearch {
  /// Brings the chat list on screen, from wherever the app is.
  final VoidCallback showChatList;

  TitleBarSearch({required this.showChatList});

  final TextEditingController textController = TextEditingController();
  final FocusNode focusNode = FocusNode(debugLabel: 'title bar search');

  /// The chat list the title bar acts on: the one registered last that is
  /// still up, or null while there is none.
  final ValueNotifier<ChatListController?> list = ValueNotifier(null);

  /// Changes after the chat list rebuilds, for the parts of the title bar
  /// that show its search state.
  final ValueNotifier<int> listState = ValueNotifier(0);

  final _lists = <ChatListController>[];
  bool _publishScheduled = false;
  bool _disposed = false;

  /// The title bar search above [context], if there is one.
  static TitleBarSearch? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<TitleBarSearchScope>()?.search;

  void register(ChatListController controller) {
    _lists.add(controller);
    _publish();
  }

  void unregister(ChatListController controller) {
    _lists.remove(controller);
    _publish();
  }

  /// Called by the chat list whenever it rebuilds.
  void listChanged() => _publish();

  /// Passes changes on after the current frame. Lists register, rebuild and
  /// go away while the tree is being built or torn down, when the title bar
  /// cannot be rebuilt.
  void _publish() {
    if (_publishScheduled || _disposed) return;
    _publishScheduled = true;
    SchedulerBinding.instance
      ..addPostFrameCallback((_) {
        _publishScheduled = false;
        if (_disposed) return;
        final current = _lists.lastOrNull;
        if (list.value != current) {
          list.value = current;
          // Text typed while no list was up, or in the list this one
          // replaces, carries on as this list's search.
          final text = textController.text;
          if (current != null && text.isNotEmpty) current.onSearchEnter(text);
        }
        listState.value++;
      })
      ..ensureVisualUpdate();
  }

  /// Whether the chat list is up and in view, rather than covered by
  /// another page in the single column layout or not built at all.
  bool get listOnScreen {
    final controller = list.value;
    if (controller == null || !controller.mounted) return false;
    final context = controller.context;
    if (FluffyThemes.isColumnMode(context)) return true;
    return GoRouter.of(context).routerDelegate.currentConfiguration.uri.path ==
        '/rooms';
  }

  void _showListIfHidden() {
    if (!listOnScreen) showChatList();
  }

  /// Puts the cursor in the field with its text selected, bringing the chat
  /// list on screen for the results.
  void focus() {
    _showListIfHidden();
    focusNode.requestFocus();
    textController.selection = TextSelection(
      baseOffset: 0,
      extentOffset: textController.text.length,
    );
  }

  void _onTap() => _showListIfHidden();

  void _onChanged(String text) {
    _showListIfHidden();
    final controller = list.value;
    if (controller != null && controller.mounted) {
      controller.onSearchEnter(text);
    }
  }

  /// Ends the search: clears the field, leaves it and shows the list as it
  /// was.
  void cancel() {
    final controller = list.value;
    if (controller != null && controller.mounted) {
      controller.cancelSearch();
      return;
    }
    textController.clear();
    focusNode.unfocus();
  }

  void dispose() {
    _disposed = true;
    textController.dispose();
    focusNode.dispose();
    list.dispose();
    listState.dispose();
  }
}

/// Makes [search] available to the chat list below.
class TitleBarSearchScope extends InheritedWidget {
  final TitleBarSearch search;

  const TitleBarSearchScope({
    required this.search,
    required super.child,
    super.key,
  });

  @override
  bool updateShouldNotify(TitleBarSearchScope oldWidget) =>
      search != oldWidget.search;
}

/// The search field of a title bar: a 32 high pill with a search icon, the
/// hint, and at its end the Ctrl+K shortcut while [showShortcutHint] is set.
/// Typing searches the chat list as its own field does; Escape and the
/// clear button end the search, and Ctrl+K anywhere in the window comes
/// here.
class TitleBarSearchField extends StatefulWidget {
  final TitleBarSearch search;
  final bool showShortcutHint;

  const TitleBarSearchField({
    required this.search,
    this.showShortcutHint = false,
    super.key,
  });

  static const double height = 32;

  @override
  State<TitleBarSearchField> createState() => _TitleBarSearchFieldState();
}

class _TitleBarSearchFieldState extends State<TitleBarSearchField> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  /// Ctrl+K, unless it went to another window.
  bool _onKey(KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.keyK ||
        !mounted) {
      return false;
    }
    final keyboard = HardwareKeyboard.instance;
    if (!keyboard.isControlPressed ||
        keyboard.isAltPressed ||
        keyboard.isShiftPressed ||
        keyboard.isMetaPressed) {
      return false;
    }
    final focusContext = FocusManager.instance.primaryFocus?.context;
    if (focusContext != null &&
        View.maybeOf(focusContext) != View.maybeOf(context)) {
      return false;
    }
    widget.search.focus();
    return true;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final search = widget.search;
    final onField = theme.colorScheme.onSurfaceVariant;
    final textStyle = theme.textTheme.bodyMedium!.copyWith(
      fontSize: 14,
      color: theme.colorScheme.onSurface,
    );
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        // A click beside the text still lands in the field.
        onTap: search.focus,
        mouseCursor: SystemMouseCursors.text,
        child: SizedBox(
          height: TitleBarSearchField.height,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(
              children: [
                Icon(Icons.search_outlined, size: 20, color: onField),
                const SizedBox(width: 10),
                Expanded(
                  child: CallbackShortcuts(
                    bindings: {
                      const SingleActivator(LogicalKeyboardKey.escape):
                          search.cancel,
                    },
                    child: TextField(
                      controller: search.textController,
                      focusNode: search.focusNode,
                      textInputAction: TextInputAction.search,
                      textAlignVertical: TextAlignVertical.center,
                      style: textStyle,
                      onTap: search._onTap,
                      onChanged: search._onChanged,
                      decoration: InputDecoration.collapsed(
                        hintText: L10n.of(context).search,
                        hintStyle: textStyle.copyWith(color: onField),
                      ),
                    ),
                  ),
                ),
                ListenableBuilder(
                  listenable: Listenable.merge([
                    search.list,
                    search.listState,
                    search.textController,
                  ]),
                  builder: (context, _) => _trailing(context),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// The end of the field: progress while the list searches the server,
  /// the server the search goes to, and a clear button once there is text;
  /// else the shortcut hint.
  Widget _trailing(BuildContext context) {
    final theme = Theme.of(context);
    final search = widget.search;
    final controller = search.list.value;
    final searching = controller != null && controller.mounted;
    final hasText = search.textController.text.isNotEmpty;
    if (!hasText) {
      if (!widget.showShortcutHint) return const SizedBox.shrink();
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
        decoration: BoxDecoration(
          border: Border.all(color: theme.colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'Ctrl+K',
          style: theme.textTheme.labelSmall?.copyWith(
            fontSize: 11,
            color: theme.colorScheme.outline,
          ),
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (searching && controller.isSearching)
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 4),
            child: SizedBox.square(
              dimension: 16,
              child: CircularProgressIndicator.adaptive(strokeWidth: 2),
            ),
          )
        else if (searching &&
            controller.isSearchMode &&
            widget.showShortcutHint &&
            MatrixFeatures.forClient(
              Matrix.of(controller.context).client,
            ).isRelevant(MatrixFeature.explore))
          // The server whose public rooms the search lists, as the chat
          // list's own field offers it, while public rooms are searched.
          // Only a wide field has room.
          TextButton.icon(
            onPressed: controller.setServer,
            style: TextButton.styleFrom(
              minimumSize: const Size(0, 24),
              padding: const EdgeInsets.symmetric(horizontal: 8),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              visualDensity: VisualDensity.compact,
              textStyle: theme.textTheme.labelLarge?.copyWith(fontSize: 12),
            ),
            icon: const Icon(Icons.edit_outlined, size: 14),
            label: Text(
              controller.searchServer ??
                  Result(
                    () => Matrix.of(controller.context).client.homeserver?.host,
                  ).asValue?.value ??
                  '',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
        IconButton(
          tooltip: L10n.of(context).cancel,
          onPressed: search.cancel,
          iconSize: 18,
          padding: EdgeInsets.zero,
          constraints: const BoxConstraints.tightFor(width: 24, height: 24),
          color: theme.colorScheme.onSurfaceVariant,
          icon: const Icon(Icons.close_outlined),
        ),
      ],
    );
  }
}

/// The account button of a title bar: the chat list's [ClientChooserButton]
/// at [size]. While no chat list is up, a click brings it on screen and
/// then opens the menu.
class TitleBarAccountButton extends StatelessWidget {
  final TitleBarSearch search;
  final double size;

  const TitleBarAccountButton({
    required this.search,
    this.size = 32,
    super.key,
  });

  @override
  Widget build(BuildContext context) => ValueListenableBuilder(
    valueListenable: search.list,
    builder: (context, controller, _) => ClientChooserButton(
      controller,
      size: size,
      onPressedWithoutList: search.showChatList,
    ),
  );
}
