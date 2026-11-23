// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/message_search/index_operation.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, Object?> event({
  String type = 'm.room.message',
  String eventId = r'$original',
  Object? content = const {'msgtype': 'm.text', 'body': 'Dinner with Naveen'},
  Map<String, Object?>? unsigned,
  String? redacts,
}) => {
  'type': type,
  'event_id': eventId,
  'room_id': '!room:example.org',
  'sender': '@naveen:example.org',
  'origin_server_ts': 1700000000000,
  'content': content,
  'unsigned': ?unsigned,
  'redacts': ?redacts,
  'status': 2,
};

void main() {
  test('a text message is indexed under its own event', () {
    final operation = IndexOperation.fromEventJson(event()) as IndexMessage;
    expect(operation.eventId, r'$original');
    expect(operation.roomId, '!room:example.org');
    expect(operation.senderId, '@naveen:example.org');
    expect(operation.timestamp, 1700000000000);
    expect(operation.body, 'Dinner with Naveen');
    expect(operation.editTimestamp, 0);
  });

  test('an edit replaces the text of the message it edits', () {
    final operation =
        IndexOperation.fromEventJson(
              event(
                eventId: r'$edit',
                content: {
                  'msgtype': 'm.text',
                  'body': '* Lunch with Naveen',
                  'm.new_content': {'msgtype': 'm.text', 'body': 'Lunch'},
                  'm.relates_to': {
                    'rel_type': 'm.replace',
                    'event_id': r'$original',
                  },
                },
              ),
            )
            as IndexMessage;
    expect(operation.eventId, r'$original');
    expect(operation.body, 'Lunch');
    expect(operation.editTimestamp, 1700000000000);
  });

  test('a reply is a message of its own', () {
    final operation =
        IndexOperation.fromEventJson(
              event(
                eventId: r'$reply',
                content: {
                  'msgtype': 'm.text',
                  'body': 'Sure',
                  'm.relates_to': {
                    'm.in_reply_to': {'event_id': r'$original'},
                  },
                },
              ),
            )
            as IndexMessage;
    expect(operation.eventId, r'$reply');
    expect(operation.editTimestamp, 0);
  });

  test('a redaction removes its target', () {
    final operation =
        IndexOperation.fromEventJson(
              event(
                type: 'm.room.redaction',
                eventId: r'$redaction',
                content: const <String, Object?>{},
                redacts: r'$original',
              ),
            )
            as RemoveMessage;
    expect(operation.eventId, r'$original');
  });

  test('a message stored as redacted is removed', () {
    final operation =
        IndexOperation.fromEventJson(
              event(
                content: const <String, Object?>{},
                unsigned: {
                  'redacted_because': {'type': 'm.room.redaction'},
                },
              ),
            )
            as RemoveMessage;
    expect(operation.eventId, r'$original');
  });

  test('events without searchable text are skipped', () {
    // Could not be decrypted yet.
    expect(
      IndexOperation.fromEventJson(
        event(type: 'm.room.encrypted', content: {'ciphertext': 'x'}),
      ),
      isNull,
    );
    expect(IndexOperation.fromEventJson(event(type: 'm.reaction')), isNull);
    // Still sending: stored under a transaction ID.
    expect(IndexOperation.fromEventJson(event(eventId: 'txn123')), isNull);
    expect(
      IndexOperation.fromEventJson(event(content: {'msgtype': 'm.text'})),
      isNull,
    );
    expect(
      IndexOperation.fromEventJson(
        event(content: {'msgtype': 'm.text', 'body': '   '}),
      ),
      isNull,
    );
  });

  test('content of the wrong shape is skipped, not thrown on', () {
    expect(IndexOperation.fromEventJson(event(content: {'body': 42})), isNull);
    expect(IndexOperation.fromEventJson(event(content: 'text')), isNull);
    expect(
      IndexOperation.fromEventJson(
        event(
          content: {
            'body': 'ok',
            'm.relates_to': 'broken',
            'm.new_content': ['broken'],
          },
        ),
      ),
      isA<IndexMessage>(),
    );
  });

  test('very long text is cut to the indexed length', () {
    final operation =
        IndexOperation.fromEventJson(
              event(
                content: {'body': 'a' * (IndexOperation.maxBodyLength * 2)},
              ),
            )
            as IndexMessage;
    expect(operation.body.length, IndexOperation.maxBodyLength);
  });
}
