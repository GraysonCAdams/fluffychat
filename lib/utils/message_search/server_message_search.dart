// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

import 'message_search_hit.dart';
import 'message_search_source.dart';
import 'search_query.dart';

/// The call behind `POST /_matrix/client/v3/search`, as [Client.search]
/// offers it.
typedef MatrixSearchCall =
    Future<SearchResults> Function(Categories categories, {String? nextBatch});

/// Searches message text on the homeserver.
///
/// The homeserver only knows the text of unencrypted rooms the user is in.
/// Encrypted rooms are covered by the local index instead.
class ServerMessageSearch extends MessageSearchSource {
  final MatrixSearchCall _search;

  /// Kept small on purpose: the homeserver looks up the sender profile for
  /// every result, and the response is decoded on the UI isolate.
  final int pageSize;

  ServerMessageSearch(Client client, {this.pageSize = 20})
    : _search = client.search;

  ServerMessageSearch.withCall(this._search, {this.pageSize = 20});

  /// Set once the homeserver answered that it has no search endpoint. Asking
  /// again on every keystroke would only produce the same error.
  bool get unsupported => _unsupported;
  bool _unsupported = false;

  @override
  Future<MessageSearchPage> search(SearchQuery query, {Object? cursor}) async {
    if (_unsupported) return MessageSearchPage.empty;
    final SearchResults response;
    try {
      response = await _search(
        Categories(
          roomEvents: RoomEventsCriteria(
            searchTerm: query.text,
            keys: [KeyKind.contentBody],
            orderBy: SearchOrder.recent,
            filter: SearchFilter(limit: pageSize),
            // No surrounding events: a result tile shows the message alone.
            // The context is still requested because it is the only way to
            // get the sender's name and avatar for a room whose members are
            // not loaded.
            eventContext: IncludeEventContext(
              beforeLimit: 0,
              afterLimit: 0,
              includeProfile: true,
            ),
          ),
        ),
        nextBatch: cursor as String?,
      );
    } on MatrixException catch (e) {
      if (_meansUnsupported(e)) {
        _unsupported = true;
        Logs().i('Homeserver does not offer message search: ${e.errcode}');
        return MessageSearchPage.empty;
      }
      rethrow;
    }
    return pageFromSearchResults(response);
  }

  /// The specification asks servers to answer unknown endpoints with
  /// `M_UNRECOGNIZED`. `M_NOT_FOUND` is what some send instead, and this
  /// endpoint has no resource that could be "not found" otherwise.
  static bool _meansUnsupported(MatrixException e) {
    if (e.error == MatrixError.M_UNRECOGNIZED ||
        e.error == MatrixError.M_NOT_FOUND) {
      return true;
    }
    final status = e.response?.statusCode;
    return status == 404 || status == 405 || status == 501;
  }
}

/// Turns the homeserver's answer into hits.
///
/// Results that are not text messages any more (redacted, or of a type the
/// tile cannot show) are left out.
MessageSearchPage pageFromSearchResults(SearchResults response) {
  final roomEvents = response.searchCategories.roomEvents;
  if (roomEvents == null) return MessageSearchPage.empty;
  final hits = <MessageSearchHit>[];
  for (final result in roomEvents.results ?? const <Result>[]) {
    final event = result.result;
    if (event == null || event.type != EventTypes.Message) continue;
    final roomId = event.roomId;
    final body = event.content.tryGet<String>('body');
    if (roomId == null || body == null || body.isEmpty) continue;
    final profile = result.context?.profileInfo?[event.senderId];
    hits.add(
      MessageSearchHit(
        eventId: event.eventId,
        roomId: roomId,
        senderId: event.senderId,
        senderName: profile?.displayname,
        senderAvatar: profile?.avatarUrl,
        body: body,
        timestamp: event.originServerTs,
        msgtype: event.content.tryGet<String>('msgtype'),
      ),
    );
  }
  return MessageSearchPage(
    hits: hits,
    nextCursor: roomEvents.nextBatch,
    highlights: roomEvents.highlights ?? const [],
  );
}
