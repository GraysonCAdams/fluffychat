// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/notification_media.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'message_search/search_test_client.dart';

const _authority = 'chat.fluffy.fluffychat.fork.notification_media';

void main() {
  late Client client;
  late Room room;
  late Directory directory;
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

  setUpAll(() async {
    client = await createSearchTestClient();
    room = client.getRoomById('!726s6s6q:example.com')!;
  });

  setUp(() async {
    directory = await Directory.systemTemp.createTemp('notification_media');
  });

  tearDown(() => directory.delete(recursive: true));

  Event event(
    Map<String, Object?> content, {
    String id = r'$photo',
    int ts = 1000,
  }) => Event(
    content: content,
    type: EventTypes.Message,
    eventId: id,
    senderId: '@bob:example.com',
    originServerTs: DateTime.fromMillisecondsSinceEpoch(ts),
    room: room,
  );

  Event image({Map<String, Object?> extra = const {}}) => event({
    'msgtype': MessageTypes.Image,
    'body': 'IMG.jpg',
    'url': 'mxc://example.com/photo',
    'info': {'mimetype': 'image/jpeg', 'size': jpeg.length},
    ...extra,
  });

  Future<NotificationMedia?> mediaOf(
    Event event, {
    NotificationMediaDownloader? downloader,
  }) => notificationMediaOf(
    event,
    downloader:
        downloader ??
        (_) async => MatrixFile(bytes: jpeg, name: 'p.jpg', mimeType: 'image/jpeg'),
    directory: () async => directory,
    authority: () async => _authority,
  );

  final person = Person(key: '@bob:example.com', name: 'Bob');

  test('an image gives its message a picture the system UI can read', () async {
    final photo = image();
    final media = await mediaOf(photo);
    final message = notificationMessage(
      photo,
      body: 'Bob sent a picture',
      person: person,
      media: media,
    );

    expect(message.dataMimeType, 'image/jpeg');
    expect(
      message.dataUri,
      startsWith('content://$_authority/$notificationMediaPathName/'),
    );
    final name = Uri.parse(message.dataUri!).pathSegments.last;
    expect(File('${directory.path}/$name').readAsBytesSync(), jpeg);
  });

  test('a video shows its poster, and a video without one shows text', () async {
    final video = event({
      'msgtype': MessageTypes.Video,
      'body': 'clip.mp4',
      'url': 'mxc://example.com/clip',
      'info': {
        'mimetype': 'video/mp4',
        'thumbnail_url': 'mxc://example.com/poster',
        'thumbnail_info': {'mimetype': 'image/jpeg', 'size': jpeg.length},
      },
    });
    Event? asked;
    final media = await mediaOf(
      video,
      downloader: (e) async {
        asked = e;
        return MatrixFile(bytes: jpeg, name: 'p.jpg', mimeType: 'image/jpeg');
      },
    );
    expect(media?.mimeType, 'image/jpeg');
    expect(asked?.messageType, MessageTypes.Video);

    final bare = event({
      'msgtype': MessageTypes.Video,
      'body': 'clip.mp4',
      'url': 'mxc://example.com/clip',
      'info': {'mimetype': 'video/mp4'},
    });
    expect(await downloadNotificationMedia(bare), isNull);
  });

  test('a text message has no picture', () async {
    final text = event({'msgtype': MessageTypes.Text, 'body': 'hi'});
    expect(hasNotificationMedia(text), isFalse);
    expect(await mediaOf(text), isNull);
  });

  test('Invisible Ink never carries a picture', () async {
    final ink = image(
      extra: {messageEffectKey: MessageEffect.invisibleInk.id},
    );
    var asked = false;
    final media = await mediaOf(
      ink,
      downloader: (_) async {
        asked = true;
        return MatrixFile(bytes: jpeg, name: 'p.jpg', mimeType: 'image/jpeg');
      },
    );
    final message = notificationMessage(
      ink,
      body: 'Sent with Invisible Ink',
      person: person,
      media: media,
    );

    expect(asked, isFalse);
    expect(message.dataUri, isNull);
    expect(message.dataMimeType, isNull);
    expect(message.text, 'Sent with Invisible Ink');
    expect(directory.listSync(), isEmpty);
  });

  test('a download that fails leaves the text message', () async {
    final photo = image();
    final failing = await mediaOf(
      photo,
      downloader: (_) async => throw Exception('offline'),
    );
    final timedOut = await notificationMediaOf(
      photo,
      downloader: (_) => Completer<MatrixFile?>().future,
      directory: () async => directory,
      authority: () async => _authority,
      timeout: const Duration(milliseconds: 10),
    );
    final bad = await mediaOf(
      photo,
      downloader: (_) async =>
          MatrixFile(bytes: jpeg, name: 'x.bin', mimeType: 'application/pdf'),
    );

    for (final media in [failing, timedOut, bad]) {
      expect(media, isNull);
      final message = notificationMessage(
        photo,
        body: 'Bob sent a picture',
        person: person,
        media: media,
      );
      expect(message.text, 'Bob sent a picture');
      expect(message.dataUri, isNull);
    }
  });

  test('a picture over the size cap is not fetched', () async {
    final big = image(
      extra: {
        'info': {'mimetype': 'image/jpeg', 'size': 5 * 1024 * 1024},
        'file': {'url': 'mxc://example.com/photo'},
      },
    );
    expect(await downloadNotificationMedia(big), isNull);
  });

  group('the bridge placeholder and its edit', () {
    Event placeholder() => event({
      'msgtype': MessageTypes.Notice,
      'body': 'Waiting for attachment abc',
    }, id: r'$placeholder', ts: 5000);

    Event edit() => event({
      'msgtype': MessageTypes.Notice,
      'body': '* Waiting for attachment abc',
      'm.new_content': {
        'msgtype': MessageTypes.Image,
        'body': 'IMG.jpg',
        'url': 'mxc://example.com/photo',
        'info': {'mimetype': 'image/jpeg', 'size': jpeg.length},
      },
      'm.relates_to': {
        'rel_type': RelationshipTypes.edit,
        'event_id': r'$placeholder',
      },
    }, id: r'$edit', ts: 7000);

    test('the edit reads as the picture', () {
      expect(hasNotificationMedia(edit()), isTrue);
      expect(effectiveEvent(edit()).messageType, MessageTypes.Image);
      expect(hasNotificationMedia(placeholder()), isFalse);
    });

    test('takes the placeholder\'s line instead of adding one', () async {
      final first = notificationMessage(
        placeholder(),
        body: 'Waiting for attachment abc',
        person: person,
      );
      final other = Message(
        'later',
        DateTime.fromMillisecondsSinceEpoch(6000),
        Person(key: '@alice:example.com', name: 'Alice'),
      );
      final photo = edit();
      final media = await mediaOf(photo);
      final second = notificationMessage(
        photo,
        body: 'Bob sent a picture',
        person: person,
        media: media,
      );

      final lines = withNotificationMessage(
        [first, other],
        second,
        replacedTime: DateTime.fromMillisecondsSinceEpoch(5000),
      );

      expect(lines, hasLength(2));
      expect(lines.first.text, 'Bob sent a picture');
      expect(lines.first.dataUri, isNotNull);
      expect(lines.any((m) => m.text.startsWith('Waiting')), isFalse);
    });

    test('is added when the placeholder is not on screen', () {
      final photo = notificationMessage(
        edit(),
        body: 'Bob sent a picture',
        person: person,
      );
      final lines = withNotificationMessage(
        [],
        photo,
        replacedTime: DateTime.fromMillisecondsSinceEpoch(5000),
      );
      expect(lines, [photo]);
    });
  });
}
