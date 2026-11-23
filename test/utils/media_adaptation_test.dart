// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/utils/media_adaptation.dart';
import 'package:fluffychat/utils/room_features.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'room_features_fixtures.dart';

final iMessage = RoomFeatures.fromJson(iMessageFeatures);
final googleMessages = RoomFeatures.fromJson(googleMessagesFeatures);
final noCaptions = RoomFeatures.fromJson(noCaptionFeatures);

/// A 2x2 24-bit BMP: red, green, blue and white pixels.
Uint8List tinyBmp() {
  final pixels = <int>[
    // Bottom row first, BGR, each row padded to 4 bytes.
    0x00, 0x00, 0xFF, 0x00, 0xFF, 0x00, 0, 0, //
    0xFF, 0x00, 0x00, 0xFF, 0xFF, 0xFF, 0, 0,
  ];
  final header = ByteData(54)
    ..setUint8(0, 0x42)
    ..setUint8(1, 0x4D)
    ..setUint32(2, 54 + pixels.length, Endian.little)
    ..setUint32(10, 54, Endian.little)
    ..setUint32(14, 40, Endian.little)
    ..setInt32(18, 2, Endian.little)
    ..setInt32(22, 2, Endian.little)
    ..setUint16(26, 1, Endian.little)
    ..setUint16(28, 24, Endian.little)
    ..setUint32(34, pixels.length, Endian.little);
  return Uint8List.fromList([...header.buffer.asUint8List(), ...pixels]);
}

MatrixFile bmp() => MatrixImageFile(
  bytes: Uint8List.fromList([1, 2, 3]),
  name: 'drawing.bmp',
  mimeType: 'image/bmp',
);

MatrixFile mov([int size = 3]) => MatrixVideoFile(
  bytes: Uint8List(size),
  name: 'clip.mov',
  mimeType: 'video/quicktime',
);

void main() {
  group('planMediaFormat', () {
    MediaFormatPlan plan(
      RoomFeatures features,
      String msgType,
      String mime, {
      bool canConvertVideo = false,
      bool allowFileFallback = true,
    }) => planMediaFormat(
      features,
      msgType: msgType,
      mimeType: mime,
      canConvertVideo: canConvertVideo,
      allowFileFallback: allowFileFallback,
    );

    const keep = MediaFormatPlan(MediaFormatAction.keep);

    test('an unrestricted room keeps everything', () {
      expect(plan(RoomFeatures.unrestricted, 'm.image', 'image/bmp'), keep);
      expect(plan(RoomFeatures.unrestricted, 'm.video', 'video/x-xyz'), keep);
    });

    test('an accepted type is kept, including partial support', () {
      expect(plan(iMessage, 'm.image', 'image/png'), keep);
      expect(plan(iMessage, 'm.video', 'video/quicktime'), keep);
      expect(plan(googleMessages, 'm.image', 'image/bmp'), keep);
    });

    test('a BMP for iMessage becomes PNG, else a file', () {
      expect(
        plan(iMessage, 'm.image', 'image/bmp'),
        const MediaFormatPlan(
          MediaFormatAction.convertToPng,
          fallback: MediaFormatAction.sendAsFile,
        ),
      );
    });

    test('a MOV for Google Messages becomes MP4 where possible', () {
      expect(
        plan(
          googleMessages,
          'm.video',
          'video/quicktime',
          canConvertVideo: true,
        ),
        const MediaFormatPlan(
          MediaFormatAction.convertToMp4,
          fallback: MediaFormatAction.refuse,
        ),
      );
    });

    test('a MOV for Google Messages without a transcoder is refused', () {
      expect(
        plan(googleMessages, 'm.video', 'video/quicktime'),
        const MediaFormatPlan(MediaFormatAction.refuse),
      );
    });

    test('a video type the room takes as a file goes as a file', () {
      expect(
        plan(iMessage, 'm.video', 'video/x-msvideo'),
        const MediaFormatPlan(MediaFormatAction.sendAsFile),
      );
    });

    test('no conversion to a format the room does not take either', () {
      final noPng = RoomFeatures.fromJson({
        'file': {
          'm.image': {
            'mime_types': {'image/jpeg': 2},
          },
        },
      });
      expect(
        plan(noPng, 'm.image', 'image/bmp'),
        const MediaFormatPlan(MediaFormatAction.refuse),
      );
      final noMp4 = RoomFeatures.fromJson({
        'file': {
          'm.video': {
            'mime_types': {'video/webm': 2},
          },
        },
      });
      expect(
        plan(noMp4, 'm.video', 'video/quicktime', canConvertVideo: true),
        const MediaFormatPlan(MediaFormatAction.refuse),
      );
    });

    test('a dropped type with no alternative is sent unchanged', () {
      final dropped = RoomFeatures.fromJson({
        'file': {
          'm.audio': {
            'mime_types': {'audio/flac': -1},
          },
        },
      });
      expect(plan(dropped, 'm.audio', 'audio/flac'), keep);
    });

    test('a type at level 0 is kept', () {
      final zero = RoomFeatures.fromJson({
        'file': {
          'm.image': {
            'mime_types': {'image/bmp': 0, 'image/png': 2},
          },
        },
      });
      expect(plan(zero, 'm.image', 'image/bmp'), keep);
    });

    test('a negative level forces a conversion', () {
      for (final level in [-1, -2]) {
        final negative = RoomFeatures.fromJson({
          'file': {
            'm.image': {
              'mime_types': {'image/bmp': level, 'image/png': 2},
            },
          },
        });
        expect(
          plan(negative, 'm.image', 'image/bmp').action,
          MediaFormatAction.convertToPng,
          reason: 'level $level',
        );
      }
    });

    test('a missing message type falls back to a file', () {
      expect(
        plan(googleMessages, 'm.audio', 'application/ogg'),
        const MediaFormatPlan(MediaFormatAction.sendAsFile),
      );
      expect(
        plan(googleMessages, 'm.audio', 'audio/ogg'),
        const MediaFormatPlan(MediaFormatAction.refuse),
      );
    });

    test('voice without the file fallback is refused where not listed', () {
      expect(
        plan(
          iMessage,
          CapabilityMsgType.voice,
          'audio/ogg',
          allowFileFallback: false,
        ),
        const MediaFormatPlan(MediaFormatAction.refuse),
      );
    });
  });

  group('captionNeedsOwnMessage and exceededSizeLimit', () {
    test('a caption is split only where the room refuses it', () {
      expect(
        captionNeedsOwnMessage(
          noCaptions,
          msgType: 'm.image',
          hasCaption: true,
        ),
        isTrue,
      );
      expect(
        captionNeedsOwnMessage(
          noCaptions,
          msgType: 'm.image',
          hasCaption: false,
        ),
        isFalse,
      );
      expect(
        captionNeedsOwnMessage(
          googleMessages,
          msgType: 'm.image',
          hasCaption: true,
        ),
        isFalse,
      );
      expect(
        captionNeedsOwnMessage(
          RoomFeatures.unrestricted,
          msgType: 'm.image',
          hasCaption: true,
        ),
        isFalse,
      );
    });

    test('the size limit applies only above max_size', () {
      expect(
        exceededSizeLimit(googleMessages, msgType: 'm.file', size: 104857600),
        isNull,
      );
      expect(
        exceededSizeLimit(googleMessages, msgType: 'm.file', size: 104857601),
        104857600,
      );
      expect(
        exceededSizeLimit(googleMessages, msgType: 'm.image', size: 1 << 40),
        isNull,
      );
    });
  });

  group('adaptMediaForRoom', () {
    Future<Uint8List?> fakePng(Uint8List bytes) async =>
        Uint8List.fromList([9, 9]);
    Future<Uint8List?> failingPng(Uint8List bytes) async => null;

    test('an unrestricted room gets the same objects back', () async {
      final file = bmp();
      final thumbnail = MatrixImageFile(bytes: Uint8List(1), name: 't.jpg');
      final adapted = await adaptMediaForRoom(
        features: RoomFeatures.unrestricted,
        file: file,
        thumbnail: thumbnail,
        hasCaption: true,
        convertImage: (_) => fail('must not convert'),
      );
      expect(adapted.file, same(file));
      expect(adapted.thumbnail, same(thumbnail));
      expect(adapted.extraContent, isNull);
      expect(adapted.captionSeparately, isFalse);
    });

    test('a BMP for iMessage is sent as a PNG image', () async {
      final adapted = await adaptMediaForRoom(
        features: iMessage,
        file: bmp(),
        convertImage: fakePng,
      );
      expect(adapted.file, isA<MatrixImageFile>());
      expect(adapted.file.name, 'drawing.png');
      expect(adapted.file.mimeType, 'image/png');
      expect(adapted.file.bytes, [9, 9]);
      expect(adapted.extraContent, isNull);
    });

    test('a BMP that will not convert goes to iMessage as a file', () async {
      final adapted = await adaptMediaForRoom(
        features: iMessage,
        file: bmp(),
        convertImage: failingPng,
      );
      expect(adapted.sentAsFile, isTrue);
      expect(adapted.file, isNot(isA<MatrixImageFile>()));
      expect(adapted.file.name, 'drawing.bmp');
      expect(adapted.file.mimeType, 'image/bmp');
      expect(adapted.extraContent, {'msgtype': 'm.file'});
    });

    test('a throwing converter counts as a failed conversion', () async {
      final adapted = await adaptMediaForRoom(
        features: iMessage,
        file: bmp(),
        convertImage: (_) => throw StateError('codec'),
      );
      expect(adapted.sentAsFile, isTrue);
    });

    test('a MOV for Google Messages is transcoded to MP4', () async {
      final adapted = await adaptMediaForRoom(
        features: googleMessages,
        file: mov(),
        thumbnail: MatrixImageFile(bytes: Uint8List(1), name: 't.jpg'),
        convertVideo: () async => MatrixVideoFile(
          bytes: Uint8List(5),
          name: 'clip.mov',
          mimeType: 'video/mp4',
          width: 640,
          height: 480,
          duration: 1000,
        ),
      );
      final file = adapted.file as MatrixVideoFile;
      expect(file.name, 'clip.mp4');
      expect(file.mimeType, 'video/mp4');
      expect(file.bytes.length, 5);
      expect(file.width, 640);
      expect(file.duration, 1000);
      expect(adapted.thumbnail, isNotNull);
      expect(adapted.extraContent, isNull);
    });

    test('a transcode that still yields MOV is refused', () async {
      await expectLater(
        adaptMediaForRoom(
          features: googleMessages,
          file: mov(),
          convertVideo: () async => mov(),
        ),
        throwsA(isA<MediaTypeNotAcceptedException>()),
      );
    });

    test('a MOV refused names the types the chat takes', () async {
      try {
        await adaptMediaForRoom(features: googleMessages, file: mov());
        fail('should refuse');
      } on MediaTypeNotAcceptedException catch (e) {
        expect(e.mimeType, 'video/quicktime');
        expect(e.msgType, 'm.video');
        expect(e.acceptedMimeTypes, ['video/mp4', 'video/3gpp', 'video/webm']);
      }
    });

    test(
      'a MOV the room takes as a file goes as a file, no thumbnail',
      () async {
        final room = RoomFeatures.fromJson({
          'file': {
            'm.video': {
              'mime_types': {'video/mp4': 2},
            },
            'm.file': {
              'mime_types': {'*/*': 2},
            },
          },
        });
        final adapted = await adaptMediaForRoom(
          features: room,
          file: mov(),
          thumbnail: MatrixImageFile(bytes: Uint8List(1), name: 't.jpg'),
        );
        expect(adapted.sentAsFile, isTrue);
        expect(adapted.thumbnail, isNull);
        expect(adapted.file.name, 'clip.mov');
      },
    );

    test(
      'a file over the limit of the type it is sent as is refused',
      () async {
        final room = RoomFeatures.fromJson({
          'file': {
            'm.video': {
              'mime_types': {'video/mp4': 2},
              'max_size': 1000,
            },
            'm.file': {
              'mime_types': {'*/*': 2},
              'max_size': 10,
            },
          },
        });
        await expectLater(
          adaptMediaForRoom(features: room, file: mov(11)),
          throwsA(
            isA<FileTooBigForChatException>()
                .having((e) => e.maxSize, 'maxSize', 10)
                .having((e) => e.size, 'size', 11),
          ),
        );
        final adapted = await adaptMediaForRoom(features: room, file: mov(10));
        expect(adapted.sentAsFile, isTrue);
      },
    );

    test('a caption is split where the room refuses captions', () async {
      final adapted = await adaptMediaForRoom(
        features: noCaptions,
        file: MatrixImageFile(
          bytes: Uint8List(1),
          name: 'a.png',
          mimeType: 'image/png',
        ),
        hasCaption: true,
      );
      expect(adapted.captionSeparately, isTrue);
      final kept = await adaptMediaForRoom(
        features: googleMessages,
        file: MatrixImageFile(
          bytes: Uint8List(1),
          name: 'a.png',
          mimeType: 'image/png',
        ),
        hasCaption: true,
      );
      expect(kept.captionSeparately, isFalse);
    });

    test('the caption check uses the type actually sent', () async {
      final room = RoomFeatures.fromJson({
        'file': {
          'm.image': {
            'mime_types': {'image/jpeg': 2},
            'caption': 2,
          },
          'm.file': {
            'mime_types': {'*/*': 2},
            'caption': -2,
          },
        },
      });
      final adapted = await adaptMediaForRoom(
        features: room,
        file: bmp(),
        hasCaption: true,
      );
      expect(adapted.sentAsFile, isTrue);
      expect(adapted.captionSeparately, isTrue);
    });

    test('voice the room does not list is refused, not sent as a file', () {
      return expectLater(
        adaptMediaForRoom(
          features: iMessage,
          file: MatrixAudioFile(
            bytes: Uint8List(1),
            name: 'voice.ogg',
            mimeType: 'audio/ogg',
          ),
          msgType: CapabilityMsgType.voice,
          allowFileFallback: false,
        ),
        throwsA(isA<MediaTypeNotAcceptedException>()),
      );
    });

    test('mergeExtraContent puts the msgtype over the caller content', () {
      const asFile = AdaptedMedia(
        file: _dummy,
        extraContent: {'msgtype': 'm.file'},
      );
      expect(asFile.mergeExtraContent({'body': 'hi'}), {
        'body': 'hi',
        'msgtype': 'm.file',
      });
      expect(asFile.mergeExtraContent(null), {'msgtype': 'm.file'});
      const plain = AdaptedMedia(file: _dummy);
      expect(plain.mergeExtraContent({'body': 'hi'}), {'body': 'hi'});
      expect(plain.mergeExtraContent(null), isNull);
    });
  });

  testWidgets('encodeImageAsPng turns a BMP into a PNG', (tester) async {
    final png = await tester.runAsync(() => encodeImageAsPng(tinyBmp()));
    expect(png, isNotNull);
    expect(png!.sublist(0, 8), [
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ]);
  });

  testWidgets('encodeImageAsPng returns null for bytes it cannot decode', (
    tester,
  ) async {
    final png = await tester.runAsync(
      () => encodeImageAsPng(Uint8List.fromList([1, 2, 3, 4])),
    );
    expect(png, isNull);
  });
}

const _dummy = _DummyFile();

class _DummyFile implements MatrixFile {
  const _DummyFile();
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
