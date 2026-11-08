// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

/// Web build stand-in for `voice_transcriber_io.dart`, which needs `dart:ffi`.
abstract final class VoiceTranscriber {
  static bool get isSupported => false;

  static const modelSizeBytes = 0;

  static final cache = TranscriptCache();

  static Future<bool> isModelDownloaded() async => false;

  static Future<void> downloadModel({
    void Function(double)? onProgress,
  }) async => throw UnsupportedError('Transcription is not available');

  static Future<String> transcribe(Uint8List audio, String fileName) async =>
      throw UnsupportedError('Transcription is not available');
}

class TranscriptCache {
  Future<String?> get(String eventId) async => null;

  Future<void> put(String eventId, String transcript) async {}
}
