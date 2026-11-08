// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:http/http.dart' as http;
import 'package:opus_codec/opus_codec.dart' as opus_flutter;
import 'package:opus_codec_dart/opus_codec_dart.dart';
import 'package:path/path.dart';
import 'package:path_provider/path_provider.dart';
import 'package:synchronized/synchronized.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

import 'ogg_opus_to_wav.dart';
import 'transcript_cache.dart';

/// On-device transcription of voice messages with whisper.cpp.
abstract final class VoiceTranscriber {
  static bool get isSupported => Platform.isAndroid || Platform.isWindows;

  // The smallest multilingual model that still gives usable transcripts;
  // tiny mangles most languages other than English.
  static const modelSizeBytes = 59707625;
  static const _modelName = 'ggml-base-q5_1.bin';
  static const _modelSha256 =
      '422f1ae452ade6f30a004d7e5c6a43195e4433bc370bf23fac9cc591f01a8898';
  static final _modelUri = Uri.parse(
    'https://huggingface.co/ggerganov/whisper.cpp/resolve/main/$_modelName',
  );

  static final cache = TranscriptCache(
    () async => Directory(
      join((await getApplicationSupportDirectory()).path, 'transcripts'),
    ),
  );

  static final _lock = Lock();
  static Future<void>? _download;
  static Future<void>? _opusLoaded;

  static Future<File> _modelFile() async => File(
    join((await getApplicationSupportDirectory()).path, 'whisper', _modelName),
  );

  static Future<bool> isModelDownloaded() async =>
      (await _modelFile()).exists();

  /// Concurrent callers share one download.
  static Future<void> downloadModel({void Function(double)? onProgress}) =>
      _download ??= _downloadModel(
        onProgress,
      ).whenComplete(() => _download = null);

  static Future<void> _downloadModel(void Function(double)? onProgress) async {
    final file = await _modelFile();
    await file.parent.create(recursive: true);
    final partFile = File('${file.path}.part');
    final client = http.Client();
    try {
      final response = await client.send(http.Request('GET', _modelUri));
      if (response.statusCode != 200) {
        throw HttpException(
          'Model download failed: ${response.statusCode}',
          uri: _modelUri,
        );
      }
      final sink = partFile.openWrite();
      var received = 0;
      try {
        await for (final chunk in response.stream) {
          sink.add(chunk);
          received += chunk.length;
          onProgress?.call(received / modelSizeBytes);
        }
      } finally {
        await sink.close();
      }
      final digest = await sha256.bind(partFile.openRead()).first;
      if (digest.toString() != _modelSha256) {
        throw const FileSystemException('Model checksum mismatch');
      }
      await partFile.rename(file.path);
    } finally {
      client.close();
      if (await partFile.exists()) await partFile.delete();
    }
  }

  /// Returns the transcript of [audio], an Ogg Opus voice message or any
  /// other file whisper_ggml can convert itself.
  static Future<String> transcribe(Uint8List audio, String fileName) =>
      _lock.synchronized(() async {
        final modelFile = await _modelFile();
        final tempDir = await getTemporaryDirectory();
        final stamp = DateTime.now().microsecondsSinceEpoch;
        final File input;
        if (isOggFile(audio)) {
          await (_opusLoaded ??= opus_flutter.load().then(initOpus));
          input = File(join(tempDir.path, 'transcribe_$stamp.wav'));
          await input.writeAsBytes(oggOpusToWav(audio));
        } else {
          input = File(join(tempDir.path, 'transcribe_${stamp}_$fileName'));
          await input.writeAsBytes(audio);
        }
        // whisper_ggml writes its own conversion next to the input.
        final converted = File('${input.path}.wav');
        try {
          final response = await const Whisper(model: WhisperModel.base)
              .transcribe(
                transcribeRequest: TranscribeRequest(
                  audio: input.path,
                  language: 'auto',
                  isNoTimestamps: true,
                ),
                modelPath: modelFile.path,
              );
          return response.text.trim();
        } finally {
          if (await input.exists()) await input.delete();
          if (await converted.exists()) await converted.delete();
        }
      });
}
