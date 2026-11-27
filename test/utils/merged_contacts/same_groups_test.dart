// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:async';

import 'package:fluffychat/pages/chat_list/merged_contact_list.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/merged_timeline.dart';
import 'package:fluffychat/utils/merged_contacts/send_router.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';

import 'fake_rooms.dart';

const _imessageBot = '@imessagebot:x';
const _gmessagesBot = '@gmessagesbot:x';
const _drew = '@imessage_drew:x';
const _harrison = '@imessage_harrison:x';
const _peter = '@imessage_peter:x';
const _quinn = '@imessage_quinn:x';

/// Separate iMessage threads with the same people, as the bridge makes a
/// room for each, and the chat list's view of them.
void main() {
  late Client client;

  setUp(() async => client = await fakeMergedClient());
  tearDown(() => MergedContactsStore.disposeFor(client));

  void member(Room room, String id, String name) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': name},
      senderId: id,
      stateKey: id,
    ),
  );

  /// A group on the bridge of [bot] with [people] (ID to display name),
  /// named [name] when given, whose newest message is at [last].
  Room addGroup(
    String id,
    Map<String, String> people, {
    String? name,
    String bot = _imessageBot,
    required DateTime last,
    int unread = 0,
  }) {
    final room = Room(id: id, client: client, notificationCount: unread);
    if (name != null) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomName,
          content: {'name': name},
          senderId: bot,
          stateKey: '',
        ),
      );
    }
    member(room, bot, 'bridge bot');
    people.forEach((id, name) => member(room, id, name));
    room.setState(
      StrippedStateEvent(
        type: 'm.bridge',
        content: {
          'bridgebot': bot,
          'protocol': {'id': 'imessage', 'displayname': 'iMessage'},
        },
        senderId: bot,
        stateKey: 'net/$id',
      ),
    );
    room.lastEvent = Event(
      content: {'msgtype': 'm.text', 'body': 'last in $id'},
      type: EventTypes.Message,
      eventId: '\$$id-last',
      senderId: people.keys.first,
      originServerTs: last,
      room: room,
    );
    client.rooms.add(room);
    return room;
  }

  const drewAndHarrison = {_drew: 'Drew Andersen', _harrison: 'Harrison Young'};

  /// The Drew and Harrison threads: the live one, and an older one.
  (Room, Room) addPair() => (
    addGroup(
      '!SzbgISeNdtFIwkkdBi:x',
      drewAndHarrison,
      name: 'Harrison Young, Drew Andersen',
      last: DateTime(2026, 11, 26),
      unread: 2,
    ),
    addGroup(
      '!vgMMvrfuOBINcTnmQG:x',
      drewAndHarrison,
      name: 'Drew Andersen, Harrison Young',
      last: DateTime(2025, 6, 1),
      unread: 1,
    ),
  );

  MergedChatList list() {
    final rooms = [...client.rooms]
      ..sort(
        (a, b) =>
            b.latestEventReceivedTime.compareTo(a.latestEventReceivedTime),
      );
    return MergedChatList.build(client, rooms, (_) => true);
  }

  test('the same people on one bridge are one row, unread summed', () {
    final (live, old) = addPair();
    final listed = list();
    expect(listed.rooms, [live]);
    final contact = listed.contacts[live.id]!;
    expect(contact.roomIds, [live.id, old.id]);
    expect(contact.notificationCount, 3);
    expect(MergedContact.ofRoom(client, old.id)?.id, contact.id);
  });

  test('their histories interleave by time', () {
    final (live, old) = addPair();
    final contact = list().contacts[live.id]!;
    Event message(Room room, String id, int day) => Event(
      content: {'msgtype': 'm.text', 'body': id},
      type: EventTypes.Message,
      eventId: '\$$id',
      senderId: _drew,
      originServerTs: DateTime(2025, 1, day),
      room: room,
    );
    final timelines = [
      for (final room in contact.rooms)
        Timeline(
          room: room,
          chunk: TimelineChunk(
            events: room == live
                ? [
                    message(live, 'live5', 5),
                    message(live, 'live3', 3),
                    message(live, 'live1', 1),
                  ]
                : [
                    message(old, 'old4', 4),
                    message(old, 'old2', 2),
                    message(old, 'old0', 0),
                  ],
          ),
        ),
    ];
    final merged = MergedTimeline.ofChildren(timelines);
    addTearDown(merged.cancelSubscriptions);
    // Both can load older history, so what shows stops above the newer
    // of their oldest loaded messages (day 1), as for merged chats.
    expect(
      [for (final event in merged.events) event.eventId],
      [r'$live5', r'$old4', r'$live3', r'$old2'],
    );
  });

  test('a new message goes to the most recently active thread', () {
    final (live, old) = addPair();
    final contact = MergedContact.ofRoom(client, old.id)!;
    expect(SendRouter.contact(contact.entry).newMessageRoomId, live.id);
  });

  test('a name given to the group wins over one built from the members', () {
    const four = {
      _drew: 'Drew Andersen',
      _harrison: 'Harrison Young',
      _peter: 'Peter Park',
      _quinn: 'Quinn Imsg',
    };
    final unnamed = addGroup(
      '!ntWueQqjLmugqRXsFW:x',
      four,
      name: 'Quinn Imsg, Peter Park, Harrison Young, Drew Andersen',
      last: DateTime(2025, 5, 1),
    );
    addGroup(
      '!SlpITPiIBnozbvRbGm:x',
      four,
      name: 'P-Patrol Rebørn',
      last: DateTime(2025, 3, 1),
    );
    final contact = MergedContact.ofRoom(client, unnamed.id)!;
    expect(contact.sendViaRoom, unnamed);
    expect(contact.displayName(), 'P-Patrol Rebørn');
  });

  test('"Group Chat" is a built name, passed over for the members', () {
    final (live, _) = addPair();
    final legacy = addGroup(
      '!third:x',
      drewAndHarrison,
      name: 'Group Chat',
      last: DateTime(2026, 11, 27),
    );
    expect(MergedContact.ofRoom(client, live.id)?.sendViaRoom, legacy);
    expect(
      MergedContact.ofRoom(client, live.id)?.displayName(),
      'Harrison Young, Drew Andersen',
    );
  });

  test('groups whose people differ stay apart', () {
    final (live, _) = addPair();
    addGroup('!more:x', {
      ...drewAndHarrison,
      _peter: 'Peter Park',
    }, last: DateTime(2026, 11, 25));
    addGroup('!less:x', {_drew: 'Drew Andersen'}, last: DateTime(2026, 11, 24));
    final listed = list();
    expect(listed.rooms.map((room) => room.id), [
      live.id,
      '!more:x',
      '!less:x',
    ]);
    expect(MergedContact.ofRoom(client, '!more:x'), isNull);
    expect(MergedContact.ofRoom(client, '!less:x'), isNull);
  });

  test('the same people on two bridges stay apart', () {
    addGroup('!imsg:x', drewAndHarrison, last: DateTime(2026, 11, 26));
    addGroup(
      '!gm:x',
      drewAndHarrison,
      bot: _gmessagesBot,
      last: DateTime(2026, 11, 25),
    );
    expect(list().rooms, hasLength(2));
    expect(MergedContact.ofRoom(client, '!imsg:x'), isNull);
  });

  test(
    'a chat added to them makes a stored conversation of all three',
    () async {
      final backend = _Backend();
      final store = MergedContactsStore(backend);
      addTearDown(store.dispose);
      final automatic = store.contactForRoom('!a')!;

      // The same people on another network, added with the chat's "+".
      final id = await store.merge(['!gm'], intoContactId: automatic.id);
      final contact = store.contactForRoom('!gm');
      expect(contact?.id, id);
      expect(contact?.automatic, isFalse);
      expect(contact?.rooms, ['!a', '!b', '!gm']);
      expect(store.contactForRoom('!a')?.id, id);
      expect(store.contactForRoom('!b')?.id, id);
      expect(store.contacts, hasLength(1));
    },
  );

  test('splitting them up keeps them apart', () async {
    final backend = _Backend();
    final store = MergedContactsStore(backend);
    addTearDown(store.dispose);
    final contact = store.contactForRoom('!a')!;
    expect(contact.automatic, isTrue);
    expect(contact.rooms, ['!a', '!b']);

    await store.unmerge(contact.id);
    expect(store.contactForRoom('!a'), isNull);
    expect(store.contactForRoom('!b'), isNull);
    expect(backend.content?['dismissed_suggestions'], [
      ['!a', '!b'],
    ]);
  });
}

/// Account data in memory, with two same-people groups.
class _Backend extends MergedContactsBackend {
  Map<String, Object?>? content;
  final _changes = StreamController<void>.broadcast();

  @override
  Map<String, Object?>? read() => content;

  @override
  Future<void> write(Map<String, Object?> content) async =>
      this.content = content;

  @override
  Stream<void> get onRemoteChange => _changes.stream;

  @override
  Stream<void> get onRoomsChanged => _changes.stream;

  @override
  bool isUsableRoom(String roomId) => true;

  @override
  Future<void> get ready async {}

  @override
  List<({List<String> rooms, String? name})> sameGroups() => [
    (rooms: ['!a', '!b'], name: null),
  ];
}
