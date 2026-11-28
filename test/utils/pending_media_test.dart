// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/pending_media.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'message_search/search_test_client.dart';
import 'pending_media_fixtures.dart';

void main() {
  late Room room;

  setUpAll(() async {
    final client = await createSearchTestClient();
    room = client.getRoomById('!726s6s6q:example.com')!;
  });

  Event notice(
    String body, {
    String sender = '@gmessages_15551234567:example.com',
    Map<String, Object?> extra = const {},
    String msgtype = MessageTypes.Notice,
  }) => Event(
    content: {'msgtype': msgtype, 'body': body, ...extra},
    type: EventTypes.Message,
    eventId: r'$placeholder',
    senderId: sender,
    originServerTs: DateTime.fromMillisecondsSinceEpoch(1000),
    room: room,
  );

  final debugData = rawDebugData([
    mediaContent(name: 'PXL_1.jpg', width: 3024, height: 4032),
  ]);

  group('detection', () {
    test('the media_pending flag marks a placeholder from any sender', () {
      final media = PendingMedia.of(
        notice(
          'Waiting for attachment PXL_1.jpg',
          sender: '@gray:example.com',
          extra: {PendingMedia.pendingKey: true},
        ),
      )!;
      expect(media.state, PendingMediaState.pending);
      expect(media.fileName, 'PXL_1.jpg');
      expect(media.kind, PendingMediaKind.image);
    });

    test('without the flag, a gmessages notice with debug data counts', () {
      final media = PendingMedia.of(
        notice(
          'Waiting for attachment clip.mp4',
          extra: {PendingMedia.rawDebugDataKey: debugData},
        ),
      )!;
      expect(media.state, PendingMediaState.pending);
      expect(media.kind, PendingMediaKind.video);
    });

    test('the same text from anyone else stays a notice', () {
      expect(
        PendingMedia.of(
          notice(
            'Waiting for attachment PXL_1.jpg',
            sender: '@whatsappbot:example.com',
            extra: {PendingMedia.rawDebugDataKey: debugData},
          ),
        ),
        isNull,
      );
      expect(
        PendingMedia.of(notice('Waiting for attachment PXL_1.jpg')),
        isNull,
        reason: 'a gmessages notice needs the debug data or the flag',
      );
      expect(
        PendingMedia.of(
          notice(
            'Waiting for attachment PXL_1.jpg',
            msgtype: MessageTypes.Text,
            extra: {PendingMedia.rawDebugDataKey: debugData},
          ),
        ),
        isNull,
        reason: 'only a notice is a placeholder',
      );
      expect(PendingMedia.of(notice('Hello there')), isNull);
    });

    test('a failed transfer is the failed state', () {
      final media = PendingMedia.of(
        notice('Failed to transfer attachment IMG_2.png'),
      )!;
      expect(media.state, PendingMediaState.failed);
      expect(media.fileName, 'IMG_2.png');
      expect(media.kind, PendingMediaKind.image);
      expect(
        PendingMedia.of(
          notice(
            'Failed to transfer attachment IMG_2.png',
            sender: '@someone:example.com',
          ),
        ),
        isNull,
      );
    });

    test('a name without a media extension is a file', () {
      final media = PendingMedia.of(
        notice(
          'Waiting for attachment contact.vcf',
          extra: {PendingMedia.pendingKey: true},
        ),
      )!;
      expect(media.kind, PendingMediaKind.file);
    });
  });

  group('a name without an extension', () {
    // Google Messages often names an attachment by a number.
    const name = '4308013893108320279';

    test('takes its kind from the debug data\'s MIME type', () {
      final media = PendingMedia.of(
        notice(
          'Waiting for attachment $name',
          extra: {
            PendingMedia.pendingKey: true,
            PendingMedia.rawDebugDataKey: rawDebugData([
              mediaContent(name: name, mimeType: 'video/mp4'),
            ]),
          },
        ),
      )!;
      expect(media.kind, PendingMediaKind.video);
    });

    test('reads Attachment without it, never the number', () async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final media = PendingMedia.of(
        notice(
          'Waiting for attachment $name',
          extra: {PendingMedia.pendingKey: true},
        ),
      )!;
      expect(media.kind, PendingMediaKind.file);
      expect(media.previewText(l10n), 'Attachment');
    });

    test('a file with an extension still reads by its name', () async {
      final l10n = await L10n.delegate.load(const Locale('en'));
      final media = PendingMedia.of(
        notice(
          'Waiting for attachment contact.vcf',
          extra: {PendingMedia.pendingKey: true},
        ),
      )!;
      expect(media.previewText(l10n), 'contact.vcf');
    });
  });

  group('aspect hint', () {
    Event withData(String data, {String name = 'PXL_1.jpg'}) => notice(
      'Waiting for attachment $name',
      extra: {
        PendingMedia.pendingKey: true,
        PendingMedia.rawDebugDataKey: data,
      },
    );

    test('comes from the named part of the debug data', () {
      final data = rawDebugData([
        mediaContent(name: 'other.jpg', width: 4032, height: 3024),
        mediaContent(name: 'PXL_1.jpg', width: 3024, height: 4032),
      ]);
      expect(PendingMedia.of(withData(data))!.aspectRatio, 3024 / 4032);
    });

    test('a video gives its shape too', () {
      final data = rawDebugData([
        mediaContent(
          name: 'clip.mp4',
          mimeType: 'video/mp4',
          width: 2160,
          height: 3840,
        ),
      ]);
      final media = PendingMedia.of(withData(data, name: 'clip.mp4'))!;
      expect(media.kind, PendingMediaKind.video);
      expect(media.aspectRatio, 2160 / 3840);
    });

    test('is left out when missing, implausible or unreadable', () {
      expect(
        PendingMedia.of(
          withData(rawDebugData([mediaContent(name: 'PXL_1.jpg')])),
        )!.aspectRatio,
        isNull,
      );
      expect(
        PendingMedia.of(
          withData(
            rawDebugData([
              mediaContent(name: 'PXL_1.jpg', width: 4000, height: 10),
            ]),
          ),
        )!.aspectRatio,
        isNull,
      );
      final truncated = base64.encode(base64.decode(debugData).sublist(0, 12));
      final media = PendingMedia.of(withData(truncated))!;
      expect(media.state, PendingMediaState.pending);
      expect(media.aspectRatio, isNull);
      expect(PendingMedia.of(withData('not base64!'))!.aspectRatio, isNull);
    });
  });

  group('preview', () {
    Event withPreview(List<int> preview) => notice(
      'Waiting for attachment PXL_1.jpg',
      extra: {
        PendingMedia.pendingKey: true,
        PendingMedia.rawDebugDataKey: rawDebugData([
          mediaContent(
            name: 'PXL_1.jpg',
            width: 3024,
            height: 4032,
            preview: preview,
          ),
        ]),
      },
    );

    test('a JPEG preview is kept', () {
      final jpeg = previewJpeg();
      expect(PendingMedia.of(withPreview(jpeg))!.preview, jpeg);
    });

    test('anything else, or one too large, is dropped', () {
      expect(
        PendingMedia.of(withPreview(utf8.encode('not a picture')))!.preview,
        isNull,
      );
      final huge = [0xFF, 0xD8, 0xFF, ...List.filled(20 * 1024, 0)];
      expect(PendingMedia.of(withPreview(huge))!.preview, isNull);
    });

    test('a failed transfer shows no preview', () {
      final media = PendingMedia.of(
        notice(
          'Failed to transfer attachment PXL_1.jpg',
          extra: {
            PendingMedia.rawDebugDataKey: rawDebugData([
              mediaContent(name: 'PXL_1.jpg', preview: previewJpeg()),
            ]),
          },
        ),
      )!;
      expect(media.state, PendingMediaState.failed);
      expect(media.preview, isNull);
    });
  });
}
