// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

@TestOn('vm')
library;

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/utils/message_search/local_message_index.dart';
import 'package:fluffychat/utils/message_search/search_query.dart';
import 'package:fluffychat/utils/message_search/stored_event_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const roomId = '!room:example.org';

Map<String, Object?> event(
  String eventId, {
  String type = 'm.room.message',
  Object? content,
  String? body,
  int ts = 1700000000000,
  Map<String, Object?>? unsigned,
  String? redacts,
  int status = 2,
}) => {
  'type': type,
  'event_id': eventId,
  'room_id': roomId,
  'sender': '@naveen:example.org',
  'origin_server_ts': ts,
  'content': content ?? {'msgtype': 'm.text', 'body': body ?? 'hello'},
  'unsigned': ?unsigned,
  'redacts': ?redacts,
  'status': status,
};

void main() {
  late Directory directory;
  late Database sdk;
  late LocalMessageIndex index;
  late StoredEventScanner scanner;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('event_scanner_test');
    sdk = await databaseFactoryFfi.openDatabase('${directory.path}/sdk.sqlite');
    // The table as the SDK's BoxCollection creates it.
    await sdk.execute(
      'CREATE TABLE box_events (k TEXT PRIMARY KEY NOT NULL, v TEXT)',
    );
    index = (await LocalMessageIndex.open('${directory.path}/index.sqlite'))!;
    scanner = StoredEventScanner(sdk, index);
  });

  tearDown(() async {
    await sdk.close();
    await index.close();
    await directory.delete(recursive: true);
  });

  /// Stores an event the way the SDK's box does: keyed by room and event,
  /// replacing the row when the key exists.
  Future<void> store(Map<String, Object?> json) => sdk.insert('box_events', {
    'k': '$roomId|${json['event_id']}',
    'v': jsonEncode(json),
  }, conflictAlgorithm: ConflictAlgorithm.replace);

  Future<List<String>> find(String text) async {
    final page = await index.search(SearchQuery.parse(text)!);
    return [for (final hit in page.hits) hit.eventId];
  }

  test('indexes stored messages and nothing else', () async {
    await store(event(r'$a', body: 'Dinner with Naveen'));
    await store(event(r'$state', type: 'm.room.topic', body: 'Naveen topic'));
    await store(
      event(r'$locked', type: 'm.room.encrypted', content: {'ciphertext': 'x'}),
    );
    await store(event('txn-still-sending', body: 'Naveen unsent', status: 0));
    await store(event(r'$odd', content: {'body': 7}));

    expect(await scanner.catchUp(), isTrue);
    expect(await find('naveen'), [r'$a']);
    expect((await index.stats()).messages, 1);
    expect(await index.watermark, 5);
  });

  test('a second run reads only what was stored since', () async {
    await store(event(r'$a', body: 'first hello'));
    await scanner.catchUp();
    expect(await scanner.catchUp(), isFalse);

    await store(event(r'$b', body: 'second hello', ts: 1700000001000));
    expect(await scanner.catchUp(), isTrue);
    expect(await find('hello'), [r'$b', r'$a']);
  });

  test('reads a large store in steps without losing rows', () async {
    const count = StoredEventScanner.stepSize * 2 + 37;
    final batch = sdk.batch();
    for (var i = 0; i < count; i++) {
      batch.insert('box_events', {
        'k': '$roomId|\$e$i',
        'v': jsonEncode(
          event('\$e$i', body: 'filler $i', ts: 1700000000000 + i),
        ),
      });
    }
    await batch.commit(noResult: true);
    await scanner.catchUp();
    expect((await index.stats()).messages, count);
    expect(await index.watermark, count);
  });

  test('a message decrypted after it was stored is picked up', () async {
    await store(event(r'$old', body: 'older'));
    await store(
      event(r'$late', type: 'm.room.encrypted', content: {'ciphertext': 'x'}),
    );
    await scanner.catchUp();
    expect(await find('naveen'), isEmpty);

    await store(event(r'$late', body: 'Naveen says hi'));
    expect(await scanner.catchUp(), isTrue);
    expect(await find('naveen'), [r'$late']);
  });

  test('an event stored under the row ID of a deleted one is read', () async {
    await store(event(r'$a', body: 'first'));
    await store(event('txn-echo', body: 'echo'));
    await scanner.catchUp();
    final watermark = await index.watermark;

    // The newest row goes away and the next event takes over its row ID,
    // so nothing appears above the watermark.
    await sdk.delete(
      'box_events',
      where: 'k = ?',
      whereArgs: ['$roomId|txn-echo'],
    );
    await store(event(r'$b', body: 'Naveen says hi'));
    final rows = await sdk.rawQuery('SELECT max(rowid) AS r FROM box_events');
    expect(rows.single['r'], watermark);

    // A run before a search does not look below the watermark.
    expect(await scanner.catchUp(rereadRecent: false), isFalse);
    expect(await find('naveen'), isEmpty);

    expect(await scanner.catchUp(), isFalse);
    expect(await find('naveen'), [r'$b']);
  });

  test('a stored redaction removes the message', () async {
    await store(event(r'$a', body: 'secret plan'));
    await store(event(r'$b', body: 'another plan', ts: 1700000001000));
    await scanner.catchUp();
    expect(await find('plan'), [r'$b', r'$a']);

    // The SDK rewrites the redacted event without its content.
    await store(
      event(
        r'$a',
        content: const <String, Object?>{},
        unsigned: {'redacted_because': event(r'$r', type: 'm.room.redaction')},
      ),
    );
    await store(
      event(
        r'$r',
        type: 'm.room.redaction',
        content: const <String, Object?>{},
        redacts: r'$a',
      ),
    );
    await scanner.catchUp();
    expect(await find('plan'), [r'$b']);
  });

  test('a stored edit updates the edited message', () async {
    await store(event(r'$a', body: 'Dinner with Naveen'));
    await store(
      event(
        r'$edit',
        ts: 1700000005000,
        content: {
          'msgtype': 'm.text',
          'body': '* Lunch with Priya',
          'm.new_content': {'msgtype': 'm.text', 'body': 'Lunch with Priya'},
          'm.relates_to': {'rel_type': 'm.replace', 'event_id': r'$a'},
        },
      ),
    );
    await scanner.catchUp();
    expect(await find('priya'), [r'$a']);
    expect(await find('naveen'), isEmpty);
    expect((await index.stats()).messages, 1);
  });

  test('starts over when the SDK emptied its store', () async {
    for (var i = 0; i < 5; i++) {
      await store(event('\$old$i', body: 'old message $i'));
    }
    await scanner.catchUp();
    expect(await index.watermark, 5);

    await sdk.delete('box_events');
    await store(event(r'$new', body: 'fresh message', ts: 1700000009000));
    expect(await scanner.catchUp(), isTrue);
    expect(await find('fresh'), [r'$new']);
    // What was indexed before stays searchable.
    expect(await find('old'), hasLength(5));
    expect(await index.watermark, 1);
  });

  test('an empty store is not an error', () async {
    expect(await scanner.catchUp(), isFalse);
    expect(await index.watermark, 0);
  });

  test('stops between steps when cancelled', () async {
    const count = StoredEventScanner.stepSize * 3;
    final batch = sdk.batch();
    for (var i = 0; i < count; i++) {
      batch.insert('box_events', {
        'k': '$roomId|\$e$i',
        'v': jsonEncode(event('\$e$i', body: 'filler $i')),
      });
    }
    await batch.commit(noResult: true);
    var steps = 0;
    await scanner.catchUp(isCancelled: () => ++steps > 1);
    expect((await index.stats()).messages, StoredEventScanner.stepSize);
    expect(await index.watermark, StoredEventScanner.stepSize);

    // The next run continues where the cancelled one stopped.
    await scanner.catchUp();
    expect((await index.stats()).messages, count);
  });
}
