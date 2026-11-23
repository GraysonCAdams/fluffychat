// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

@TestOn('vm')
library;

import 'dart:io';

import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';
import 'package:fluffychat/utils/message_search/local_message_index.dart';
import 'package:fluffychat/utils/message_search/message_search_indexer.dart';
import 'package:fluffychat/utils/message_search/search_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;

import 'search_test_client.dart';

/// Runs the indexer against a real SDK client: its database on disk, and the
/// events of the SDK's fake homeserver.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory directory;
  late Client client;
  late MessageSearchIndexer indexer;

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('indexer_test');
    client = await createSearchTestClient(
      databasePath: '${directory.path}/account.sqlite',
    );
    // What the database builder records when it opens a database without a
    // key.
    databaseCiphers[client.clientName] = null;
    indexer = MessageSearchIndexer.of(client);
  });

  tearDown(() async {
    databaseCiphers.remove(client.clientName);
    // A search starts a scan it does not wait for. Let it end before the
    // files go away.
    await indexer.catchUp();
    await (await indexer.index)?.close();
    await client.dispose();
    await directory.delete(recursive: true);
  });

  Future<List<String>> find(String text) async {
    final page = await LocalMessageSearch(
      indexer,
    ).search(SearchQuery.parse(text)!);
    return [for (final hit in page.hits) hit.eventId];
  }

  test('keeps the index beside the SDK database', () {
    expect(
      p.equals(
        LocalMessageIndex.pathFor(client)!,
        '${directory.path}/account.search.sqlite',
      ),
      isTrue,
    );
  });

  test('without a recorded database key there is no index', () async {
    databaseCiphers.remove(client.clientName);
    indexer.start();
    expect(await indexer.index, isNull);
    expect(await find('fish'), isEmpty);
    expect(
      File('${directory.path}/account.search.sqlite').existsSync(),
      isFalse,
    );
  });

  test('indexes what the SDK stored before the indexer started', () async {
    indexer.start();
    await indexer.catchUp();
    final hits = await find('fish');
    expect(hits, isNotEmpty);
    final stats = await indexer.stats();
    expect(stats!.messages, greaterThanOrEqualTo(hits.length));
    expect(stats.bytes, greaterThan(0));
  });

  test('indexes a message that arrives while running', () async {
    indexer.start();
    await indexer.catchUp();
    expect(await find('naveen'), isEmpty);

    final room = client.rooms.firstWhere((room) => !room.isSpace);
    await client.handleSync(
      SyncUpdate(
        nextBatch: 'after-live-message',
        rooms: RoomsUpdate(
          join: {
            room.id: JoinedRoomUpdate(
              timeline: TimelineUpdate(
                events: [
                  MatrixEvent(
                    type: EventTypes.Message,
                    eventId: r'$live',
                    senderId: '@alice:example.com',
                    originServerTs: DateTime.now(),
                    content: {'msgtype': 'm.text', 'body': 'Naveen says hi'},
                  ),
                ],
              ),
            ),
          },
        ),
      ),
    );
    await indexer.flush();
    // Looked up in the index directly, so that the find below cannot be the
    // work of the scanner.
    final page = await (await indexer.index)!.search(
      SearchQuery.parse('naveen')!,
    );
    expect(page.hits.single.eventId, r'$live');
    expect(page.hits.single.roomId, room.id);
  });

  test('rebuild fills an emptied index again', () async {
    indexer.start();
    await indexer.catchUp();
    final before = await find('fish');
    expect(before, isNotEmpty);

    // Let the scan that the search above started end, then look into the
    // index directly: a search through the indexer would start the next
    // scan, which fills the index again.
    await indexer.catchUp();
    final index = (await indexer.index)!;
    await index.clear();
    expect((await index.search(SearchQuery.parse('fish')!)).hits, isEmpty);
    await indexer.rebuild();
    expect(await find('fish'), before);
  });

  test('logging out deletes the index', () async {
    indexer.start();
    await indexer.catchUp();
    final file = File('${directory.path}/account.search.sqlite');
    expect(file.existsSync(), isTrue);

    await client.logout();
    // The indexer reacts to the login state stream, which delivers after
    // logout has returned.
    for (var i = 0; i < 50 && file.existsSync(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    expect(file.existsSync(), isFalse);
    expect(await find('fish'), isEmpty);
  });
}
