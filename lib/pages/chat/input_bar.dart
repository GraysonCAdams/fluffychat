// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cross_file/cross_file.dart';
import 'package:emoji_picker_flutter/emoji_picker_flutter.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/trust_user_key_dialog.dart';
import 'package:fluffychat/utils/composer_native_menu.dart';
import 'package:fluffychat/utils/emoticons.dart';
import 'package:fluffychat/utils/inserted_content_file.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/markdown_context_builder.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/media_adaptation.dart';
import 'package:fluffychat/utils/native_context_menu.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/room_features.dart';
import 'package:fluffychat/utils/spell_check.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:pasteboard/pasteboard.dart';
import 'package:slugify/slugify.dart';

import '../../widgets/avatar.dart';
import '../../widgets/matrix.dart';
import 'command_hints.dart';

/// The lower case keywords of every emoji in a suggestion list, by index.
///
/// The lists hold thousands of emojis and are kept for as long as the chat
/// uses the same locale, so the keywords are split and lowered once per
/// list instead of on every keystroke of an emoji search.
final Expando<List<List<String>>> _lowerCaseEmojiKeywords = Expando();

/// The emojis of [emojis] that [query] (lower case) finds, best first, each
/// with the keyword it is listed under: emojis with a keyword that is the
/// query, then that starts with it, then with a word of a keyword that
/// starts with it, then that contains it. Among equals the list's own
/// order decides, which puts faces and people first. The emoji data has no
/// short names, only keywords in alphabetical order, so a row shows the
/// keyword found, with two of the others to tell similar emoji apart.
List<({Emoji emoji, String keyword})> rankEmojiSuggestions(
  List<Emoji> emojis,
  String query, {
  int limit = 30,
}) {
  final keywords = _lowerCaseEmojiKeywords[emojis] ??= [
    for (final emoji in emojis)
      [for (final keyword in emoji.keywords) keyword.toLowerCase()],
  ];
  final found = <({int rank, int index, String keyword})>[];
  for (var i = 0; i < emojis.length; i++) {
    int? best;
    String? bestKeyword;
    for (final keyword in keywords[i]) {
      final int rank;
      if (keyword == query) {
        rank = 0;
      } else if (keyword.startsWith(query)) {
        rank = 1;
      } else if (keyword
          .split(RegExp(r'[\s_-]'))
          .any((word) => word.startsWith(query))) {
        rank = 2;
      } else if (keyword.contains(query)) {
        rank = 3;
      } else {
        continue;
      }
      if (best == null ||
          rank < best ||
          (rank == best && keyword.length < bestKeyword!.length)) {
        best = rank;
        bestKeyword = keyword;
      }
    }
    if (best != null) {
      found.add((rank: best, index: i, keyword: bestKeyword!));
    }
  }
  found.sort((a, b) {
    final byRank = a.rank.compareTo(b.rank);
    if (byRank != 0) return byRank;
    return a.index.compareTo(b.index);
  });
  return [
    for (final hit in found.take(limit))
      (emoji: emojis[hit.index], keyword: hit.keyword),
  ];
}

/// Lets the chat pick the highlighted composer suggestion with Enter or
/// Tab, which the chat's own key handling sees before the suggestions do.
class ComposerSuggestions {
  VoidCallback? _pick;

  /// Whether suggestions are showing.
  bool get open => _pick != null;

  /// Picks the highlighted suggestion. Returns false when none is showing.
  bool pickHighlighted() {
    final pick = _pick;
    if (pick == null) return false;
    pick();
    return true;
  }
}

/// At most this many suggestion rows show at once; the rest scroll.
const _visibleSuggestions = 6;

/// The height of a suggestion row.
const double _suggestionRowHeight = 44;

class InputBar extends StatelessWidget {
  final Room room;
  final int? minLines;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<Uint8List?>? onSubmitImage;

  /// Receives an image or GIF the keyboard inserted, to stage it as an
  /// attachment. Without it the file is sent at once.
  final ValueChanged<XFile>? onInsertFile;
  final FocusNode? focusNode;
  final TextEditingController? controller;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final bool? autofocus;
  final bool readOnly;
  final List<Emoji> suggestionEmojis;
  final UndoHistoryController? undoController;

  /// Converts emoticons as they are typed; kept by the page, as it
  /// remembers the last conversion for Backspace to undo.
  final EmoticonFormatter? emoticonFormatter;

  /// Hands the chat a way to pick the highlighted suggestion.
  final ComposerSuggestions? suggestions;

  const InputBar({
    required this.room,
    this.minLines,
    this.maxLines,
    this.keyboardType,
    this.onSubmitted,
    this.onSubmitImage,
    this.onInsertFile,
    this.focusNode,
    this.controller,
    required this.decoration,
    this.onChanged,
    this.autofocus,
    this.textInputAction,
    this.readOnly = false,
    required this.suggestionEmojis,
    this.undoController,
    this.emoticonFormatter,
    this.suggestions,
    super.key,
  });

  List<Map<String, String?>> getSuggestions(TextEditingValue text) {
    if (text.selection.baseOffset != text.selection.extentOffset ||
        text.selection.baseOffset < 0) {
      return []; // no entries if there is selected text
    }
    final searchText = text.text.substring(0, text.selection.baseOffset);
    final ret = <Map<String, String?>>[];
    const maxResults = 30;

    final commandMatch = RegExp(r'^/(\w*)$').firstMatch(searchText);
    if (commandMatch != null) {
      final commandSearch = commandMatch[1]!.toLowerCase();
      for (final command in room.client.commands.keys) {
        if (command.contains(commandSearch)) {
          ret.add({'type': 'command', 'name': command});
        }

        if (ret.length > maxResults) return ret;
      }
    }
    final emojiMatch = RegExp(
      r'(?:\s|^):(?:([\p{L}\p{N}_-]+)~)?([\p{L}\p{N}_-]+)$',
      unicode: true,
    ).firstMatch(searchText);
    // Emoji search is off unless the user turned it on. It needs two
    // characters, one a letter, after the colon, as in Slack and Discord,
    // and leaves an emoticon such as :D or :-P alone (see emoticons.dart),
    // as it does anything in Markdown code.
    final emojiWord = emojiMatch?[0]?.trimLeft();
    if (emojiMatch != null &&
        AppSettings.emojiSuggestions.value &&
        emojiMatch[2]!.length >= 2 &&
        RegExp(r'\p{L}', unicode: true).hasMatch(emojiMatch[2]!) &&
        !isEmoticon(emojiWord!) &&
        !inMarkdownCode(searchText, searchText.length - emojiWord.length)) {
      final packSearch = emojiMatch[1];
      final emoteSearch = emojiMatch[2]!.toLowerCase();
      final emotePacks = room.getImagePacks(ImagePackUsage.emoticon);
      if (packSearch == null || packSearch.isEmpty) {
        for (final pack in emotePacks.entries) {
          for (final emote in pack.value.images.entries) {
            if (emote.key.toLowerCase().contains(emoteSearch)) {
              ret.add({
                'type': 'emote',
                'name': emote.key,
                'pack': pack.key,
                'pack_avatar_url': pack.value.pack.avatarUrl?.toString(),
                'pack_display_name': pack.value.pack.displayName ?? pack.key,
                'mxc': emote.value.url.toString(),
              });
            }
            if (ret.length > maxResults) {
              break;
            }
          }
          if (ret.length > maxResults) {
            break;
          }
        }
      } else if (emotePacks[packSearch] != null) {
        for (final emote in emotePacks[packSearch]!.images.entries) {
          if (emote.key.toLowerCase().contains(emoteSearch)) {
            ret.add({
              'type': 'emote',
              'name': emote.key,
              'pack': packSearch,
              'pack_avatar_url': emotePacks[packSearch]!.pack.avatarUrl
                  ?.toString(),
              'pack_display_name':
                  emotePacks[packSearch]!.pack.displayName ?? packSearch,
              'mxc': emote.value.url.toString(),
            });
          }
          if (ret.length > maxResults) {
            break;
          }
        }
      }

      // Aside of emote packs, also propose Unicode emojis.
      for (final hit in rankEmojiSuggestions(
        suggestionEmojis,
        emoteSearch,
        limit: maxResults + 1 - ret.length,
      )) {
        ret.add({
          'type': 'emoji',
          'emoji': hit.emoji.emoji,
          'label': hit.keyword,
          'others': hit.emoji.keywords
              .where((keyword) => keyword.toLowerCase() != hit.keyword)
              .take(2)
              .join(' · '),
          'query': emoteSearch,
          'current_word': ':${emojiMatch[2]}',
        });
      }
    }
    final userMatch = RegExp(r'(?:\s|^)@([-\w]+)$').firstMatch(searchText);
    if (userMatch != null) {
      final userSearch = userMatch[1]!.toLowerCase();
      for (final user in room.getParticipants()) {
        if ((user.displayName != null &&
                (user.displayName!.toLowerCase().contains(userSearch) ||
                    slugify(
                      user.displayName!.toLowerCase(),
                    ).contains(userSearch))) ||
            user.id.localpart!.toLowerCase().contains(userSearch)) {
          ret.add({
            'type': 'user',
            'mxid': user.id,
            'mention': user.mention,
            'displayname': user.displayName,
            'avatar_url': user.avatarUrl?.toString(),
          });
        }
        if (ret.length > maxResults) {
          break;
        }
      }
    }
    final roomMatch = RegExp(r'(?:\s|^)#([-\w]+)$').firstMatch(searchText);
    if (roomMatch != null) {
      final roomSearch = roomMatch[1]!.toLowerCase();
      for (final r in room.client.rooms) {
        if (r.getState(EventTypes.RoomTombstone) != null) {
          continue; // we don't care about tombstoned rooms
        }
        final state = r.getState(EventTypes.RoomCanonicalAlias);
        if ((state != null &&
                ((state.content['alias'] is String &&
                        state.content
                            .tryGet<String>('alias')!
                            .localpart!
                            .toLowerCase()
                            .contains(roomSearch)) ||
                    (state.content['alt_aliases'] is List &&
                        (state.content['alt_aliases'] as List).any(
                          (l) =>
                              l is String &&
                              l.localpart!.toLowerCase().contains(roomSearch),
                        )))) ||
            (r.name.toLowerCase().contains(roomSearch))) {
          ret.add({
            'type': 'room',
            'mxid': (r.canonicalAlias.isNotEmpty) ? r.canonicalAlias : r.id,
            'displayname': r.getLocalizedDisplayname(),
            'avatar_url': r.avatar?.toString(),
          });
        }
        if (ret.length > maxResults) {
          break;
        }
      }
    }
    return ret;
  }

  /// One compact row of the suggestions: 44 high, with the emoji, emote or
  /// avatar in a 32 box and one line of text, tinted while it is the
  /// highlighted one that Enter or Tab picks.
  Widget buildSuggestion(
    BuildContext context,
    Map<String, String?> suggestion,
    void Function(Map<String, String?>) onSelected,
    Client? client, {
    bool highlighted = false,
  }) {
    final theme = Theme.of(context);
    const size = 28.0;
    final secondary = theme.textTheme.bodyMedium?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    Widget row(Widget leading, Widget text) => InkWell(
      onTap: () => onSelected(suggestion),
      child: Ink(
        height: _suggestionRowHeight,
        color: highlighted
            ? theme.colorScheme.onSurface.withValues(alpha: 0.1)
            : null,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            SizedBox.square(dimension: 32, child: Center(child: leading)),
            const SizedBox(width: 12),
            Expanded(child: text),
          ],
        ),
      ),
    );
    switch (suggestion['type']) {
      case 'command':
        final command = suggestion['name']!;
        return row(
          Icon(Icons.terminal, size: 20, color: secondary?.color),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '/$command',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                TextSpan(
                  text: '  ${commandHint(L10n.of(context), command)}',
                  style: secondary,
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      case 'emoji':
        final label = suggestion['label']!;
        final query = suggestion['query'] ?? '';
        final at = label.indexOf(query);
        return row(
          Text(suggestion['emoji']!, style: const TextStyle(fontSize: 22)),
          Text.rich(
            TextSpan(
              children: [
                const TextSpan(text: ':'),
                if (at < 0 || query.isEmpty)
                  TextSpan(text: label)
                else ...[
                  TextSpan(text: label.substring(0, at)),
                  TextSpan(
                    text: label.substring(at, at + query.length),
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                  TextSpan(text: label.substring(at + query.length)),
                ],
                const TextSpan(text: ':'),
                if (suggestion['others']?.isNotEmpty ?? false)
                  TextSpan(text: '  ${suggestion['others']}', style: secondary),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      case 'emote':
        return row(
          MxcImage(
            // ensure proper ordering ...
            key: ValueKey(suggestion['name']),
            uri: suggestion['mxc'] is String
                ? Uri.parse(suggestion['mxc'] ?? '')
                : null,
            width: size,
            height: size,
            isThumbnail: false,
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: ':${suggestion['name']!}:'),
                TextSpan(
                  text: '  ${suggestion['pack_display_name'] ?? ''}',
                  style: secondary,
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
      case 'user':
      case 'room':
        final url = Uri.parse(suggestion['avatar_url'] ?? '');
        final name = suggestion['displayname'] ?? suggestion['mxid']!;
        // A user is told apart by their ID, shortened in messenger mode.
        // The mention inserted keeps the full ID.
        final id =
            suggestion['type'] == 'user' && suggestion['displayname'] != null
            ? MatrixFeatures.forClient(
                room.client,
              ).userLabel(suggestion['mxid']!, room: room)
            : null;
        return row(
          Avatar(
            mxContent: url,
            name:
                suggestion.tryGet<String>('displayname') ??
                suggestion.tryGet<String>('mxid'),
            size: size,
            client: client,
          ),
          Text.rich(
            TextSpan(
              children: [
                TextSpan(text: name),
                if (id != null) TextSpan(text: '  $id', style: secondary),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        );
    }
    return const SizedBox.shrink();
  }

  String insertSuggestion(Map<String, String?> suggestion) {
    final replaceText = controller!.text.substring(
      0,
      controller!.selection.baseOffset,
    );
    var startText = '';
    final afterText = replaceText == controller!.text
        ? ''
        : controller!.text.substring(controller!.selection.baseOffset + 1);
    var insertText = '';
    if (suggestion['type'] == 'command') {
      insertText = '${suggestion['name']!} ';
      startText = replaceText.replaceAllMapped(
        RegExp(r'^(/\w*)$'),
        (Match m) => '/$insertText',
      );
    }
    if (suggestion['type'] == 'emoji') {
      insertText = '${suggestion['emoji']!} ';
      // Only the word being typed, which ends where the cursor is.
      final word = suggestion['current_word']!;
      startText = replaceText.endsWith(word)
          ? replaceText.substring(0, replaceText.length - word.length) +
                insertText
          : replaceText;
    }
    if (suggestion['type'] == 'emote') {
      var isUnique = true;
      final insertEmote = suggestion['name'];
      final insertPack = suggestion['pack'];
      final emotePacks = room.getImagePacks(ImagePackUsage.emoticon);
      for (final pack in emotePacks.entries) {
        if (pack.key == insertPack) {
          continue;
        }
        for (final emote in pack.value.images.entries) {
          if (emote.key == insertEmote) {
            isUnique = false;
            break;
          }
        }
        if (!isUnique) {
          break;
        }
      }
      insertText = ':${isUnique ? '' : '${insertPack!}~'}$insertEmote: ';
      startText = replaceText.replaceAllMapped(
        RegExp(r'(\s|^)(:(?:[-\w]+~)?[-\w]+)$'),
        (Match m) => '${m[1]}$insertText',
      );
    }
    if (suggestion['type'] == 'user') {
      insertText = '${suggestion['mention']!} ';
      startText = replaceText.replaceAllMapped(
        RegExp(r'(\s|^)(@[-\w]+)$'),
        (Match m) => '${m[1]}$insertText',
      );
    }
    if (suggestion['type'] == 'room') {
      insertText = '${suggestion['mxid']!} ';
      startText = replaceText.replaceAllMapped(
        RegExp(r'(\s|^)(#[-\w]+)$'),
        (Match m) => '${m[1]}$insertText',
      );
    }

    return startText + afterText;
  }

  /// On Windows, gives [field] the keys that open its native menu.
  Widget _withNativeMenuShortcuts(
    BuildContext context,
    TextEditingController controller,
    FocusNode focusNode,
    Widget field,
  ) {
    if (!NativeContextMenu.isSupported) return field;
    return NativeComposerMenuShortcuts(
      focusNode: focusNode,
      dictionary: messageSpellCheckDictionary(),
      extraItems: () => markdownButtonItems(context, controller: controller),
      child: field,
    );
  }

  @override
  Widget build(BuildContext context) {
    return Autocomplete<Map<String, String?>>(
      key: Key('chat_input_field'),
      focusNode: focusNode,
      textEditingController: controller,
      optionsBuilder: getSuggestions,
      fieldViewBuilder: (context, controller, focusNode, _) => _InputTextScale(
        child: _withNativeMenuShortcuts(
          context,
          controller,
          focusNode,
          TextField(
            controller: controller,
            focusNode: focusNode,
            undoController: undoController,
            spellCheckConfiguration: messageSpellCheckConfiguration(),
            readOnly: readOnly,
            onEditingComplete: () {
              // To not lose focus on iOS:
              // https://github.com/krille-chan/fluffychat/issues/2784
            },
            contextMenuBuilder: (c, e) => NativeContextMenu.isSupported
                ? NativeComposerMenu(
                    composerContext: context,
                    editableTextState: e,
                    dictionary: messageSpellCheckDictionary(),
                    extraItems: () =>
                        markdownButtonItems(context, controller: controller),
                  )
                : MarkdownContextBuilder(
                    editableTextState: e,
                    controller: controller,
                    onPasteImage: PlatformInfos.isIOS && onSubmitImage != null
                        ? () async {
                            final scaffoldMessenger = ScaffoldMessenger.of(
                              context,
                            );
                            final l10n = L10n.of(context);
                            final image = await Pasteboard.image;
                            if (image == null) {
                              scaffoldMessenger.showSnackBar(
                                SnackBar(
                                  content: Text(l10n.noImageInClipboard),
                                ),
                              );
                              return;
                            }
                            onSubmitImage!(image);
                          }
                        : null,
                  ),
            contentInsertionConfiguration: ContentInsertionConfiguration(
              onContentInserted: (KeyboardInsertedContent content) async {
                final proceed = await showTrustUserInRoomDialog(context, room);
                if (!proceed) return;
                final data = content.data;
                if (data == null) return;
                final onInsertFile = this.onInsertFile;
                if (onInsertFile != null) {
                  onInsertFile(
                    insertedContentFile(data, content.uri, content.mimeType),
                  );
                  return;
                }

                final file = MatrixFile(
                  mimeType: content.mimeType,
                  bytes: data,
                  name: insertedContentFileName(content.uri, content.mimeType),
                );
                if (!context.mounted) return;
                final scaffoldMessenger = ScaffoldMessenger.of(context);
                final AdaptedMedia adapted;
                try {
                  adapted = await adaptMediaForRoom(
                    features: await RoomFeatures.load(room),
                    file: file,
                  );
                } on Exception catch (e) {
                  if (!context.mounted) return;
                  scaffoldMessenger.showSnackBar(
                    SnackBar(content: Text(e.toLocalizedString(context))),
                  );
                  return;
                }
                room.sendFileEvent(
                  adapted.file,
                  shrinkImageMaxDimension: 1600,
                  extraContent: adapted.extraContent,
                );
              },
            ),
            minLines: minLines,
            maxLines: maxLines,
            keyboardType: keyboardType,
            textInputAction: textInputAction,
            autofocus: autofocus!,
            inputFormatters: [
              ?emoticonFormatter,
              LengthLimitingTextInputFormatter((maxPDUSize / 3).floor()),
            ],
            onSubmitted: (text) {
              // fix for library for now
              // it sets the types for the callback incorrectly
              onSubmitted!(text);
            },
            maxLength: AppSettings.textMessageMaxLength.value,
            decoration: decoration,
            onChanged: (text) {
              // fix for the library for now
              // it sets the types for the callback incorrectly
              onChanged!(text);
            },
            textCapitalization: TextCapitalization.sentences,
          ),
        ),
      ),
      optionsViewBuilder: (c, onSelected, s) => _SuggestionList(
        suggestions: s.toList(),
        onSelected: onSelected,
        owner: suggestions,
        buildRow: (context, suggestion, highlighted) => buildSuggestion(
          context,
          suggestion,
          onSelected,
          Matrix.of(context).client,
          highlighted: highlighted,
        ),
      ),
      displayStringForOption: insertSuggestion,
      optionsViewOpenDirection: OptionsViewOpenDirection.up,
    );
  }
}

/// Applies the chat font size setting to the composer.
///
/// Copying the whole [MediaQueryData] depends on all of it, keyboard insets
/// included. Doing that here rather than in the autocomplete's field builder
/// means a change to the media query rebuilds only this widget, and the text
/// field passed in as [child] is reused as is.
class _InputTextScale extends StatelessWidget {
  final Widget child;

  const _InputTextScale({required this.child});

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(AppSettings.fontSizeFactor.value)),
    child: child,
  );
}

/// The composer's suggestions, as a compact Material menu just above it:
/// at most six 44 high rows on the surface container, 16 corners, as wide
/// as the composer on a phone and up to 360 beside it on a wide screen.
/// Up and Down move the highlight, Enter or Tab picks it (through [owner]),
/// Escape closes the list.
class _SuggestionList extends StatefulWidget {
  final List<Map<String, String?>> suggestions;
  final void Function(Map<String, String?>) onSelected;
  final ComposerSuggestions? owner;
  final Widget Function(
    BuildContext context,
    Map<String, String?> suggestion,
    bool highlighted,
  )
  buildRow;

  const _SuggestionList({
    required this.suggestions,
    required this.onSelected,
    required this.owner,
    required this.buildRow,
  });

  @override
  State<_SuggestionList> createState() => _SuggestionListState();
}

class _SuggestionListState extends State<_SuggestionList> {
  final _scroll = ScrollController();

  void _pick() {
    final index = AutocompleteHighlightedOption.of(context);
    if (index < widget.suggestions.length) {
      widget.onSelected(widget.suggestions[index]);
    }
  }

  @override
  void initState() {
    super.initState();
    widget.owner?._pick = _pick;
  }

  @override
  void dispose() {
    if (widget.owner?._pick == _pick) widget.owner?._pick = null;
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls the highlighted row into view as Up and Down move it.
  void _reveal(int index) {
    if (!_scroll.hasClients) return;
    final top = index * _suggestionRowHeight + 8;
    final position = _scroll.position;
    if (top < position.pixels) {
      _scroll.jumpTo(top - 8);
    } else if (top + _suggestionRowHeight >
        position.pixels + position.viewportDimension) {
      _scroll.jumpTo(
        top + _suggestionRowHeight + 8 - position.viewportDimension,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final highlighted = AutocompleteHighlightedOption.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _reveal(highlighted);
    });
    return Align(
      alignment: AlignmentDirectional.bottomStart,
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: FluffyThemes.isColumnMode(context) ? 360 : double.infinity,
          maxHeight: _visibleSuggestions * _suggestionRowHeight + 16,
        ),
        child: Padding(
          padding: const EdgeInsets.only(bottom: 8),
          child: Material(
            color: theme.colorScheme.surfaceContainerHigh,
            elevation: 2,
            shadowColor: theme.colorScheme.shadow,
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.all(Radius.circular(16)),
            ),
            clipBehavior: Clip.antiAlias,
            child: ListView.builder(
              controller: _scroll,
              padding: const EdgeInsets.symmetric(vertical: 8),
              shrinkWrap: true,
              itemExtent: _suggestionRowHeight,
              itemCount: widget.suggestions.length,
              itemBuilder: (context, i) => widget.buildRow(
                context,
                widget.suggestions[i],
                i == highlighted,
              ),
            ),
          ),
        ),
      ),
    );
  }
}
