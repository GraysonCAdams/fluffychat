// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';

import 'package:fluffychat/utils/voice_transcription/ogg_opus_to_wav.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:opus_codec_dart/opus_codec_dart.dart';
import 'package:whisper_ggml/whisper_ggml.dart';

/// Runs a real voice message through libopus and whisper.cpp on Windows.
/// Opt-in, because it needs native libraries from a Windows build and the
/// downloaded model:
///
///   set WHISPER_BUILD_DIR=C:\src\fluffychat-transcribe\build\windows\x64\runner\Release
///   set WHISPER_MODEL=C:\path\to\ggml-base-q5_1.bin
///   flutter test test/utils/voice_transcription_whisper_test.dart
void main() {
  final buildDir = Platform.environment['WHISPER_BUILD_DIR'];
  final model = Platform.environment['WHISPER_MODEL'];

  test(
    'transcribes an Ogg Opus voice message',
    () async {
      // Loading by full path first makes whisper_ggml's later
      // DynamicLibrary.open('whisper_ggml.dll') resolve to this module.
      DynamicLibrary.open('$buildDir\\whisper_ggml.dll');
      // libopus gets its own directory: Windows keeps a loaded DLL locked.
      final opusDir = await Directory.systemTemp.createTemp('opus');
      final opus = await File(
        '$buildDir\\data\\flutter_assets\\packages\\opus_codec_windows'
        '\\assets\\libopus_x64.dll.blob',
      ).copy('${opusDir.path}\\libopus_x64.dll');
      initOpus(DynamicLibrary.open(opus.path));
      final temp = await Directory.systemTemp.createTemp('whisper');
      final wav = File('${temp.path}\\jfk.wav');
      await wav.writeAsBytes(
        oggOpusToWav(File('test/fixtures/jfk_speech.ogg').readAsBytesSync()),
      );

      final response = await const Whisper(model: WhisperModel.base).transcribe(
        transcribeRequest: TranscribeRequest(
          audio: wav.path,
          language: 'auto',
          isNoTimestamps: true,
        ),
        modelPath: model!,
      );
      await temp.delete(recursive: true);
      printOnFailure(response.text);

      expect(
        response.text.toLowerCase(),
        contains('ask not what your country can do for you'),
      );
    },
    timeout: const Timeout(Duration(minutes: 5)),
    skip: buildDir == null || model == null
        ? 'Set WHISPER_BUILD_DIR and WHISPER_MODEL to run'
        : false,
  );
}
