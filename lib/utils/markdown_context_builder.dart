// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_text_input_dialog.dart';
import 'package:material_ui/material_ui.dart';

/// The Flutter-drawn selection menu of the message input: the platform's
/// editing buttons followed by [markdownButtonItems]. Windows shows a native
/// menu instead (composer_native_menu.dart).
class MarkdownContextBuilder extends StatelessWidget {
  final EditableTextState editableTextState;
  final TextEditingController controller;
  final VoidCallback? onPasteImage;

  const MarkdownContextBuilder({
    required this.editableTextState,
    required this.controller,
    this.onPasteImage,
    super.key,
  });

  @override
  Widget build(BuildContext context) =>
      AdaptiveTextSelectionToolbar.buttonItems(
        anchors: editableTextState.contextMenuAnchors,
        buttonItems: [
          ...editableTextState.contextMenuButtonItems,
          ...markdownButtonItems(
            context,
            controller: controller,
            onPasteImage: onPasteImage,
          ),
        ],
      );
}

/// The message input's own menu items: pasting an image when [onPasteImage]
/// is set, and with text selected, markdown formatting for it. [context]
/// must outlive the menu, since the link item opens a dialog from it.
List<ContextMenuButtonItem> markdownButtonItems(
  BuildContext context, {
  required TextEditingController controller,
  VoidCallback? onPasteImage,
}) {
  final value = controller.value;
  final selectedText = value.selection.textInside(value.text);
  final l10n = L10n.of(context);

  return [
    if (onPasteImage != null)
      ContextMenuButtonItem(
        label: l10n.pasteImage,
        onPressed: () {
          ContextMenuController.removeAny();
          onPasteImage();
        },
      ),
    if (selectedText.isNotEmpty) ...[
      ContextMenuButtonItem(
        label: l10n.link,
        onPressed: () async {
          final input = await showTextInputDialog(
            context: context,
            title: l10n.addLink,
            okLabel: l10n.ok,
            cancelLabel: l10n.cancel,
            validator: (text) {
              if (text.isEmpty) {
                return l10n.pleaseFillOut;
              }
              try {
                text.startsWith('http') ? Uri.parse(text) : Uri.https(text);
              } catch (_) {
                return l10n.invalidUrl;
              }
              return null;
            },
            hintText: 'www...',
            keyboardType: TextInputType.url,
          );
          final urlString = input;
          if (urlString == null) return;
          final url = urlString.startsWith('http')
              ? Uri.parse(urlString)
              : Uri.https(urlString);
          final selection = controller.selection;
          controller.text = controller.text.replaceRange(
            selection.start,
            selection.end,
            '[$selectedText]($url)',
          );
          ContextMenuController.removeAny();
        },
      ),
      ContextMenuButtonItem(
        label: l10n.checkList,
        onPressed: () {
          final text = controller.text;
          final selection = controller.selection;

          var start = selection.textBefore(text).lastIndexOf('\n');
          if (start == -1) start = 0;
          final end = selection.end;

          final fullLineSelection = TextSelection(
            baseOffset: start,
            extentOffset: end,
          );

          const checkBox = '- [ ]';

          final replacedRange = fullLineSelection
              .textInside(text)
              .split('\n')
              .map(
                (line) => line.startsWith(checkBox) || line.isEmpty
                    ? line
                    : '$checkBox $line',
              )
              .join('\n');
          controller.text = controller.text.replaceRange(
            start,
            end,
            replacedRange,
          );
          ContextMenuController.removeAny();
        },
      ),
      ContextMenuButtonItem(
        label: l10n.boldText,
        onPressed: () {
          final selection = controller.selection;
          controller.text = controller.text.replaceRange(
            selection.start,
            selection.end,
            '**$selectedText**',
          );
          ContextMenuController.removeAny();
        },
      ),
      ContextMenuButtonItem(
        label: l10n.italicText,
        onPressed: () {
          final selection = controller.selection;
          controller.text = controller.text.replaceRange(
            selection.start,
            selection.end,
            '*$selectedText*',
          );
          ContextMenuController.removeAny();
        },
      ),
      ContextMenuButtonItem(
        label: l10n.strikeThrough,
        onPressed: () {
          final selection = controller.selection;
          controller.text = controller.text.replaceRange(
            selection.start,
            selection.end,
            '~~$selectedText~~',
          );
          ContextMenuController.removeAny();
        },
      ),
    ],
  ];
}
