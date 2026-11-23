// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/message_search/search_query.dart';
import 'package:fluffychat/utils/message_search/server_message_search.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

/// A response in the shape Synapse sends for `order_by: recent` with
/// `event_context.include_profile`.
Map<String, Object?> searchResponse({
  required List<Map<String, Object?>> events,
  String? nextBatch,
  List<String> highlights = const [],
}) => {
  'search_categories': {
    'room_events': {
      'count': events.length,
      'highlights': highlights,
      'next_batch': ?nextBatch,
      'results': [
        for (final event in events)
          {
            'rank': 0.5,
            'result': event,
            'context': {
              'events_before': <Object?>[],
              'events_after': <Object?>[],
              'profile_info': {
                '@naveen:example.org': {
                  'displayname': 'Naveen',
                  'avatar_url': 'mxc://example.org/naveen',
                },
              },
            },
          },
      ],
    },
  },
};

Map<String, Object?> message(
  String eventId,
  int ts, {
  String type = 'm.room.message',
  Map<String, Object?>? content,
}) => {
  'type': type,
  'event_id': eventId,
  'room_id': '!room:example.org',
  'sender': '@naveen:example.org',
  'origin_server_ts': ts,
  'content': content ?? {'msgtype': 'm.text', 'body': 'body of $eventId'},
};

void main() {
  final query = SearchQuery.parse('Naveen dinner')!;

  group('pageFromSearchResults', () {
    test('maps events, sender profile, highlights and the next batch', () {
      final page = pageFromSearchResults(
        SearchResults.fromJson(
          searchResponse(
            events: [message(r'$a', 2000), message(r'$b', 1000)],
            nextBatch: 'batch2',
            highlights: ['naveen', 'dinner'],
          ),
        ),
      );
      expect(page.hits.map((h) => h.eventId), [r'$a', r'$b']);
      final hit = page.hits.first;
      expect(hit.roomId, '!room:example.org');
      expect(hit.senderId, '@naveen:example.org');
      expect(hit.senderName, 'Naveen');
      expect(hit.senderAvatar, Uri.parse('mxc://example.org/naveen'));
      expect(hit.body, r'body of $a');
      expect(hit.timestamp, DateTime.fromMillisecondsSinceEpoch(2000));
      expect(page.nextCursor, 'batch2');
      expect(page.highlights, ['naveen', 'dinner']);
    });

    test('leaves out results a tile cannot show', () {
      final page = pageFromSearchResults(
        SearchResults.fromJson(
          searchResponse(
            events: [
              message(r'$redacted', 3000, content: {}),
              message(r'$topic', 2000, type: 'm.room.topic'),
              message(r'$ok', 1000),
            ],
          ),
        ),
      );
      expect(page.hits.map((h) => h.eventId), [r'$ok']);
      expect(page.nextCursor, isNull);
    });

    test('a response without the room_events category is an empty page', () {
      final page = pageFromSearchResults(
        SearchResults.fromJson({'search_categories': <String, Object?>{}}),
      );
      expect(page.hits, isEmpty);
      expect(page.nextCursor, isNull);
    });
  });

  group('ServerMessageSearch', () {
    test(
      'asks for recent-first message bodies and passes the cursor on',
      () async {
        final requests = <(Map<String, Object?>, String?)>[];
        final search = ServerMessageSearch.withCall((
          categories, {
          nextBatch,
        }) async {
          requests.add((categories.toJson(), nextBatch));
          return SearchResults.fromJson(
            searchResponse(
              events: [message(r'$a', 2000)],
              nextBatch: nextBatch == null ? 'batch2' : null,
            ),
          );
        }, pageSize: 7);

        final first = await search.search(query);
        final second = await search.search(query, cursor: first.nextCursor);

        expect(requests.map((r) => r.$2), [null, 'batch2']);
        expect(second.nextCursor, isNull);
        final criteria = requests.first.$1['room_events']! as Map;
        expect(criteria['search_term'], 'Naveen dinner');
        expect(criteria['order_by'], 'recent');
        expect(criteria['keys'], ['content.body']);
        expect(criteria['filter'], {'limit': 7});
        expect(criteria['event_context'], {
          'after_limit': 0,
          'before_limit': 0,
          'include_profile': true,
        });
      },
    );

    test('a homeserver without the endpoint is asked only once', () async {
      var calls = 0;
      final search = ServerMessageSearch.withCall((
        categories, {
        nextBatch,
      }) async {
        calls++;
        throw MatrixException.fromJson({
          'errcode': 'M_UNRECOGNIZED',
          'error': 'Unrecognized request',
        });
      });

      expect((await search.search(query)).hits, isEmpty);
      expect(search.unsupported, isTrue);
      expect((await search.search(query)).hits, isEmpty);
      expect(calls, 1);
    });

    test('other errors reach the caller and are retried next time', () async {
      var calls = 0;
      final search = ServerMessageSearch.withCall((
        categories, {
        nextBatch,
      }) async {
        calls++;
        throw MatrixException.fromJson({
          'errcode': 'M_LIMIT_EXCEEDED',
          'error': 'Too many requests',
        });
      });

      await expectLater(search.search(query), throwsA(isA<MatrixException>()));
      await expectLater(search.search(query), throwsA(isA<MatrixException>()));
      expect(search.unsupported, isFalse);
      expect(calls, 2);
    });
  });
}
