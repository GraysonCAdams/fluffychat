// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_filter_menu.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/header_menu.dart';
import 'package:fluffychat/utils/message_search/message_search_hit.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// What the phone's chat list search looks through, picked in the field's
/// Search in menu (see [SearchScopeButton]).
enum SearchScope {
  all(Icons.search),
  chats(Icons.forum_outlined),
  people(Icons.person_outlined),
  messages(Icons.chat_bubble_outline),
  media(Icons.image_outlined),
  links(Icons.link);

  const SearchScope(this.icon);

  /// The icon of this choice in the menu.
  final IconData icon;

  /// The user's own chats whose names match. People lists only one-to-one
  /// chats.
  bool get showsChats => this == all || this == chats || this == people;

  /// The people found in the server's user directory.
  bool get showsDirectory => this == all || this == people;

  /// The rooms and spaces found in the server's room directory.
  bool get showsPublicRooms => this == all || this == chats;

  /// Messages that contain the text. Media and Links keep only some of them
  /// (see [keepsHit]).
  bool get showsMessages =>
      this == all || this == messages || this == media || this == links;

  String label(L10n l10n) => switch (this) {
    all => l10n.all,
    chats => l10n.chats,
    people => l10n.chatListPeople,
    messages => l10n.messages,
    media => l10n.searchScopeMedia,
    links => l10n.searchScopeLinks,
  };

  /// The hint the search field shows while nothing is typed.
  String hint(L10n l10n) => switch (this) {
    all => l10n.searchHintAll,
    chats => l10n.searchHintChats,
    people => l10n.searchHintPeople,
    messages => l10n.searchHintMessages,
    media => l10n.searchHintMedia,
    links => l10n.searchHintLinks,
  };

  /// Whether a found message belongs in this scope's results. Neither the
  /// homeserver's search nor the local index can be asked for only media or
  /// only links, so those are picked out of the text search's results here.
  bool keepsHit(MessageSearchHit hit) => switch (this) {
    media => isMediaHit(hit),
    links => _link.hasMatch(hit.body),
    _ => true,
  };

  static final _link = RegExp(r'(https?://|www\.)\S', caseSensitive: false);

  /// A file name such as "IMG_2041.jpg": the body of a media message is the
  /// name of its file.
  static final _fileName = RegExp(r'^\S+\.[A-Za-z0-9]{2,5}$');

  static const _mediaTypes = {
    MessageTypes.Image,
    MessageTypes.Video,
    MessageTypes.Audio,
    MessageTypes.File,
  };

  /// Whether [hit] is a picture, video, recording or file. The homeserver
  /// reports the message type; the local index does not keep it, so its hits
  /// are judged by their text, which for media is the file's name.
  static bool isMediaHit(MessageSearchHit hit) {
    final type = hit.msgtype;
    if (type != null) return _mediaTypes.contains(type);
    return _fileName.hasMatch(hit.body.trim());
  }
}

/// Whether a listed chat counts as a person for the search: a one-to-one
/// chat, or a contact merged from several.
bool searchChatIsPerson(ChatListController controller, Room room) =>
    controller.mergedContactFor(room) != null || room.isOneToOne;

/// [text] with each case-insensitive match of [query] in [style].
List<TextSpan> highlightMatches(String text, String query, TextStyle style) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return [TextSpan(text: text)];
  final haystack = text.toLowerCase();
  final spans = <TextSpan>[];
  var position = 0;
  while (true) {
    final start = haystack.indexOf(needle, position);
    if (start < 0) break;
    if (start > position) {
      spans.add(TextSpan(text: text.substring(position, start)));
    }
    final end = start + needle.length;
    spans.add(TextSpan(text: text.substring(start, end), style: style));
    position = end;
  }
  if (position < text.length) {
    spans.add(TextSpan(text: text.substring(position)));
  }
  return spans;
}

/// The style of the matched text in search results: bold, in the primary
/// colour.
TextStyle searchMatchStyle(ThemeData theme) =>
    TextStyle(color: theme.colorScheme.primary, fontWeight: FontWeight.bold);

/// Opens the Search in menu under [anchor], with the active scope checked,
/// and narrows the search to the scope picked. The field gets its focus
/// back either way, so the keyboard stays up.
Future<void> showSearchScopeMenu(
  BuildContext anchor,
  ChatListController controller,
) async {
  final l10n = L10n.of(anchor);
  final theme = Theme.of(anchor);
  final navigator = Navigator.of(controller.context);
  final box = anchor.findRenderObject()! as RenderBox;
  final overlay = navigator.overlay!.context.findRenderObject()! as RenderBox;
  final origin = overlay.globalToLocal(
    box.localToGlobal(Offset(0, box.size.height + 4)),
  );
  final picked = await HeaderMenu.show(
    anchor: showSearchScopeMenu,
    navigator: navigator,
    showMenu: () => showMenu<String>(
      context: navigator.context,
      position: RelativeRect.fromLTRB(
        origin.dx,
        origin.dy,
        overlay.size.width - origin.dx,
        0,
      ),
      // The metrics of the chat filter menu, see showChatFilterMenu.
      constraints: const BoxConstraints(minWidth: 112, maxWidth: 280),
      items: [
        PopupMenuItem(
          enabled: false,
          height: 32,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Text(
            l10n.searchInTitle,
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        for (final scope in SearchScope.values)
          chatMenuItem(
            value: scope.name,
            leading: Icon(scope.icon),
            label: scope.label(l10n),
            checked: scope == controller.searchScope,
          ),
      ],
    ),
  );
  if (!controller.mounted) return;
  if (picked != null) {
    controller.setSearchScope(SearchScope.values.byName(picked));
  }
  if (controller.isSearchMode) controller.searchFocusNode.requestFocus();
}

/// The start of the phone's search field: a filter button that opens the
/// Search in menu while the search looks through everything, and a tonal
/// chip naming the scope ("People") once one is picked, which grows out of
/// the button. Both sit concentric with the field's round end: the button's
/// 40 circle state layer and the chip's stadium are centred 24 in from the
/// start of the 48 high field.
class SearchScopeButton extends StatelessWidget {
  final ChatListController controller;

  const SearchScopeButton({required this.controller, super.key});

  /// The chip, for tests.
  static const chipKey = ValueKey('search_scope_chip');

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final scope = controller.searchScope;
    final Widget child;
    if (scope == SearchScope.all) {
      child = IconButton(
        key: const ValueKey('search_scope_button'),
        tooltip: l10n.searchInTitle,
        onPressed: () => showSearchScopeMenu(context, controller),
        icon: const Icon(Icons.filter_list),
      );
    } else {
      final label = scope.label(l10n);
      final foreground = theme.colorScheme.onSecondaryContainer;
      child = Padding(
        key: chipKey,
        padding: const EdgeInsetsDirectional.only(start: 8, end: 4),
        child: Tooltip(
          message: l10n.searchInSelected(label),
          excludeFromSemantics: true,
          child: Semantics(
            button: true,
            label: l10n.searchInSelected(label),
            child: GestureDetector(
              // The chip is 32 high; the 8 above and below it take taps
              // too, for a 48 high target.
              behavior: HitTestBehavior.opaque,
              excludeFromSemantics: true,
              onTap: () => showSearchScopeMenu(context, controller),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: Material(
                  color: theme.colorScheme.secondaryContainer,
                  shape: const StadiumBorder(),
                  child: InkWell(
                    customBorder: const StadiumBorder(),
                    excludeFromSemantics: true,
                    onTap: () => showSearchScopeMenu(context, controller),
                    child: ExcludeSemantics(
                      child: SizedBox(
                        height: 32,
                        child: Padding(
                          padding: const EdgeInsetsDirectional.only(
                            start: 8,
                            end: 16,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                Icons.filter_list,
                                size: 18,
                                color: foreground,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                label,
                                style: theme.textTheme.labelLarge?.copyWith(
                                  color: foreground,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    }
    // With animations turned off the chip is simply there.
    if (MediaQuery.disableAnimationsOf(context)) return child;
    const duration = Durations.medium2;
    return AnimatedSize(
      duration: duration,
      curve: Easing.emphasizedDecelerate,
      alignment: AlignmentDirectional.centerStart,
      child: AnimatedSwitcher(
        duration: duration,
        layoutBuilder: (current, previous) => Stack(
          alignment: AlignmentDirectional.centerStart,
          children: [...previous, ?current],
        ),
        child: child,
      ),
    );
  }
}
