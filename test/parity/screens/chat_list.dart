// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

/// The chat list fixtures (`chat-list`, `chat-list-selected`): the app's
/// real ChatList page over rooms made from the fixture.
library;

import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../harness.dart';

/// A screen that shows the chat list inside more of the app: [addRooms]
/// adds that screen's own rooms to the client, so they come first after
/// the pinned chats, and [pump] pumps the app around the list.
typedef ChatListHost = ({
  Future<void> Function(ParityClient client) addRooms,
  Future<void> Function(ParityClient client, SharedPreferences prefs) pump,
});

/// When a fixture time like "21:16" or "Tue" happened, relative to now, so
/// the list prints that same text. [index] keeps rows with the same label
/// in fixture order (newest first).
DateTime fixtureTime(String label, int index) {
  final now = DateTime.now();
  final clock = RegExp(r'^(\d{1,2}):(\d{2})$').firstMatch(label);
  if (clock != null) {
    return DateTime(
      now.year,
      now.month,
      now.day,
      int.parse(clock.group(1)!),
      int.parse(clock.group(2)!),
    );
  }
  const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
  final weekday = days.indexOf(label) + 1;
  if (weekday > 0) {
    // The last such day before today; late in the day so it stays within
    // the week the list prints as a weekday.
    var back = (now.weekday - weekday) % 7;
    if (back == 0) back = 7;
    final day = DateTime(now.year, now.month, now.day - back, 23, 30);
    return day.subtract(Duration(minutes: index));
  }
  throw ArgumentError('Unknown fixture time "$label"');
}

/// A one-to-one chat named [name] with a last message of [body] (sent by
/// the own account when [fromMe]).
ParityRoom _addChat(
  Client client, {
  required String id,
  required String name,
  required String body,
  required DateTime time,
  bool fromMe = false,
  bool picture = false,
  bool struck = false,
  int unread = 0,
  String bridge = '',
}) {
  final partner = '@$bridge${slug(name)}:$homeserver';
  final room = ParityRoom(id: id, client: client, notificationCount: unread);
  setRoomState(room, EventTypes.RoomName, {'name': name}, sender: partner);
  setRoomState(
    room,
    EventTypes.RoomMember,
    {'membership': 'join', 'displayname': name},
    stateKey: partner,
    sender: partner,
  );
  setRoomState(room, EventTypes.RoomMember, {
    'membership': 'join',
    'displayname': 'Robin',
  }, stateKey: ownUserId);
  if (picture) {
    setRoomState(room, EventTypes.RoomAvatar, {
      'url': '$flatPicture',
    }, sender: partner);
  }
  final sender = fromMe ? ownUserId : partner;
  room.lastEvent = Event(
    content: struck ? {} : {'msgtype': 'm.text', 'body': body},
    type: EventTypes.Message,
    eventId: '\$$id-last',
    senderId: sender,
    originServerTs: time,
    unsigned: struck
        ? {
            'redacted_because': {
              'type': EventTypes.Redaction,
              'event_id': '\$$id-redaction',
              'sender': partner,
              'origin_server_ts': time.millisecondsSinceEpoch,
              'content': {},
            },
          }
        : null,
    room: room,
  );
  if (unread == 0) markRead(room);
  client.rooms.add(room);
  markDirect(client, partner, id);
  return room;
}

/// A homeserver search result for [hit] in [roomId], as `/search`
/// returns it. The fixture marks the matched words with [[ ]].
Map<String, Object?> _searchResult(
  Client client,
  Map hit,
  String roomId,
  int index,
) {
  final sender = hit['sender'] == 'You'
      ? ownUserId
      : '@${slug(hit['sender'] as String)}:$homeserver';
  var body = (hit['text'] as String).replaceAll('[[', '').replaceAll(']]', '');
  // A leading ellipsis is where the app cut the message to show the match;
  // the message itself went on before it.
  if (body.startsWith('\u2026')) {
    body =
        'We talked about it on the way home and thought we could '
        '${body.substring(1)}';
  }
  return {
    'rank': 1.0,
    'result': {
      'type': EventTypes.Message,
      'event_id': '\$hit$index',
      'room_id': roomId,
      'sender': sender,
      'origin_server_ts': fixtureTime(
        hit['time'] as String,
        index,
      ).millisecondsSinceEpoch,
      'content': {'msgtype': MessageTypes.Text, 'body': body},
    },
    'context': {
      'profile_info': {
        sender: {
          'displayname': hit['sender'] == 'You' ? 'Robin' : hit['sender'],
        },
      },
    },
  };
}

Future<ParityClient> _build(
  WidgetTester tester,
  ParityFixture fixture,
  int fillers,
  ChatListHost? host,
) async {
  final screen = fixture.screenData;
  parityStep('build');
  final prefs = await setUpParitySettings(fixture);
  parityStep('settings');
  final header = screen['header'];
  if (header is Map && header['server'] != null) {
    await prefs.setString(
      'im.fluffychat.search.server',
      header['server'] as String,
    );
  }
  final client = (await tester.runAsync(
    () => ParityClient.create('parity ${fixture.screen}'),
  ))!;
  parityStep('client');
  await host?.addRooms(client);

  final pinned = (screen['pinned'] as List? ?? []).cast<Map>();
  for (final (i, pin) in pinned.indexed) {
    final name = pin['name'] as String;
    final unread = pin['unread'] as String?;
    final networks = (pin['networks'] as List? ?? []).cast<String>();
    final room = _addChat(
      client,
      id: '!pin$i:$homeserver',
      name: name,
      body: unread ?? 'See you there',
      time: DateTime.now().subtract(Duration(minutes: 1 + i)),
      picture: pin['picture'] == true,
      unread: unread == null ? 0 : 1,
      bridge: networks.isEmpty ? '' : '${networks.first}_',
    );
    room.roomAccountData['m.tag'] = BasicEvent(
      type: 'm.tag',
      content: {
        'tags': {
          'm.favourite': {'order': (i + 1) / (pinned.length + 1)},
        },
      },
    );
  }

  final rows = (screen['rows'] as List).cast<Map>();
  for (final (i, row) in rows.indexed) {
    _addChat(
      client,
      id: '!row$i:$homeserver',
      name: row['name'] as String,
      body: row['preview'] as String,
      time: fixtureTime(row['time'] as String, i),
      fromMe: row['from'] == 'you',
      picture: row['picture'] == true,
      struck: row['struck'] == true,
      unread: row['unread'] as int? ?? 0,
    );
  }

  // The search hits' chats, which the search finds by message only.
  final hits = (screen['hits'] as List? ?? []).cast<Map>();
  final hitRooms = <String, String>{};
  for (final (i, hit) in hits.indexed) {
    final name = hit['room'] as String;
    if (hitRooms.containsKey(name)) continue;
    final id = '!hit$i:$homeserver';
    hitRooms[name] = id;
    _addChat(
      client,
      id: id,
      name: name,
      body: 'See you then',
      time: DateTime.now().subtract(Duration(days: 30, minutes: i)),
      picture: hit['picture'] == true,
    );
  }

  // Unread chats further down, which only the "N unread" chip shows.
  final oldest = DateTime.now().subtract(const Duration(days: 40));
  for (var i = 0; i < fillers; i++) {
    _addChat(
      client,
      id: '!more$i:$homeserver',
      name: 'Older chat $i',
      body: 'An older message',
      time: oldest.subtract(Duration(hours: i)),
      unread: 1,
    );
  }

  // The bridges' spaces, which the "All" chip's menu lists: the menu's
  // rows when the fixture shows it open, else one per network. Added last,
  // so the list, which keeps the client's order until a sync sorts it,
  // shows them below every chat.
  final overlay = fixture.overlay;
  final filters = (screen['filters'] as List? ?? []).cast<Map>();
  if (overlay?['kind'] == 'sourceMenu') {
    for (final (i, item) in (overlay!['items'] as List).cast<Map>().indexed) {
      if (item['network'] == null && item['picture'] != true) continue;
      final space = addNetworkSpace(
        client,
        item['network'] as String? ?? 'space$i',
        item['label'] as String,
        const [],
      );
      if (item['picture'] == true) {
        setRoomState(space, EventTypes.RoomAvatar, {'url': '$flatPicture'});
      }
    }
  } else if (filters.firstOrNull?['menu'] == true) {
    for (final MapEntry(:key, :value) in fixture.networkNames.entries) {
      final space = addNetworkSpace(client, key, value, const []);
      setRoomState(space, EventTypes.RoomAvatar, {'url': '$flatPicture'});
    }
  }

  // The host's rooms brought their own spaces; those go to the end too.
  if (host != null) {
    final spaces = client.rooms.where((room) => room.isSpace).toList();
    client.rooms
      ..removeWhere((room) => room.isSpace)
      ..addAll(spaces);
  }

  addTearDown(() {
    MergeSuggestionService.disposeFor(client);
    MergedContactsStore.disposeFor(client);
  });

  parityStep('rooms');
  if (host != null) {
    await host.pump(client, prefs);
  } else {
    await pumpParityApp(
      tester,
      client: client,
      prefs: prefs,
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => const ChatList(activeChat: null),
          routes: [
            GoRoute(
              path: ':roomid',
              builder: (context, state) => const SizedBox.shrink(),
            ),
          ],
        ),
      ],
    );
  }
  await settleParity(tester);

  if (header is Map && header['query'] != null) {
    final sections = (screen['searchSections'] as List? ?? []).cast<Map>();
    ParityClient.searchStillLoading = sections.any(
      (section) => section['label'] == 'Messages' && section['busy'] == true,
    );
    ParityClient.searchHits = [
      for (final (i, hit) in hits.indexed)
        _searchResult(client, hit, hitRooms[hit['room']]!, i),
    ];
    // On a phone the header shows a search button until search starts;
    // where it shows the field itself, the field is tapped instead.
    final field = find.byType(TextField);
    await tester.tap(
      field.evaluate().isEmpty
          ? find.byIcon(Icons.search_outlined).first
          : field.first,
    );
    await tester.pump();
    await tester.enterText(
      find.byType(TextField).first,
      header['query'] as String,
    );
    await tester.pump(const Duration(seconds: 1));
    // The phone showed no cursor: the keyboard was down.
    FocusManager.instance.primaryFocus?.unfocus();
    await settleParity(tester);
  }

  if (overlay?['kind'] == 'sourceMenu') {
    await tester.tap(find.byIcon(Icons.arrow_drop_down));
    await settleParity(tester);
  }

  final selected = rows.where((row) => row['selected'] == true);
  for (final row in selected) {
    await tester.longPress(find.text(row['name'] as String).first);
    await settleParity(tester);
  }
  final scroll = (screen['scroll'] as num?)?.toDouble();
  if (scroll != null) {
    final controller = tester
        .state<ChatListController>(find.byType(ChatList))
        .scrollController;
    controller.jumpTo(-scroll);
    await settleParity(tester);
  }
  return client;
}

/// The number the "N unread" chip at the bottom shows, or 0.
int _unreadChipCount() {
  final chip = find.textContaining(RegExp(r'^\d+ unread$'));
  if (chip.evaluate().isEmpty) return 0;
  final text = (chip.evaluate().first.widget as Text).data!;
  return int.parse(text.split(' ').first);
}

/// Shows the chat list fixture [fixture] on the app's ChatList page and
/// returns its client, for tests that go on to change it. [view] sizes the
/// view instead of [fixture], and [host] shows the list inside more of the
/// app.
Future<ParityClient> pumpChatList(
  WidgetTester tester,
  ParityFixture fixture, {
  ParityFixture? view,
  ChatListHost? host,
}) async {
  setUpParityView(tester, view ?? fixture);
  final want = fixture.screenData['unreadJump'] as int? ?? 0;
  // Fixture rows past the bottom edge count toward the chip too, so the
  // first pass measures how many of them do and the second adds the rest.
  var client = await _build(tester, fixture, want, host);
  parityStep('first pass');
  final fromRows = _unreadChipCount() - want;
  if (fromRows != 0) {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(seconds: 5));
    client = await _build(tester, fixture, want - fromRows, host);
  }
  expect(_unreadChipCount(), want);
  return client;
}

Future<void> pumpChatListScreen(
  WidgetTester tester,
  ParityFixture fixture,
) async {
  await pumpChatList(tester, fixture);
  await expectParityGolden(tester, fixture);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}
