// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Measures the local message search over synthetic data. Not part of the
// normal test run, start it with:
//
//   flutter test test/utils/message_search/local_message_index_benchmark_test.dart
//     --dart-define=MESSAGE_SEARCH_BENCHMARK=50000
//
// The number is how many stored events to generate.

// ignore_for_file: avoid_print

@TestOn('vm')
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:fluffychat/utils/message_search/local_message_index_io.dart';
import 'package:fluffychat/utils/message_search/search_query.dart';
import 'package:fluffychat/utils/message_search/stored_event_scanner.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

const eventCount = int.fromEnvironment('MESSAGE_SEARCH_BENCHMARK');
const cipher = 'benchmark-key';

/// Words with a skewed frequency, a little like real text: a few occur in
/// most messages, most occur rarely.
String word(Random random) {
  final u = random.nextDouble();
  return 'w${(u * u * u * 4000).floor().toRadixString(36)}x';
}

String body(Random random, int i) {
  final words = [for (var j = 3 + random.nextInt(18); j > 0; j--) word(random)];
  if (i % 2000 == 7) words.insert(words.length ~/ 2, 'naveen');
  if (i % 3 == 0) words.insert(0, 'the');
  return words.join(' ');
}

Future<String> median(Future<Object?> Function() run) async {
  final micros = <int>[];
  for (var i = 0; i < 9; i++) {
    final watch = Stopwatch()..start();
    await run();
    micros.add(watch.elapsedMicroseconds);
  }
  micros.sort();
  return '${(micros[4] / 1000).toStringAsFixed(1)} ms '
      '(max ${(micros.last / 1000).toStringAsFixed(1)})';
}

void main() {
  test(
    'local message search over $eventCount stored events',
    skip: eventCount == 0 ? 'set MESSAGE_SEARCH_BENCHMARK to run' : null,
    timeout: const Timeout(Duration(minutes: 30)),
    () async {
      final directory = await Directory.systemTemp.createTemp('search_bench');
      addTearDown(() => directory.delete(recursive: true));

      // The SDK database, encrypted like the real one.
      final sdk = await databaseFactoryFfi.openDatabase(
        '${directory.path}/sdk.sqlite',
        options: OpenDatabaseOptions(
          onConfigure: (db) => db.rawQuery("PRAGMA KEY='$cipher'"),
        ),
      );
      addTearDown(sdk.close);
      await sdk.execute(
        'CREATE TABLE box_events (k TEXT PRIMARY KEY NOT NULL, v TEXT)',
      );
      final random = Random(42);
      for (var start = 0; start < eventCount; start += 2000) {
        final batch = sdk.batch();
        for (var i = start; i < min(eventCount, start + 2000); i++) {
          final room = '!room${i % 1000}abcdefghijkl:example.org';
          final id = '\$ev${i}AbCdEfGhIjKlMnOpQrStUvWxYz0123456789abcd';
          batch.insert('box_events', {
            'k': '$room|$id',
            'v': jsonEncode({
              'type': 'm.room.message',
              'event_id': id,
              'room_id': room,
              'sender': '@imessage_${i % 300}:example.org',
              'origin_server_ts': 1600000000000 + i * 60000,
              'content': {'msgtype': 'm.text', 'body': body(random, i)},
              'unsigned': {'age': 1234, 'bridge': 'x' * 40},
              'status': 2,
            }),
          });
        }
        await batch.commit(noResult: true);
      }
      final sdkBytes = File('${directory.path}/sdk.sqlite').lengthSync();
      print('SDK database: $eventCount events, ${sdkBytes ~/ 1024} KiB');

      // Baseline: what a search costs without an index, scanning the stored
      // JSON inside SQLite.
      Future<int> scan(String text) async => (await sdk.rawQuery(
        "SELECT k, json_extract(v, '\$.content.body') AS body, "
        "json_extract(v, '\$.origin_server_ts') AS ts FROM box_events "
        "WHERE v LIKE ?1 AND json_extract(v, '\$.type') = 'm.room.message' "
        "AND json_extract(v, '\$.content.body') LIKE ?1 "
        'ORDER BY ts DESC LIMIT 30',
        ['%$text%'],
      )).length;
      print(
        'Scan of stored events, rare word:   ${await median(() => scan('naveen'))}',
      );
      print(
        'Scan of stored events, common word: ${await median(() => scan('the'))}',
      );

      final index = (await LocalMessageIndex.open(
        '${directory.path}/index.sqlite',
        cipher: cipher,
      ))!;
      addTearDown(index.close);

      // While the index is filled, a timer on this isolate (the stand-in for
      // the UI isolate) records how late it fires. The lateness is how long
      // Dart code or message decoding kept the isolate busy in one go.
      var longestStall = Duration.zero;
      var lastTick = Stopwatch()..start();
      final ticker = Timer.periodic(const Duration(milliseconds: 1), (_) {
        final stall = lastTick.elapsed - const Duration(milliseconds: 1);
        if (stall > longestStall) longestStall = stall;
        lastTick = Stopwatch()..start();
      });
      final fill = Stopwatch()..start();
      await StoredEventScanner(sdk, index).catchUp();
      fill.stop();
      ticker.cancel();
      final stats = await index.stats();
      print(
        'First indexing run: ${fill.elapsedMilliseconds} ms for '
        '${stats.messages} messages, longest stall of the calling isolate '
        '${(longestStall.inMicroseconds / 1000).toStringAsFixed(1)} ms',
      );
      print(
        'Index size: ${stats.bytes ~/ 1024} KiB '
        '(${(100 * stats.bytes / sdkBytes).round()}% of the SDK database)',
      );
      print(
        'Run with nothing new: ${await median(() => StoredEventScanner(sdk, index).catchUp())}',
      );

      Future<int> search(String text) async =>
          (await index.search(SearchQuery.parse(text)!)).hits.length;
      for (final text in [
        'naveen',
        'na',
        'the',
        'w1',
        'w1a',
        'the w1',
        'w9 w8 w7',
        'zzzqqq',
      ]) {
        print(
          'Index search "$text": ${await median(() => search(text))} -> ${await search(text)} hits',
        );
      }
      Future<int> thirdPage() async {
        final query = SearchQuery.parse('the')!;
        var page = await index.search(query);
        page = await index.search(query, before: page.nextCursor as int?);
        page = await index.search(query, before: page.nextCursor as int?);
        return page.hits.length;
      }

      print('Index search "the", pages 1 to 3: ${await median(thirdPage)}');
    },
  );
}
