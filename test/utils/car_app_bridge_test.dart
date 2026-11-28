// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/car_app_bridge.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'message_search/search_test_client.dart';

void main() {
  group('groupCarConversations', () {
    test('a merged contact lists once, at its newest room', () {
      final groups = groupCarConversations([
        ('!imsg', 'contact_c1'),
        ('!bob', '!bob'),
        ('!sms', 'contact_c1'),
      ], 10);
      expect(groups.map((g) => g.id), ['contact_c1', '!bob']);
      expect(groups.first.roomIds, ['!imsg', '!sms']);
    });

    test('stops at the limit but keeps rooms of listed conversations', () {
      final groups = groupCarConversations([
        ('!a', '!a'),
        ('!imsg', 'contact_c1'),
        ('!b', '!b'),
        ('!sms', 'contact_c1'),
      ], 2);
      expect(groups.map((g) => g.id), ['!a', 'contact_c1']);
      expect(groups.last.roomIds, ['!imsg', '!sms']);
    });
  });

  group('carReplyRoom', () {
    test('answers the room the other side wrote in last', () {
      expect(
        carReplyRoom(
          ['!imsg', '!sms'],
          {'!imsg': DateTime(2026, 1, 1), '!sms': DateTime(2026, 1, 2)},
          sendVia: '!imsg',
        ),
        '!sms',
      );
    });

    test('falls back to send-via when they never wrote', () {
      expect(carReplyRoom(['!imsg', '!sms'], {}, sendVia: '!sms'), '!sms');
      expect(carReplyRoom(['!only'], {'!only': null}), '!only');
    });
  });

  group('carRoomMessages', () {
    const roomId = '!bridged:fakeServer.notExisting';
    const puppet = '@gmessages_1:fakeServer.notExisting';
    late Client client;
    late MatrixLocals locals;

    setUp(() async {
      client = await createSearchTestClient();
      locals = MatrixLocals(await lookupL10n(const Locale('en')));
    });

    tearDown(() => client.dispose(closeDatabase: true));

    MatrixEvent event(
      String id,
      Map<String, Object?> content,
      int second, {
      String sender = puppet,
    }) => MatrixEvent(
      type: EventTypes.Message,
      content: content,
      senderId: sender,
      eventId: id,
      originServerTs: DateTime.utc(2026, 11, 26, 15, 12, second),
    );

    Future<void> sync(List<MatrixEvent> events) => client.handleSync(
      SyncUpdate(
        nextBatch: 'batch',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(timeline: TimelineUpdate(events: events)),
          },
        ),
      ),
    );

    Map<String, Object?> edit(String target, Map<String, Object?> content) => {
      'msgtype': content['msgtype'],
      'body': '* ${content['body']}',
      'm.new_content': content,
      'm.relates_to': {'rel_type': 'm.replace', 'event_id': target},
    };

    test('a placeholder notice edited into a photo shows the photo', () async {
      const notice = r'$notice';
      await sync([
        event(r'$text', {
          'msgtype': 'm.text',
          'body': 'Time to put up the tree!',
        }, 0),
        event(notice, {
          'msgtype': 'm.notice',
          'body': 'Waiting for attachment 4308013893108320279',
        }, 1),
        event(
          r'$edit',
          edit(notice, {
            'msgtype': 'm.image',
            'body': 'image.jpg',
            'url': 'mxc://fakeServer.notExisting/photo',
          }),
          3,
        ),
      ]);

      final messages = await carRoomMessages(
        client,
        client.getRoomById(roomId)!,
        locals,
      );

      expect(messages, hasLength(2));
      // Newest first, as the database lists them.
      expect(messages.first.body, isNot(contains('Waiting for attachment')));
      expect(messages.first.body, contains('sent a picture'));
      // It keeps the placeholder's place in the order.
      expect(messages.first.event.eventId, notice);
      expect(
        messages.first.event.originServerTs.toUtc(),
        DateTime.utc(2026, 11, 26, 15, 12, 1),
      );
    });

    test('a placeholder still waiting reads as the photo or video', () async {
      await sync([
        event(r'$photo', {
          'msgtype': 'm.notice',
          'body': 'Waiting for attachment PXL_1.jpg',
          'fi.mau.gmessages.media_pending': true,
        }, 0),
        event(r'$video', {
          'msgtype': 'm.notice',
          'body': 'Waiting for attachment PXL_2.mp4',
          'fi.mau.gmessages.media_pending': true,
        }, 1),
        event(r'$failed', {
          'msgtype': 'm.notice',
          'body': 'Failed to transfer attachment PXL_3.jpg',
        }, 2),
      ]);

      final messages = await carRoomMessages(
        client,
        client.getRoomById(roomId)!,
        locals,
      );

      // Newest first, as the database lists them.
      expect(messages.map((m) => m.body), [
        "Photo didn't arrive",
        'Video',
        'Photo',
      ]);
    });

    test('the newest edit wins and another sender cannot edit', () async {
      const message = r'$message';
      await sync([
        event(message, {'msgtype': 'm.text', 'body': 'first'}, 0),
        event(
          r'$e1',
          edit(message, {'msgtype': 'm.text', 'body': 'second'}),
          1,
        ),
        event(r'$e2', edit(message, {'msgtype': 'm.text', 'body': 'third'}), 2),
        event(
          r'$e3',
          edit(message, {'msgtype': 'm.text', 'body': 'forged'}),
          3,
          sender: '@other:fakeServer.notExisting',
        ),
      ]);

      final messages = await carRoomMessages(
        client,
        client.getRoomById(roomId)!,
        locals,
      );

      expect(messages.map((m) => m.body), ['third']);
    });
  });
}
