// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/archive/archive.dart';
import 'package:fluffychat/pages/archive/archive_cache.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/message_search/search_test_client.dart';
import '../chat_list/chat_list_fakes.dart';

/// Holds every `/sync` with `include_leave` until [release], as a homeserver
/// building a large account's initial sync does.
class _SlowArchiveServer extends http.BaseClient {
  final http.Client inner;
  final _gate = Completer<void>();
  int archiveSyncs = 0;

  _SlowArchiveServer(this.inner);

  void release() => _gate.complete();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    if (request.url.path.endsWith('/sync') &&
        request.url.queryParameters['filter']?.contains('include_leave') ==
            true) {
      archiveSyncs++;
      await _gate.future;
      // The SDK varies the timeout to get past Synapse's response cache; the
      // fake homeserver only answers the first one.
      final url = request.url.replace(
        queryParameters: {...request.url.queryParameters, 'timeout': '0'},
      );
      return inner.send(
        http.Request(request.method, url)..headers.addAll(request.headers),
      );
    }
    return inner.send(request);
  }
}

const _leftRoom = '!5345234234:example.com';

void main() {
  late Client client;
  late _SlowArchiveServer server;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    client = await createSearchTestClient();
    server = _SlowArchiveServer(client.httpClient);
    client.httpClient = server;
  });

  tearDown(() => client.dispose(closeDatabase: true));

  test('a stored archive comes back with its rooms and timelines', () async {
    server.release();
    final fresh = await ArchiveCache.refresh(client);
    final stored = (await ArchiveCache.read(client))!;

    expect(
      stored.map((a) => a.room.id),
      orderedEquals(fresh.map((a) => a.room.id)),
    );
    final room = stored.firstWhere((a) => a.room.id == _leftRoom);
    final original = fresh.firstWhere((a) => a.room.id == _leftRoom);
    expect(room.room.membership, Membership.leave);
    expect(room.room.getLocalizedDisplayname(), 'The room name');
    expect(room.room.lastEvent?.eventId, original.room.lastEvent?.eventId);
    expect(
      room.timeline.events.map((e) => e.eventId),
      orderedEquals(original.timeline.events.map((e) => e.eventId)),
    );
    expect(room.timeline.chunk.prevBatch, 't_1234a');
  });

  test(
    'opening the archive twice while loading asks the server once',
    () async {
      final first = ArchiveCache.refresh(client);
      final second = ArchiveCache.refresh(client);
      await Future<void>.delayed(Duration.zero);
      server.release();
      await Future.wait([first, second]);
      expect(server.archiveSyncs, 1);
    },
  );

  testWidgets('the page shows the stored archive before the server answers', (
    tester,
  ) async {
    await tester.runAsync(() async {
      // A previous visit stored the archive.
      server.release();
      await ArchiveCache.refresh(client);
      server = _SlowArchiveServer(server.inner);
      client.httpClient = server;
    });
    final prefs = await SharedPreferences.getInstance();

    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Archive(),
        ),
      ),
    );
    await _pumpUntil(
      tester,
      () => find.text('The room name').evaluate().isNotEmpty,
    );

    expect(find.text('The room name'), findsOneWidget);
    // The server is still being asked.
    expect(server.archiveSyncs, 1);
    expect(find.byType(LinearProgressIndicator), findsOneWidget);

    // Let the database reads ChatListItem started settle before the test ends.
    await tester.pumpWidget(const SizedBox());
    await _pumpUntil(tester, () => false, times: 3);
    await tester.pump(const Duration(seconds: 11));
  });
}

/// Pumps until [done] (at most [times] rounds), letting the database and HTTP futures, which run
/// outside the test's fake clock, complete in between.
Future<void> _pumpUntil(
  WidgetTester tester,
  bool Function() done, {
  int times = 40,
}) async {
  for (var i = 0; i < times && !done(); i++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump(const Duration(milliseconds: 100));
  }
}
