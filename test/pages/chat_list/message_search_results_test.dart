// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/message_search_results.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/message_search/message_search_hit.dart';
import 'package:fluffychat/utils/message_search/message_search_source.dart';
import 'package:fluffychat/utils/message_search/search_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/message_search/search_test_client.dart';

/// Answers at once from a fixed list, [pageSize] hits per page.
class ListSource extends MessageSearchSource {
  ListSource(this.hits, {this.pageSize = 100, this.fails = false});

  final List<MessageSearchHit> hits;
  final int pageSize;
  final bool fails;
  final queries = <String>[];

  @override
  Future<MessageSearchPage> search(SearchQuery query, {Object? cursor}) async {
    queries.add(query.text);
    if (fails) throw Exception('offline');
    final start = cursor as int? ?? 0;
    final end = start + pageSize < hits.length ? start + pageSize : hits.length;
    return MessageSearchPage(
      hits: hits.sublist(start, end),
      nextCursor: end < hits.length ? end : null,
    );
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late Room room;
  late TextEditingController searchField;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await createSearchTestClient();
    room = client.rooms.firstWhere((room) => !room.isSpace);
  });

  setUp(() => searchField = TextEditingController());
  tearDown(() => searchField.dispose());

  MessageSearchHit hit(String eventId, String body, int ts, {String? roomId}) =>
      MessageSearchHit(
        eventId: eventId,
        roomId: roomId ?? room.id,
        senderId: '@naveen:example.org',
        senderName: 'Naveen K',
        body: body,
        timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
      );

  Future<void> pumpResults(
    WidgetTester tester,
    List<MessageSearchSource> sources,
  ) async {
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: CustomScrollView(
              slivers: [
                MessageSearchResults(
                  client: client,
                  searchField: searchField,
                  sources: sources,
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/rooms/:roomid',
          builder: (context, state) => Text(
            'opened ${state.pathParameters['roomid']} '
            'at ${state.uri.queryParameters['event']}',
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      MaterialApp.router(
        routerConfig: router,
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Types into the field and lets the debounce and the answers pass.
  Future<void> search(WidgetTester tester, String text) async {
    searchField.text = text;
    await tester.pump(const Duration(milliseconds: 300));
    await tester.pumpAndSettle();
  }

  testWidgets('shows nothing until there is something to search for', (
    tester,
  ) async {
    final source = ListSource([hit(r'$a', 'Dinner with Naveen', 1000)]);
    await pumpResults(tester, [source]);
    expect(find.text('Messages'), findsNothing);

    await search(tester, 'n');
    expect(find.text('Messages'), findsNothing);
    expect(source.queries, isEmpty);
  });

  testWidgets('lists a hit with chat, sender, time and the match in bold', (
    tester,
  ) async {
    await pumpResults(tester, [
      ListSource([hit(r'$a', 'Dinner with Naveen tonight', 1000)]),
    ]);
    await search(tester, 'naveen');

    expect(find.text('Messages'), findsOneWidget);
    final l10n = L10n.of(tester.element(find.text('Messages')));
    expect(
      find.text(room.getLocalizedDisplayname(MatrixLocals(l10n))),
      findsOneWidget,
    );
    final snippet = tester.widget<RichText>(
      find.textContaining('Dinner with', findRichText: true),
    );
    expect(snippet.text.toPlainText(), 'Naveen K: Dinner with Naveen tonight');
    final bold = <String>[];
    snippet.text.visitChildren((span) {
      if (span is TextSpan && span.style?.fontWeight == FontWeight.bold) {
        bold.add(span.text!);
      }
      return true;
    });
    expect(bold, ['Naveen']);
    expect(find.text('No messages found'), findsNothing);
  });

  testWidgets('opens the chat at the message when tapped', (tester) async {
    await pumpResults(tester, [
      ListSource([hit(r'$a', 'Dinner with Naveen', 1000)]),
    ]);
    await search(tester, 'naveen');
    await tester.tap(find.textContaining('Dinner with', findRichText: true));
    await tester.pumpAndSettle();
    expect(find.text('opened ${room.id} at \$a'), findsOneWidget);
  });

  testWidgets('says so when nothing matches', (tester) async {
    await pumpResults(tester, [ListSource([])]);
    await search(tester, 'naveen');
    expect(find.text('Messages'), findsOneWidget);
    expect(find.text('No messages found'), findsOneWidget);
  });

  testWidgets('says so when no source could search', (tester) async {
    await pumpResults(tester, [ListSource([], fails: true)]);
    await search(tester, 'naveen');
    expect(
      find.text('Messages could not be searched right now'),
      findsOneWidget,
    );
    expect(find.text('No messages found'), findsNothing);
  });

  testWidgets('leaves out messages of rooms the account is not in', (
    tester,
  ) async {
    await pumpResults(tester, [
      ListSource([
        hit(r'$gone', 'Naveen left', 2000, roomId: '!left:example.org'),
        hit(r'$here', 'Naveen stayed', 1000),
      ]),
    ]);
    await search(tester, 'naveen');
    expect(find.textContaining('stayed', findRichText: true), findsOneWidget);
    expect(find.textContaining('left', findRichText: true), findsNothing);
  });

  testWidgets('fetches the next page when the end comes into view', (
    tester,
  ) async {
    final source = ListSource([
      for (var i = 0; i < 6; i++) hit('\$e$i', 'Naveen message $i', 9000 - i),
    ], pageSize: 2);
    await pumpResults(tester, [source]);
    await search(tester, 'naveen');
    // Six short tiles fit on the test screen, so every page's footer is in
    // view as soon as it is built and the pages follow one another.
    expect(source.queries, hasLength(3));
    expect(
      find.textContaining('Naveen message', findRichText: true),
      findsNWidgets(6),
    );
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('clearing the field removes the section', (tester) async {
    await pumpResults(tester, [
      ListSource([hit(r'$a', 'Dinner with Naveen', 1000)]),
    ]);
    await search(tester, 'naveen');
    expect(find.text('Messages'), findsOneWidget);
    await search(tester, '');
    expect(find.text('Messages'), findsNothing);
    expect(find.textContaining('Dinner', findRichText: true), findsNothing);
  });
}
