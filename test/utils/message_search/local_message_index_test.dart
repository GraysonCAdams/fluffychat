// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/utils/message_search/index_operation.dart';
import 'package:fluffychat/utils/message_search/local_message_index_io.dart';
import 'package:fluffychat/utils/message_search/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

IndexMessage message(
  String eventId,
  String body, {
  int ts = 1700000000000,
  int editTs = 0,
  String roomId = '!room:example.org',
}) => IndexMessage(
  eventId: eventId,
  roomId: roomId,
  senderId: '@naveen:example.org',
  timestamp: ts,
  body: body,
  editTimestamp: editTs,
);

void main() {
  late Directory directory;
  late LocalMessageIndex index;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('message_index_test');
    index = (await LocalMessageIndex.open('${directory.path}/index.sqlite'))!;
  });

  tearDown(() async {
    await index.close();
    await directory.delete(recursive: true);
  });

  Future<List<String>> find(String text, {int? before, int limit = 30}) async {
    final page = await index.search(
      SearchQuery.parse(text)!,
      before: before,
      limit: limit,
    );
    return [for (final hit in page.hits) hit.eventId];
  }

  test('finds a message by a word and returns its fields', () async {
    await index.apply([
      message(r'$a', 'Dinner with Naveen tonight'),
      message(r'$b', 'Lunch tomorrow'),
    ]);
    final page = await index.search(SearchQuery.parse('naveen')!);
    final hit = page.hits.single;
    expect(hit.eventId, r'$a');
    expect(hit.roomId, '!room:example.org');
    expect(hit.senderId, '@naveen:example.org');
    expect(hit.body, 'Dinner with Naveen tonight');
    expect(hit.timestamp, DateTime.fromMillisecondsSinceEpoch(1700000000000));
    expect(page.nextCursor, isNull);
  });

  test('matches word beginnings, every term, any case, any accent', () async {
    await index.apply([
      message(r'$a', 'Dinner with Naveen tonight'),
      message(r'$b', 'Naveen is late'),
      message(r'$c', 'Meet at the Café'),
    ]);
    expect(await find('nav'), unorderedEquals([r'$a', r'$b']));
    expect(await find('NAVEEN din'), [r'$a']);
    expect(await find('aveen'), isEmpty);
    expect(await find('cafe'), [r'$c']);
  });

  test('input with FTS syntax is searched as plain words', () async {
    await index.apply([message(r'$a', 'this or that'), message(r'$b', 'this')]);
    // Read as FTS5 syntax, OR would let the second message match as well.
    expect(await find('this" OR that*'), [r'$a']);
  });

  test('returns the newest messages first and pages without gaps', () async {
    await index.apply([
      for (var i = 0; i < 25; i++)
        message('\$e$i', 'hello number $i', ts: 1700000000000 + i * 1000),
    ]);
    final seen = <String>[];
    int? cursor;
    var pages = 0;
    do {
      final page = await index.search(
        SearchQuery.parse('hello')!,
        before: cursor,
        limit: 10,
      );
      seen.addAll(page.hits.map((hit) => hit.eventId));
      cursor = page.nextCursor as int?;
      pages++;
    } while (cursor != null);
    expect(pages, 3);
    expect(seen, [for (var i = 24; i >= 0; i--) '\$e$i']);
  });

  test('messages sharing a timestamp and a row ID are all kept', () async {
    // Find two event IDs whose preferred row ID is the same.
    final byId = <int, String>{};
    late String first, second;
    for (var i = 0; ; i++) {
      final eventId = '\$collide$i';
      final id = LocalMessageIndex.baseId(eventId, 1700000000000);
      final other = byId[id];
      if (other != null) {
        first = other;
        second = eventId;
        break;
      }
      byId[id] = eventId;
    }
    await index.apply([
      message(first, 'twin one'),
      message(second, 'twin two'),
      message(r'$third', 'twin three', ts: 1700000000001),
    ]);
    expect(await find('twin'), unorderedEquals([first, second, r'$third']));
    expect((await find('twin')).first, r'$third');
    expect((await index.stats()).messages, 3);
  });

  test('indexing an event again does not duplicate it', () async {
    await index.apply([message(r'$a', 'hello')]);
    await index.apply([message(r'$a', 'hello')]);
    expect(await find('hello'), [r'$a']);
    expect((await index.stats()).messages, 1);
  });

  test('an edit replaces the searchable text', () async {
    await index.apply([message(r'$a', 'Dinner with Naveen')]);
    await index.apply([message(r'$a', 'Lunch with Priya', editTs: 5)]);
    expect(await find('naveen'), isEmpty);
    expect(await find('dinner'), isEmpty);
    expect(await find('priya'), [r'$a']);
  });

  test('the newest edit wins whatever order events are indexed in', () async {
    await index.apply([message(r'$a', 'third wording', editTs: 30)]);
    await index.apply([message(r'$a', 'second wording', editTs: 20)]);
    await index.apply([message(r'$a', 'first wording')]);
    expect(await find('third'), [r'$a']);
    expect(await find('second'), isEmpty);
    expect(await find('first'), isEmpty);
  });

  test('a redacted message is no longer found', () async {
    await index.apply([message(r'$a', 'secret plan'), message(r'$b', 'plan')]);
    await index.apply([const RemoveMessage(r'$a')]);
    expect(await find('plan'), [r'$b']);
    expect(await find('secret'), isEmpty);
    // Removing something unknown is not an error.
    await index.apply([const RemoveMessage(r'$never-seen')]);
  });

  test('stores the watermark together with the messages', () async {
    expect(await index.watermark, 0);
    await index.apply([message(r'$a', 'hello')], watermark: 41);
    expect(await index.watermark, 41);
    await index.apply(const [], watermark: 42);
    expect(await index.watermark, 42);
  });

  test('forgets a room without touching the others', () async {
    await index.apply([
      message(r'$a', 'hello', roomId: '!one:example.org'),
      message(r'$b', 'hello', roomId: '!two:example.org'),
    ]);
    expect(
      await index.roomIds(),
      unorderedEquals(['!one:example.org', '!two:example.org']),
    );
    await index.removeRoom('!one:example.org');
    expect(await find('hello'), [r'$b']);
    expect(await index.roomIds(), ['!two:example.org']);
  });

  test('keeps its content across reopening', () async {
    await index.apply([message(r'$a', 'hello')], watermark: 7);
    await index.close();
    index = (await LocalMessageIndex.open('${directory.path}/index.sqlite'))!;
    expect(await find('hello'), [r'$a']);
    expect(await index.watermark, 7);
  });

  test('clear empties the index and resets the watermark', () async {
    await index.apply([
      for (var i = 0; i < 500; i++) message('\$e$i', 'hello filler text $i'),
    ], watermark: 500);
    final before = await index.stats();
    expect(before.messages, 500);
    expect(before.bytes, greaterThan(0));

    await index.clear();
    final after = await index.stats();
    expect(after.messages, 0);
    expect(after.bytes, lessThan(before.bytes));
    expect(await index.watermark, 0);
    expect(await find('hello'), isEmpty);

    await index.apply([message(r'$new', 'hello again')]);
    expect(await find('hello'), [r'$new']);
  });

  test('delete removes the files', () async {
    await index.apply([message(r'$a', 'hello')]);
    await index.delete();
    expect(directory.listSync().map((entry) => entry.path), isEmpty);
    // tearDown closes the index again, which needs one to be open.
    index = (await LocalMessageIndex.open('${directory.path}/index.sqlite'))!;
  });

  group('with a database key', () {
    bool fileContains(String path, String text) {
      final needle = utf8.encode(text);
      for (final suffix in ['', '-wal']) {
        final file = File('$path$suffix');
        if (!file.existsSync()) continue;
        final bytes = file.readAsBytesSync();
        outer:
        for (var i = 0; i + needle.length <= bytes.length; i++) {
          for (var j = 0; j < needle.length; j++) {
            if (bytes[i + j] != needle[j]) continue outer;
          }
          return true;
        }
      }
      return false;
    }

    test('message text is not readable in the file', () async {
      final path = '${directory.path}/encrypted.sqlite';
      final encrypted = (await LocalMessageIndex.open(path, cipher: 'key'))!;
      await encrypted.apply([message(r'$a', 'Dinner with Naveen')]);
      expect(
        (await encrypted.search(SearchQuery.parse('naveen')!)).hits,
        hasLength(1),
      );
      await encrypted.close();
      expect(fileContains(path, 'Naveen'), isFalse);

      // The same check on the index without a key finds the text, so the
      // check above does look in the right place.
      await index.apply([message(r'$a', 'Dinner with Naveen')]);
      await index.close();
      expect(fileContains('${directory.path}/index.sqlite', 'Naveen'), isTrue);
      index = (await LocalMessageIndex.open('${directory.path}/index.sqlite'))!;
    });

    test('cannot be opened with another key', () async {
      final path = '${directory.path}/encrypted.sqlite';
      final encrypted = (await LocalMessageIndex.open(path, cipher: 'key'))!;
      await encrypted.apply([message(r'$a', 'hello')]);
      await encrypted.close();
      expect(await LocalMessageIndex.open(path, cipher: 'other'), isNull);
    });
  });
}
