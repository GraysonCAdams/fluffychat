// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/native_context_menu.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Lets the spelling part of a menu teach the spell checker a word.
abstract interface class SpellCheckDictionary {
  /// Accepts [word] from now on, in every app that uses the dictionary.
  void add(String word);

  /// Accepts [word] until the app quits.
  void ignore(String word);
}

/// The message input's right-click menu as Windows draws it, laid out like
/// Notepad's: the spelling suggestions for [span] with "Add to dictionary"
/// and "Ignore", then the editing items of [editableTextState], then
/// [extraItems]. Choosing a suggestion replaces [span]'s range.
List<NativeMenuEntry> composerMenuEntries(
  BuildContext context, {
  required EditableTextState editableTextState,
  required SuggestionSpan? span,
  required SpellCheckDictionary? dictionary,
  List<ContextMenuButtonItem> extraItems = const [],
}) {
  final l10n = L10n.of(context);
  final checkedText = editableTextState.spellCheckResults?.spellCheckedText;
  final word =
      span != null &&
          checkedText != null &&
          span.range.isValid &&
          span.range.end <= checkedText.length
      ? span.range.textInside(checkedText)
      : null;

  List<NativeMenuEntry> section(List<ContextMenuButtonItem> items) => [
    for (final item in items)
      NativeMenuItem(
        label: AdaptiveTextSelectionToolbar.getButtonLabel(context, item),
        ctrlKey: switch (item.type) {
          ContextMenuButtonType.cut => 'X',
          ContextMenuButtonType.copy => 'C',
          ContextMenuButtonType.paste => 'V',
          ContextMenuButtonType.selectAll => 'A',
          _ => null,
        },
        onSelected: item.onPressed,
      ),
  ];

  final sections = <List<NativeMenuEntry>>[
    if (span != null && word != null && word.isNotEmpty) ...[
      [
        for (final suggestion in span.suggestions)
          NativeMenuItem(
            label: suggestion,
            onSelected: () => editableTextState.userUpdateTextEditingValue(
              editableTextState.textEditingValue.replaced(
                span.range,
                suggestion,
              ),
              SelectionChangedCause.toolbar,
            ),
          ),
        if (span.suggestions.isEmpty)
          NativeMenuItem(label: l10n.noSpellingSuggestions),
      ],
      if (dictionary != null)
        [
          NativeMenuItem(
            label: l10n.addToDictionary,
            onSelected: () {
              dictionary.add(word);
              _stopFlagging(editableTextState, word);
            },
          ),
          NativeMenuItem(
            label: l10n.ignoreSpelling,
            onSelected: () {
              dictionary.ignore(word);
              _stopFlagging(editableTextState, word);
            },
          ),
        ],
    ],
    section(_editingItems(editableTextState.contextMenuButtonItems)),
    section(extraItems),
  ].where((section) => section.isNotEmpty);

  return [
    for (final (index, entries) in sections.indexed) ...[
      if (index > 0) const NativeMenuSeparator(),
      ...entries,
    ],
  ];
}

/// Cut, Copy, Paste and Select all in that order, greyed out when Flutter
/// leaves them out (Copy with nothing selected, Paste with an empty
/// clipboard), as Windows menus keep them in place.
List<ContextMenuButtonItem> _editingItems(List<ContextMenuButtonItem> items) {
  const fixed = [
    ContextMenuButtonType.cut,
    ContextMenuButtonType.copy,
    ContextMenuButtonType.paste,
    ContextMenuButtonType.selectAll,
  ];
  return [
    for (final type in fixed)
      items.firstWhere(
        (item) => item.type == type,
        orElse: () => ContextMenuButtonItem(type: type, onPressed: null),
      ),
    ...items.where((item) => !fixed.contains(item.type)),
  ];
}

/// Drops the underline from every occurrence of [word] at once. The spell
/// checker would only stop flagging it at the next edit, when Flutter checks
/// the text again.
void _stopFlagging(EditableTextState state, String word) {
  final results = state.spellCheckResults;
  if (results == null) return;
  final text = results.spellCheckedText;
  state.spellCheckResults = SpellCheckResults(text, [
    for (final span in results.suggestionSpans)
      if (span.range.end > text.length || span.range.textInside(text) != word)
        span,
  ]);
  state.renderEditable.text = state.buildTextSpan();
}

/// Opens the native menu of [editableTextState]'s input. With a
/// [clickPosition] (global, logical pixels) it opens there for the word under
/// it, as a right-click does; without one it opens at the caret for the word
/// there, as Shift+F10 and the Menu key do.
Future<void> showComposerNativeMenu(
  BuildContext context, {
  required EditableTextState editableTextState,
  required SpellCheckDictionary? dictionary,
  Offset? clickPosition,
  List<ContextMenuButtonItem> extraItems = const [],
}) async {
  // Paste is only offered once the clipboard is known to hold text.
  await editableTextState.clipboardStatus.update();
  if (!context.mounted) return;
  final renderEditable = editableTextState.renderEditable;
  final Offset position;
  final int index;
  if (clickPosition != null) {
    position = clickPosition;
    index = renderEditable.getPositionForPoint(clickPosition).offset;
  } else {
    final caret = editableTextState.textEditingValue.selection.extent;
    position = renderEditable.localToGlobal(
      renderEditable.getLocalRectForCaret(caret).bottomLeft,
    );
    index = caret.offset;
  }
  final entries = composerMenuEntries(
    context,
    editableTextState: editableTextState,
    span: editableTextState.findSuggestionSpanAtCursorIndex(index),
    dictionary: dictionary,
    extraItems: extraItems,
  );
  await NativeContextMenu.show(context, entries, globalPosition: position);
}

/// Stands in for the Flutter-drawn menu when [EditableText] asks for one
/// after a right-click: it opens the native menu at the click instead, and
/// tells the field its menu is closed. [composerContext] must outlive the
/// menu, as the items' dialogs open from it.
class NativeComposerMenu extends StatefulWidget {
  final BuildContext composerContext;
  final EditableTextState editableTextState;
  final SpellCheckDictionary? dictionary;
  final List<ContextMenuButtonItem> Function() extraItems;

  const NativeComposerMenu({
    required this.composerContext,
    required this.editableTextState,
    required this.dictionary,
    required this.extraItems,
    super.key,
  });

  @override
  State<NativeComposerMenu> createState() => _NativeComposerMenuState();
}

class _NativeComposerMenuState extends State<NativeComposerMenu> {
  @override
  void initState() {
    super.initState();
    final state = widget.editableTextState;
    final clickPosition = state.renderEditable.lastSecondaryTapDownPosition;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      state.hideToolbar(false);
      if (!widget.composerContext.mounted) return;
      showComposerNativeMenu(
        widget.composerContext,
        editableTextState: state,
        dictionary: widget.dictionary,
        clickPosition: clickPosition,
        extraItems: widget.extraItems(),
      );
    });
  }

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Opens the native menu of the input inside [child] with Shift+F10 or the
/// Menu key, the Windows keys for a context menu, at the caret.
class NativeComposerMenuShortcuts extends StatelessWidget {
  final FocusNode focusNode;
  final SpellCheckDictionary? dictionary;
  final List<ContextMenuButtonItem> Function() extraItems;
  final Widget child;

  const NativeComposerMenuShortcuts({
    required this.focusNode,
    required this.dictionary,
    required this.extraItems,
    required this.child,
    super.key,
  });

  void _open(BuildContext context) {
    final state = focusNode.context
        ?.findAncestorStateOfType<EditableTextState>();
    if (state == null) return;
    showComposerNativeMenu(
      context,
      editableTextState: state,
      dictionary: dictionary,
      extraItems: extraItems(),
    );
  }

  @override
  Widget build(BuildContext context) => CallbackShortcuts(
    bindings: {
      const SingleActivator(LogicalKeyboardKey.f10, shift: true): () =>
          _open(context),
      const SingleActivator(LogicalKeyboardKey.contextMenu): () =>
          _open(context),
    },
    child: child,
  );
}
