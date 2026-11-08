// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:ffi';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:fluffychat/utils/ogg_opus_remuxer.dart';
import 'package:fluffychat/utils/voice_transcription/ogg_opus_to_wav.dart';
import 'package:fluffychat/utils/voice_transcription/transcript_cache.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opus_codec_dart/opus_codec_dart.dart';

/// Loads the libopus DLL that opus_codec_windows ships as an asset, so the
/// conversion runs through the same native decoder as the app.
Future<void> _loadOpus(Directory tempDir) async {
  final config =
      jsonDecode(File('.dart_tool/package_config.json').readAsStringSync())
          as Map<String, Object?>;
  final package = (config['packages'] as List).cast<Map>().singleWhere(
    (p) => p['name'] == 'opus_codec_windows',
  );
  final root = Uri.directory(
    Directory.current.path,
  ).resolve('.dart_tool/').resolve(package['rootUri'] as String);
  final blob = File.fromUri(
    Uri.directory(root.toFilePath()).resolve('assets/libopus_x64.dll.blob'),
  );
  final dll = await blob.copy('${tempDir.path}/libopus_x64.dll');
  initOpus(DynamicLibrary.open(dll.path));
}

Uint8List _fixture(String name) =>
    File('test/fixtures/$name').readAsBytesSync();

Int16List _wavSamples(Uint8List wav) {
  final view = ByteData.sublistView(wav);
  expect(String.fromCharCodes(wav.sublist(0, 4)), 'RIFF');
  expect(String.fromCharCodes(wav.sublist(8, 16)), 'WAVEfmt ');
  expect(view.getUint16(20, Endian.little), 1, reason: 'PCM');
  expect(view.getUint16(22, Endian.little), 1, reason: 'mono');
  expect(view.getUint32(24, Endian.little), 16000, reason: 'sample rate');
  expect(view.getUint16(34, Endian.little), 16, reason: 'bits per sample');
  expect(String.fromCharCodes(wav.sublist(36, 40)), 'data');
  final dataLength = view.getUint32(40, Endian.little);
  expect(dataLength, wav.length - 44);
  return Int16List.fromList([
    for (var i = 0; i < dataLength ~/ 2; i++)
      view.getInt16(44 + i * 2, Endian.little),
  ]);
}

void main() {
  late Directory tempDir;

  setUp(() async {
    tempDir = await Directory.systemTemp.createTemp('voice_transcription');
  });

  tearDown(() async {
    await tempDir.delete(recursive: true);
  });

  group(
    'oggOpusToWav',
    () {
      setUpAll(() async {
        final dir = await Directory.systemTemp.createTemp('opus');
        await _loadOpus(dir);
      });

      test('decodes stereo 48 kHz Opus to a 16 kHz mono 440 Hz tone', () {
        final samples = _wavSamples(
          oggOpusToWav(_fixture('sine_440hz_stereo.ogg')),
        );

        // ffmpeg encoded exactly 2 s of audio; Opus pads to whole frames.
        expect(samples.length / 16000, closeTo(2.0, 0.03));

        // Count zero crossings over the middle second to get the pitch.
        final middle = samples.sublist(8000, 24000);
        var crossings = 0;
        for (var i = 1; i < middle.length; i++) {
          if ((middle[i - 1] < 0) != (middle[i] < 0)) crossings++;
        }
        expect(crossings / 2, closeTo(440, 5));

        final rms = sqrt(
          middle.fold<double>(0, (sum, s) => sum + s * s) / middle.length,
        );
        expect(rms, greaterThan(1000));
      });

      test('decodes a voice message remuxed the way FluffyChat sends it', () {
        final ogg = remuxOggOpus(_fixture('jfk_speech.ogg'));
        final samples = _wavSamples(oggOpusToWav(ogg));
        expect(samples.length / 16000, closeTo(11.0, 0.05));
      });

      test('rejects Ogg files that are not Opus', () {
        final ogg = _fixture('sine_440hz_stereo.ogg');
        // Overwrite the OpusHead magic of the first packet.
        final broken = Uint8List.fromList(ogg)
          ..setAll(28, 'VorbisHd'.codeUnits);
        expect(() => oggOpusToWav(broken), throwsFormatException);
      });
    },
    skip: Platform.isWindows
        ? false
        : 'libopus is loaded from the Windows asset',
  );

  group('TranscriptCache', () {
    test('persists transcripts per event across instances', () async {
      final first = TranscriptCache(() async => tempDir);
      await first.put(r'$event:example.org', 'Hello there');
      await first.put(r'$other:example.org', 'General Kenobi');

      final second = TranscriptCache(() async => tempDir);
      expect(await second.get(r'$event:example.org'), 'Hello there');
      expect(await second.get(r'$other:example.org'), 'General Kenobi');
      expect(await second.get(r'$missing:example.org'), isNull);
    });

    test(
      'stores empty transcripts so silence is not transcribed again',
      () async {
        final cache = TranscriptCache(() async => tempDir);
        await cache.put(r'$silent:example.org', '');
        expect(
          await TranscriptCache(
            () async => tempDir,
          ).get(r'$silent:example.org'),
          '',
        );
      },
    );

    test('accepts event IDs that are not valid file names', () async {
      final cache = TranscriptCache(() async => tempDir);
      final eventId = '\$${'a/b\\c:*?"<>|' * 20}:example.org';
      await cache.put(eventId, 'ok');
      expect(await TranscriptCache(() async => tempDir).get(eventId), 'ok');
    });
  });
}
