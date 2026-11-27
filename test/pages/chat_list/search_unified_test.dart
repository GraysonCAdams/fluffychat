// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_header.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/message_search_results.dart';
import 'package:fluffychat/utils/message_search/message_search_hit.dart';
import 'package:fluffychat/utils/message_search/message_search_source.dart';
import 'package:fluffychat/utils/message_search/search_query.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../utils/merged_contacts/fake_rooms.dart' show setMergedContacts;
import 'chat_list_fakes.dart';

/// Answers every search with [hits].
class _Hits extends MessageSearchSource {
  _Hits(this.hits);

  final List<MessageSearchHit> hits;

  @override
  Future<MessageSearchPage> search(SearchQuery query, {Object? cursor}) async =>
      MessageSearchPage(hits: hits);
}

/// A merged contact is one chat in the search, whichever of its networks
/// the chats or messages found are on.
void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('search unified test');
    addFakeChat(
      client,
      '!imsg:x',
      'Harrison iMessage',
      partner: '@imessage_harrison:x',
    );
    addFakeChat(
      client,
      '!sms:x',
      'Harrison SMS',
      partner: '@gmessages_harrison:x',
      lastMessageTime: DateTime(2025),
    );
    setMergedContacts(client, {
      'c_1': {
        'name': 'Harrison Young',
        'rooms': ['!imsg:x', '!sms:x'],
        'send_via': '!imsg:x',
        'updated': 1,
      },
    });
  });

  tearDown(() => tearDownFakeChatList(client));

  testWidgets('a merged contact is one row in the results, opening its '
      'merged chat', (tester) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(400, 800);
    addTearDown(tester.view.reset);
    await pumpFakeChatList(tester, client);
    await tester.tap(
      find.descendant(
        of: find.byType(ChatListHeader),
        matching: find.byTooltip('Search'),
      ),
    );
    await tester.pumpAndSettle();
    // Both of its rooms are named for it.
    await tester.enterText(find.byType(TextField), 'harrison');
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    expect(find.byType(ChatListItem), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatListItem),
        matching: find.text('Harrison Young'),
      ),
      findsOneWidget,
    );
    await tester.tap(find.byType(ChatListItem));
    await tester.pumpAndSettle();
    expect(find.text('opened contact c_1'), findsOneWidget);

    await finishFakeChatList(tester, client);
  });

  testWidgets('a message from either network is the merged chat\'s, and '
      'opens it at that message', (tester) async {
    final field = TextEditingController();
    addTearDown(field.dispose);
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (context, state) => Scaffold(
            body: CustomScrollView(
              slivers: [
                MessageSearchResults(
                  client: client,
                  searchField: field,
                  sources: [
                    _Hits([
                      MessageSearchHit(
                        eventId: r'$waffle',
                        roomId: '!sms:x',
                        senderId: '@gmessages_harrison:x',
                        body: 'Waffle House tonight?',
                        timestamp: DateTime(2026, 11, 27),
                      ),
                    ]),
                  ],
                ),
              ],
            ),
          ),
        ),
        GoRoute(
          path: '/rooms/contact/:contactid',
          builder: (context, state) => Text(
            'opened contact ${state.pathParameters['contactid']} at '
            '${state.uri.queryParameters['event']} in '
            '${state.uri.queryParameters['room']}',
          ),
        ),
        GoRoute(
          path: '/rooms/:roomid',
          builder: (context, state) =>
              Text('opened ${state.pathParameters['roomid']}'),
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
    field.text = 'waffle';
    await tester.pump(const Duration(milliseconds: 600));
    await tester.pumpAndSettle();

    // Named for the merged chat, not the room the message is in.
    expect(find.text('Harrison Young'), findsOneWidget);
    expect(find.text('Harrison SMS'), findsNothing);
    await tester.tap(find.textContaining('Waffle', findRichText: true));
    await tester.pumpAndSettle();
    expect(
      find.text(r'opened contact c_1 at $waffle in !sms:x'),
      findsOneWidget,
    );

    await tester.pumpWidget(const SizedBox());
  });
}
