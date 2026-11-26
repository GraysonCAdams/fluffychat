// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/search_title.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/message_search/message_search_controller.dart';
import 'package:fluffychat/utils/message_search/message_search_hit.dart';
import 'package:fluffychat/utils/message_search/message_search_indexer.dart';
import 'package:fluffychat/utils/message_search/message_search_source.dart';
import 'package:fluffychat/utils/message_search/server_message_search.dart';
import 'package:fluffychat/utils/message_search/snippet.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The "Messages" section of the chat list search: messages from all chats
/// that contain the text in [searchField].
///
/// A sliver, meant to sit in the chat list's scroll view below the chats.
/// It searches by itself whenever the field changes, so the page showing it
/// only has to build it while the search is open.
class MessageSearchResults extends StatefulWidget {
  final Client client;

  /// The search field of the chat list.
  final TextEditingController searchField;

  /// Stand-in for the homeserver search and the local index, for tests.
  final List<MessageSearchSource>? sources;

  const MessageSearchResults({
    required this.client,
    required this.searchField,
    this.sources,
    super.key,
  });

  @override
  State<MessageSearchResults> createState() => _MessageSearchResultsState();
}

class _MessageSearchResultsState extends State<MessageSearchResults> {
  late MessageSearchController _search;

  @override
  void initState() {
    super.initState();
    _search = _createController();
    widget.searchField.addListener(_onInput);
    _onInput();
  }

  @override
  void didUpdateWidget(MessageSearchResults oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Another account has its own homeserver and its own index.
    if (oldWidget.client != widget.client) {
      _search.dispose();
      _search = _createController();
      // Nothing listens to the new controller before the coming build, so
      // it can take the input right away.
      _onInput();
    }
    if (oldWidget.searchField != widget.searchField) {
      oldWidget.searchField.removeListener(_onInput);
      widget.searchField.addListener(_onInput);
      // The controller notifies its listeners, which must not happen while
      // this widget is being rebuilt.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _onInput();
      });
    }
  }

  @override
  void dispose() {
    widget.searchField.removeListener(_onInput);
    _search.dispose();
    super.dispose();
  }

  MessageSearchController _createController() => MessageSearchController(
    widget.sources ??
        [
          LocalMessageSearch(MessageSearchIndexer.of(widget.client)),
          ServerMessageSearch(widget.client),
        ],
  );

  /// The field notifies on every change, including a moved cursor. The
  /// controller ignores input that leaves the query as it is.
  void _onInput() => _search.setInput(widget.searchField.text);

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: _search,
      builder: (context, _) {
        if (_search.query == null) {
          return const SliverToBoxAdapter(child: SizedBox.shrink());
        }
        final l10n = L10n.of(context);
        final theme = Theme.of(context);
        // A hit can name a room the account has left since the message was
        // indexed. There is no chat to open for it.
        final hits = [
          for (final hit in _search.hits)
            if (widget.client.getRoomById(hit.roomId) case final room?)
              (hit, room),
        ];
        final String? status;
        if (hits.isNotEmpty || _search.isLoading) {
          status = null;
        } else if (_search.failed) {
          status = l10n.messageSearchFailed;
        } else {
          status = l10n.noMessagesFound;
        }
        return SliverMainAxisGroup(
          slivers: [
            SliverToBoxAdapter(
              child: SearchTitle(
                title: l10n.messages,
                trailing: _search.isLoading
                    ? const SizedBox.square(
                        dimension: 16,
                        child: CircularProgressIndicator.adaptive(
                          strokeWidth: 2,
                        ),
                      )
                    : null,
              ),
            ),
            SliverList.builder(
              itemCount: hits.length,
              itemBuilder: (context, i) => _MessageSearchTile(
                key: ValueKey(hits[i].$1.eventId),
                hit: hits[i].$1,
                room: hits[i].$2,
                highlights: _search.highlights,
              ),
            ),
            if (status != null)
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Text(
                    status,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            if (_search.hasMore)
              SliverToBoxAdapter(
                // A new key for every page that arrived: the footer is built
                // afresh and asks for the next page if it is still in view.
                child: _NextPageTrigger(
                  key: ValueKey(_search.loadedPages),
                  onVisible: _search.loadMore,
                ),
              ),
            SliverPadding(
              padding: EdgeInsets.only(
                bottom: MediaQuery.paddingOf(context).bottom,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// Sits below the loaded results. The list builds it only when the user has
/// scrolled close to the end, which is the moment to fetch the next page.
class _NextPageTrigger extends StatefulWidget {
  final VoidCallback onVisible;

  const _NextPageTrigger({required this.onVisible, super.key});

  @override
  State<_NextPageTrigger> createState() => _NextPageTriggerState();
}

class _NextPageTriggerState extends State<_NextPageTrigger> {
  @override
  void initState() {
    super.initState();
    // Loading notifies the controller's listeners, which is not allowed
    // while the frame that builds this widget is still in progress.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) widget.onVisible();
    });
  }

  @override
  Widget build(BuildContext context) => const Padding(
    padding: EdgeInsets.all(16),
    child: Center(
      child: SizedBox.square(
        dimension: 18,
        child: CircularProgressIndicator.adaptive(strokeWidth: 2),
      ),
    ),
  );
}

class _MessageSearchTile extends StatelessWidget {
  final MessageSearchHit hit;
  final Room room;
  final Set<String> highlights;

  const _MessageSearchTile({
    required this.hit,
    required this.room,
    required this.highlights,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final client = room.client;
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final roomName = room.getLocalizedDisplayname(MatrixLocals(l10n));
    final String sender;
    if (hit.senderId == client.userID) {
      sender = l10n.you;
    } else if (hit.senderId == room.directChatMatrixID) {
      // In a direct chat the room is named after the other person, and that
      // name is known even when the member list is not loaded.
      sender = roomName;
    } else {
      sender =
          hit.senderName ??
          room
              .unsafeGetUserFromMemoryOrFallback(hit.senderId)
              .calcDisplayname();
    }
    final snippet = buildSnippet(hit.body, highlights);

    // A Material three line list item: the chat in body large, the
    // message in body medium, and its time as trailing supporting text in
    // label small, all on the list's 16 insets.
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 16),
      leading: Avatar(mxContent: room.avatar, name: roomName, client: client),
      title: Row(
        children: [
          Expanded(
            child: Text(roomName, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
          const SizedBox(width: 8),
          Text(
            hit.timestamp.localizedTimeShort(context),
            style: theme.textTheme.labelSmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      titleTextStyle: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurface,
      ),
      subtitle: Text.rich(
        TextSpan(
          children: [
            TextSpan(text: '$sender: '),
            ..._highlighted(
              snippet,
              TextStyle(
                color: theme.colorScheme.onSurface,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
      ),
      subtitleTextStyle: theme.textTheme.bodyMedium?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
      onTap: () => context.go(
        '/${Uri(pathSegments: ['rooms', hit.roomId], queryParameters: {'event': hit.eventId})}',
      ),
    );
  }

  static List<TextSpan> _highlighted(MessageSnippet snippet, TextStyle style) {
    final spans = <TextSpan>[];
    var position = 0;
    for (final (start, end) in snippet.highlights) {
      if (start > position) {
        spans.add(TextSpan(text: snippet.text.substring(position, start)));
      }
      spans.add(
        TextSpan(text: snippet.text.substring(start, end), style: style),
      );
      position = end;
    }
    if (position < snippet.text.length) {
      spans.add(TextSpan(text: snippet.text.substring(position)));
    }
    return spans;
  }
}
