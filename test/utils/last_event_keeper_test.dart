// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/last_event_keeper.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'message_search/search_test_client.dart';

const _bridged = '!bridged:fakeServer.notExisting';
const _other = '!other:fakeServer.notExisting';
const _ghost = '@telegram_42:fakeServer.notExisting';

MatrixEvent _message(String id, String body, DateTime time) => MatrixEvent(
  type: EventTypes.Message,
  content: {'msgtype': 'm.text', 'body': body},
  senderId: _ghost,
  eventId: id,
  originServerTs: time,
);

SyncUpdate _sync(
  String roomId,
  List<MatrixEvent> events, {
  bool limited = false,
}) => SyncUpdate(
  nextBatch: 'batch',
  rooms: RoomsUpdate(
    join: {
      roomId: JoinedRoomUpdate(
        timeline: TimelineUpdate(events: events, limited: limited),
      ),
    },
  ),
);

int _rank(Client client, String roomId) =>
    client.rooms.indexWhere((room) => room.id == roomId);

void main() {
  late Client client;

  setUp(() async {
    client = await createSearchTestClient();
    LastEventKeeper.attach(client);
    await client.handleSync(
      _sync(_bridged, [_message('\$old', 'old message', DateTime(2026, 1, 1))]),
    );
    await client.handleSync(
      _sync(_other, [
        _message('\$newer', 'newer message', DateTime(2026, 1, 2)),
      ]),
    );
  });

  tearDown(() => client.dispose(closeDatabase: true));

  test('a limited sync holding only a bridge state event keeps the preview '
      'and the order', () async {
    expect(_rank(client, _other), lessThan(_rank(client, _bridged)));
    // The sync loop announces each request before sending it.
    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.waitingForResponse));
    await pumpEventQueue();
    await client.handleSync(
      _sync(_bridged, [
        MatrixEvent(
          type: 'com.beeper.room_features',
          content: {'max_text_length': 4096},
          senderId: '@telegrambot:fakeServer.notExisting',
          eventId: '\$features',
          originServerTs: DateTime(2026, 1, 3),
          stateKey: '',
        ),
      ], limited: true),
    );
    // The keeper puts the old event back after the sync is handled.
    await pumpEventQueue();
    final room = client.getRoomById(_bridged)!;
    expect(room.lastEvent?.type, isNot(EventTypes.refreshingLastEvent));
    expect(room.lastEvent?.body, 'old message');
    expect(_rank(client, _other), lessThan(_rank(client, _bridged)));
  });

  test(
    'a room with only bridge state gets no preview and keeps its place',
    () async {
      const empty = '!empty:fakeServer.notExisting';
      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.waitingForResponse));
      await pumpEventQueue();
      await client.handleSync(
        _sync(empty, [
          MatrixEvent(
            type: 'com.beeper.room_features',
            content: {'max_text_length': 4096},
            senderId: '@imessagebot:fakeServer.notExisting',
            eventId: '\$features2',
            originServerTs: DateTime(2026, 1, 5),
            stateKey: '',
          ),
        ], limited: true),
      );
      await pumpEventQueue();
      final room = client.getRoomById(empty)!;
      expect(room.lastEvent, isNull);
      expect(_rank(client, _other), lessThan(_rank(client, empty)));
    },
  );

  test('a limited sync with a message previews that message', () async {
    client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.waitingForResponse));
    await pumpEventQueue();
    await client.handleSync(
      _sync(_bridged, [
        _message('\$newest', 'newest message', DateTime(2026, 1, 3)),
      ], limited: true),
    );
    await pumpEventQueue();
    expect(client.getRoomById(_bridged)!.lastEvent?.body, 'newest message');
    expect(_rank(client, _bridged), lessThan(_rank(client, _other)));
  });

  test(
    'a reaction taken back leaves the message before it as the preview',
    () async {
      // The app counts reactions as a chat's latest event.
      client.roomPreviewLastEvents.add(EventTypes.Reaction);
      final room = client.getRoomById(_bridged)!;
      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.waitingForResponse));
      await pumpEventQueue();
      await client.handleSync(
        _sync(_bridged, [
          MatrixEvent(
            type: EventTypes.Reaction,
            content: {
              'm.relates_to': {
                'rel_type': RelationshipTypes.reaction,
                'event_id': '\$old',
                'key': '\u2764\ufe0f',
              },
            },
            senderId: client.userID!,
            eventId: '\$heart',
            originServerTs: DateTime(2026, 1, 3),
          ),
        ]),
      );
      await pumpEventQueue();
      expect(room.lastEvent?.eventId, '\$heart');
      client.onSyncStatus.add(SyncStatusUpdate(SyncStatus.waitingForResponse));
      await pumpEventQueue();
      await client.handleSync(
        _sync(_bridged, [
          MatrixEvent(
            type: EventTypes.Redaction,
            content: {'redacts': '\$heart'},
            redacts: '\$heart',
            senderId: client.userID!,
            eventId: '\$unheart',
            originServerTs: DateTime(2026, 1, 3, 0, 0, 3),
          ),
        ]),
      );
      await pumpEventQueue();
      expect(room.lastEvent?.redacted, isNot(true));
      expect(room.lastEvent?.body, 'old message');
    },
  );
}
