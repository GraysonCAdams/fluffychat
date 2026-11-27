// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages, implementation_imports

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/notification_media.dart';
import 'package:fluffychat/utils/windows_toast_images.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_local_notifications_windows/src/details/notification_to_xml.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'message_search/search_test_client.dart';

void main() {
  late Client client;
  late Room room;
  late Directory directory;
  final jpeg = Uint8List.fromList([0xff, 0xd8, 0xff, 0xe0, 1, 2, 3]);

  setUpAll(() async {
    client = await createSearchTestClient();
    room = client.getRoomById('!726s6s6q:example.com')!;
  });

  setUp(() => directory = Directory.systemTemp.createTempSync('toast_media'));
  tearDown(() => directory.deleteSync(recursive: true));

  Event image({Map<String, Object?> extra = const {}}) => Event(
    content: {
      'msgtype': MessageTypes.Image,
      'body': 'IMG.jpg',
      'url': 'mxc://example.com/photo',
      'info': {'mimetype': 'image/jpeg', 'size': jpeg.length},
      ...extra,
    },
    type: EventTypes.Message,
    eventId: r'$photo',
    senderId: '@bob:example.com',
    originServerTs: DateTime(2026, 11, 27),
    room: room,
  );

  Future<Uri?> fileOf(
    Event event, {
    NotificationMediaDownloader? downloader,
    Duration timeout = const Duration(seconds: 5),
  }) => notificationMediaFileOf(
    event,
    directory: () async => directory,
    timeout: timeout,
    downloader:
        downloader ??
        (_) async =>
            MatrixFile(bytes: jpeg, name: 'p.jpg', mimeType: 'image/jpeg'),
  );

  String xmlOf({Uri? media}) => notificationToXml(
    title: 'Bob',
    body: 'Bob sent a picture',
    notificationDetails: WindowsNotificationDetails(
      images: windowsToastImages(
        avatar: Uri.file(r'C:\avatar.png', windows: true),
        title: 'Bob',
        roundAvatar: true,
        media: media,
        mediaAltText: 'Bob sent a picture',
      ),
    ),
  );

  group('the toast XML', () {
    test('has the picture inline under the text and the avatar as logo', () {
      final xml = xmlOf(media: Uri.file(r'C:\media\photo.jpg', windows: true));

      final images = RegExp('<image [^>]*>').allMatches(xml).toList();
      expect(images, hasLength(2));
      expect(images[0][0], contains('placement="appLogoOverride"'));
      expect(images[0][0], contains('hint-crop="circle"'));
      expect(images[1][0], contains('file:///C:/media/photo.jpg'));
      expect(images[1][0], isNot(contains('placement')));
      expect(images[1][0], isNot(contains('hero')));
      expect(xml.indexOf('<text>'), lessThan(xml.indexOf(images[1][0]!)));
    });

    test('has only the avatar without a picture', () {
      final xml = xmlOf();
      expect(RegExp('<image ').allMatches(xml), hasLength(1));
      expect(xml, contains('appLogoOverride'));
    });
  });

  group('the picture of a toast', () {
    test('is a file the toast can name', () async {
      final uri = await fileOf(image());

      expect(uri, isNotNull);
      expect(uri!.scheme, 'file');
      expect(File.fromUri(uri).readAsBytesSync(), jpeg);
      expect(File.fromUri(uri).parent.path, directory.path);
    });

    test('is none for Invisible Ink', () async {
      var asked = false;
      final uri = await fileOf(
        image(extra: {messageEffectKey: MessageEffect.invisibleInk.id}),
        downloader: (_) async {
          asked = true;
          return MatrixFile(bytes: jpeg, name: 'p.jpg', mimeType: 'image/jpeg');
        },
      );

      expect(uri, isNull);
      expect(asked, isFalse);
      expect(directory.listSync(), isEmpty);
    });

    test('is none for a text message', () async {
      final text = Event(
        content: {'msgtype': MessageTypes.Text, 'body': 'hi'},
        type: EventTypes.Message,
        eventId: r'$text',
        senderId: '@bob:example.com',
        originServerTs: DateTime(2026, 11, 27),
        room: room,
      );
      expect(await fileOf(text), isNull);
    });

    test('is none when the download fails or is too slow', () async {
      expect(
        await fileOf(image(), downloader: (_) async => throw Exception('x')),
        isNull,
      );
      expect(
        await fileOf(
          image(),
          downloader: (_) => Completer<MatrixFile?>().future,
          timeout: const Duration(milliseconds: 10),
        ),
        isNull,
      );
    });

    test('is none for a format a toast cannot draw', () async {
      expect(
        await fileOf(
          image(),
          downloader: (_) async =>
              MatrixFile(bytes: jpeg, name: 'p.webp', mimeType: 'image/webp'),
        ),
        isNull,
      );
    });

    test('of a bridge edit is the new content', () async {
      final edit = Event(
        content: {
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
        },
        type: EventTypes.Message,
        eventId: r'$edit',
        senderId: '@bob:example.com',
        originServerTs: DateTime(2026, 11, 27),
        room: room,
      );
      expect(await fileOf(edit), isNotNull);
    });
  });
}
