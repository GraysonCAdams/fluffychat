// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/room_features.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'merged_contacts/fake_rooms.dart';
import 'room_features_fixtures.dart';

void main() {
  group('FileFeatures.mimeSupport', () {
    const features = FileFeatures(
      mimeTypes: {
        'image/png': 2,
        'image/*': 1,
        'video/quicktime': 1,
        'video/webm': 0,
        'video/x-msvideo': -1,
        'video/*': -2,
        'text/*': 2,
      },
    );

    test('an exact key gives its level', () {
      expect(features.mimeSupport('image/png'), 2);
      expect(features.mimeSupport('video/quicktime'), 1);
      expect(features.mimeSupport('video/webm'), 0);
      expect(features.mimeSupport('video/x-msvideo'), -1);
    });

    test('matching ignores case and parameters', () {
      expect(features.mimeSupport('IMAGE/PNG'), 2);
      expect(features.mimeSupport('image/png; charset=binary'), 2);
    });

    test('a subtype wildcard covers the rest of its type', () {
      expect(features.mimeSupport('image/bmp'), 1);
      expect(features.mimeSupport('text/plain'), 2);
      expect(features.mimeSupport('video/mp4'), -2);
    });

    test('a type with no matching key is rejected', () {
      expect(features.mimeSupport('application/pdf'), CapabilityLevel.rejected);
    });

    test('*/* covers everything not listed more specifically', () {
      const any = FileFeatures(mimeTypes: {'*/*': 2, 'image/bmp': -2});
      expect(any.mimeSupport('application/zip'), 2);
      expect(any.mimeSupport('image/bmp'), -2);
    });
  });

  group('CapabilityLevel', () {
    test('usable is 0 and up, rejects is -2 and below', () {
      expect([-3, -2, -1, 0, 1, 2].map(CapabilityLevel.usable), [
        false,
        false,
        false,
        true,
        true,
        true,
      ]);
      expect([-3, -2, -1, 0, 1, 2].map(CapabilityLevel.rejects), [
        true,
        true,
        false,
        false,
        false,
        false,
      ]);
    });
  });

  group('RoomFeatures.fromJson', () {
    test('parses the iMessage room', () {
      final features = RoomFeatures.fromJson(iMessageFeatures);
      expect(features.isUnrestricted, isFalse);
      expect(features.maxSize('m.file'), 2097152000);
      expect(features.maxSize('m.image'), isNull);
      expect(features.acceptsMime('m.image', 'image/heic'), isTrue);
      expect(features.acceptsMime('m.image', 'image/bmp'), isFalse);
      expect(features.rejectsMime('m.image', 'image/bmp'), isTrue);
      expect(features.acceptsMime('m.video', 'video/quicktime'), isTrue);
      expect(features.mimeSupport('m.video', 'video/quicktime'), 1);
      expect(features.acceptsMime('m.file', 'image/bmp'), isTrue);
      expect(features.acceptsMime('m.audio', 'audio/ogg'), isTrue);
      expect(features.acceptsCaption('m.image'), isTrue);
    });

    test('parses the Google Messages room', () {
      final features = RoomFeatures.fromJson(googleMessagesFeatures);
      expect(features.maxSize('m.file'), 104857600);
      expect(features.acceptsMime('m.image', 'image/bmp'), isTrue);
      expect(features.acceptsMime('m.video', 'video/quicktime'), isFalse);
      expect(features.acceptsMime('m.video', 'video/mp4'), isTrue);
      expect(features.acceptsMime('m.file', 'application/pdf'), isTrue);
      expect(features.acceptsMime('m.file', 'video/quicktime'), isFalse);
    });

    test('a message type the room does not list is rejected', () {
      final features = RoomFeatures.fromJson(googleMessagesFeatures);
      expect(features.featuresFor('m.audio'), isNull);
      expect(features.rejectsMime('m.audio', 'audio/ogg'), isTrue);
      expect(features.rejectsMime(CapabilityMsgType.voice, 'audio/ogg'), true);
    });

    test('caption levels: absent and 0 to 2 are kept, -1 and -2 are not', () {
      Map<String, Object?> withCaption(Object? level) => {
        'file': {
          'm.image': {
            'mime_types': {'image/png': 2},
            'caption': ?level,
          },
        },
      };
      bool accepts(Object? level) =>
          RoomFeatures.fromJson(withCaption(level)).acceptsCaption('m.image');
      expect(accepts(null), isTrue);
      expect(accepts(0), isTrue);
      expect(accepts(1), isTrue);
      expect(accepts(2), isTrue);
      expect(accepts(-1), isFalse);
      expect(accepts(-2), isFalse);
    });

    test('a non-positive max_size means no limit', () {
      final features = RoomFeatures.fromJson({
        'file': {
          'm.file': {'mime_types': {}, 'max_size': 0},
        },
      });
      expect(features.maxSize('m.file'), isNull);
    });

    test('content without a file object is unrestricted', () {
      for (final content in <Object?>[
        null,
        'not an object',
        42,
        <String, Object?>{},
        {'file': 'nope'},
        {
          'file': ['m.image'],
        },
        {'formatting': <String, Object?>{}},
      ]) {
        final features = RoomFeatures.fromJson(content);
        expect(features.isUnrestricted, isTrue, reason: '$content');
        expect(features.acceptsMime('m.image', 'image/bmp'), isTrue);
        expect(features.acceptsCaption('m.image'), isTrue);
        expect(features.maxSize('m.file'), isNull);
      }
    });

    test('malformed entries and members are skipped', () {
      final features = RoomFeatures.fromJson({
        'file': {
          'm.image': 'not an object',
          'm.video': {
            'mime_types': {'video/mp4': '2', 'video/webm': 2, '*/*': null},
            'caption': 'yes',
            'max_size': '100',
          },
        },
      });
      expect(features.isUnrestricted, isFalse);
      expect(features.featuresFor('m.image'), isNull);
      expect(features.acceptsMime('m.video', 'video/webm'), isTrue);
      expect(features.acceptsMime('m.video', 'video/mp4'), isFalse);
      expect(features.acceptsCaption('m.video'), isTrue);
      expect(features.maxSize('m.video'), isNull);
    });

    test('mime keys are matched without regard to case', () {
      final features = RoomFeatures.fromJson({
        'file': {
          'm.image': {
            'mime_types': {'Image/PNG': 2},
          },
        },
      });
      expect(features.acceptsMime('m.image', 'image/png'), isTrue);
    });

    test('usableMimeTypes lists only usable levels', () {
      const features = FileFeatures(
        mimeTypes: {'video/mp4': 2, 'video/3gpp': 0, 'video/avi': -1},
      );
      expect(features.usableMimeTypes, ['video/mp4', 'video/3gpp']);
    });
  });

  group('RoomFeatures.of', () {
    late Client client;
    setUp(() async => client = await fakeMergedClient());
    tearDown(() async => client.dispose(closeDatabase: true));

    Event featuresEvent(Room room, String stateKey, Object content, int ts) =>
        Event(
          type: RoomFeatures.eventType,
          content: content as Map<String, Object?>,
          eventId: '\$$stateKey-$ts',
          senderId: '@bridge:example.org',
          originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
          stateKey: stateKey,
          room: room,
        );

    test('a room without the event is unrestricted', () {
      final room = Room(id: '!plain:example.org', client: client);
      expect(RoomFeatures.of(room).isUnrestricted, isTrue);
    });

    test('reads the event under a non-empty state key', () {
      final room = Room(id: '!imsg:example.org', client: client);
      room.setState(
        featuresEvent(room, 'fi.mau.imessage://x', iMessageFeatures, 1),
      );
      final features = RoomFeatures.of(room);
      expect(features.isUnrestricted, isFalse);
      expect(features.acceptsMime('m.image', 'image/bmp'), isFalse);
    });

    test('the newest event wins across state keys', () {
      final room = Room(id: '!two:example.org', client: client);
      room.setState(featuresEvent(room, 'old', iMessageFeatures, 1000));
      room.setState(featuresEvent(room, 'new', googleMessagesFeatures, 2000));
      expect(RoomFeatures.of(room).acceptsMime('m.image', 'image/bmp'), isTrue);

      final reversed = Room(id: '!three:example.org', client: client);
      reversed.setState(
        featuresEvent(reversed, 'new', googleMessagesFeatures, 1000),
      );
      reversed.setState(featuresEvent(reversed, 'old', iMessageFeatures, 2000));
      expect(
        RoomFeatures.of(reversed).acceptsMime('m.image', 'image/bmp'),
        isFalse,
      );
    });

    test('load keeps the state already in memory', () {
      final room = Room(id: '!partial:example.org', client: client);
      room.setState(featuresEvent(room, 'bridge', iMessageFeatures, 1));
      return expectLater(
        RoomFeatures.load(room).then((f) => f.isUnrestricted),
        completion(isFalse),
      );
    });
  });
}
