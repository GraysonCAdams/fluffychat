// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

/// Stores voice message transcripts as one file per event, so a transcript
/// survives restarts and a second request does not run whisper again.
class TranscriptCache {
  final Future<Directory> Function() _directory;
  final Map<String, String> _memory = {};

  TranscriptCache(this._directory);

  Future<String?> get(String eventId) async {
    final cached = _memory[eventId];
    if (cached != null) return cached;
    final file = await _file(eventId);
    if (!await file.exists()) return null;
    return _memory[eventId] = await file.readAsString();
  }

  Future<void> put(String eventId, String transcript) async {
    _memory[eventId] = transcript;
    final file = await _file(eventId);
    await file.parent.create(recursive: true);
    await file.writeAsString(transcript);
  }

  // Event IDs can be up to 255 bytes and contain characters that are not
  // allowed in file names, so the file is named after their hash.
  Future<File> _file(String eventId) async {
    final directory = await _directory();
    final name = sha256.convert(utf8.encode(eventId)).toString();
    return File('${directory.path}${Platform.pathSeparator}$name.txt');
  }
}
