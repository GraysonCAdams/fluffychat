// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Writes the app's log lines to Android's logcat under the tag "Seam", so
/// `adb logcat -s Seam` shows them in profile and release builds too.
///
/// The Matrix SDK prints its log lines with `print`, which reach logcat
/// under the "flutter" tag, prefixed "[Matrix]" and wrapped in colour
/// codes, and which profile and release builds hold back to warnings and
/// errors (see `ClientManager.createClient`). This writes info and above
/// straight to liblog instead, with secrets taken out. Debug and verbose
/// lines stay in the in-app log viewer only.
abstract final class LogcatMirror {
  static const String tag = 'Seam';

  /// logcat keeps about 4 KB of a line, so longer ones go out in pieces.
  static const int maxLineLength = 4000;

  /// Where a line goes: liblog on Android, swapped out in tests.
  @visibleForTesting
  static void Function(int priority, String tag, String line) writer =
      _writeToLiblog;

  /// Starts mirroring, on Android outside debug builds, where `flutter run`
  /// already shows every line. [previous] is the onLog callback it keeps
  /// calling first.
  static void install({LogCallback? previous}) {
    if (kIsWeb || !Platform.isAndroid || kDebugMode) return;
    Logs().onLog = (event) {
      previous?.call(event);
      handle(event);
    };
  }

  /// Android's log priorities for the levels that are mirrored: info,
  /// warning and error (a "what a terrible failure" is an error). Null for
  /// debug and verbose, which are not.
  @visibleForTesting
  static int? priorityOf(Level level) => switch (level) {
    Level.wtf || Level.error => 6,
    Level.warning => 5,
    Level.info => 4,
    Level.debug || Level.verbose => null,
  };

  /// Writes [event] to logcat when its level is mirrored.
  static void handle(LogEvent event) {
    final priority = priorityOf(event.level);
    if (priority == null) return;
    for (final line in chunks(scrub(event.toFormattedString()))) {
      try {
        writer(priority, tag, line);
      } catch (_) {
        // A log line that cannot be written is dropped; logging must never
        // take the app down.
      }
    }
  }

  static final List<(RegExp, String)> _secrets = [
    // access_token=…, refresh_token=… in a URL or form body.
    (
      RegExp(r'((?:access|refresh)_token=)[^&\s"]+', caseSensitive: false),
      r'$1<redacted>',
    ),
    // "access_token": "…" in JSON, and the same for refresh tokens.
    (
      RegExp(
        r'("(?:access|refresh)_token"\s*:\s*")[^"]*',
        caseSensitive: false,
      ),
      r'$1<redacted>',
    ),
    // Authorization: Bearer … in a header, and a bare bearer token.
    (
      RegExp(r'(Bearer\s+)[A-Za-z0-9._~+/=-]+', caseSensitive: false),
      r'$1<redacted>',
    ),
    (
      RegExp(r'(authorization\W{1,4})[^\s,}"]+', caseSensitive: false),
      r'$1<redacted>',
    ),
  ];

  /// [text] with access and refresh tokens and authorization values
  /// replaced by `<redacted>`.
  @visibleForTesting
  static String scrub(String text) {
    var scrubbed = text;
    for (final (pattern, replacement) in _secrets) {
      scrubbed = scrubbed.replaceAllMapped(
        pattern,
        (match) => replacement.replaceAll(r'$1', match.group(1)!),
      );
    }
    return scrubbed;
  }

  /// [text] in pieces of at most [maxLineLength] characters.
  @visibleForTesting
  static Iterable<String> chunks(String text) sync* {
    for (var start = 0; start < text.length; start += maxLineLength) {
      final end = start + maxLineLength;
      yield text.substring(start, end < text.length ? end : text.length);
    }
  }

  static int Function(int, Pointer<Utf8>, Pointer<Utf8>)? _androidLogWrite;

  static void _writeToLiblog(int priority, String tag, String line) {
    final write = _androidLogWrite ??= DynamicLibrary.open('liblog.so')
        .lookupFunction<
          Int32 Function(Int32, Pointer<Utf8>, Pointer<Utf8>),
          int Function(int, Pointer<Utf8>, Pointer<Utf8>)
        >('__android_log_write');
    final nativeTag = tag.toNativeUtf8();
    final nativeLine = line.toNativeUtf8();
    try {
      write(priority, nativeTag, nativeLine);
    } finally {
      malloc.free(nativeTag);
      malloc.free(nativeLine);
    }
  }
}
