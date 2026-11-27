// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';
import 'dart:io';

import 'package:fluffychat/utils/logcat_mirror.dart';
import 'package:fluffychat/utils/network_error_log.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' show ClientException;
import 'package:matrix/matrix.dart';

void main() {
  final written = <(int, String, String)>[];
  late void Function(int, String, String) original;

  setUp(() {
    written.clear();
    original = LogcatMirror.writer;
    LogcatMirror.writer = (priority, tag, line) =>
        written.add((priority, tag, line));
  });

  tearDown(() => LogcatMirror.writer = original);

  group('scrubbing', () {
    test('takes tokens out of URLs, JSON and headers', () {
      const lines = [
        'GET https://matrix.x/_matrix/client/v3/sync?access_token=syt_abc123&since=s1',
        '{"access_token": "syt_abc123", "device_id": "D"}',
        '{"refresh_token":"syr_abc123"}',
        'headers: {Authorization: Bearer syt_abc123}',
        'authorization=syt_abc123',
      ];
      for (final line in lines) {
        final scrubbed = LogcatMirror.scrub(line);
        expect(scrubbed, isNot(contains('abc123')), reason: line);
        expect(scrubbed, contains('<redacted>'), reason: line);
      }
      // What is around a token stays readable.
      expect(
        LogcatMirror.scrub('sync?access_token=syt_abc123&since=s1'),
        'sync?access_token=<redacted>&since=s1',
      );
    });

    test('leaves a line without secrets alone', () {
      const line = 'Syncloop failed: host=matrix.x SocketException: timed out';
      expect(LogcatMirror.scrub(line), line);
    });

    test('a mirrored line is scrubbed', () {
      LogcatMirror.handle(
        LogEvent(
          'Request failed',
          exception: 'https://x/_matrix?access_token=syt_secret',
          level: Level.warning,
        ),
      );
      expect(written.single.$3, isNot(contains('syt_secret')));
    });
  });

  group('levels', () {
    test('info and above go to logcat as Seam with their priority', () {
      for (final level in [Level.info, Level.warning, Level.error, Level.wtf]) {
        LogcatMirror.handle(LogEvent('line ${level.name}', level: level));
      }
      expect(written, [
        (4, 'Seam', 'line info'),
        (5, 'Seam', 'line warning'),
        (6, 'Seam', 'line error'),
        (6, 'Seam', 'line wtf'),
      ]);
    });

    test('debug and verbose stay out', () {
      LogcatMirror.handle(LogEvent('noise', level: Level.debug));
      LogcatMirror.handle(LogEvent('more noise', level: Level.verbose));
      expect(written, isEmpty);
    });

    test('a long line goes out in pieces logcat keeps whole', () {
      LogcatMirror.handle(LogEvent('x' * 9000, level: Level.info));
      expect(written.map((w) => w.$3.length), [4000, 4000, 1000]);
    });
  });

  group('network errors', () {
    test('name the host, the type and the message', () {
      expect(
        networkErrorSummary(
          ClientException(
            'Connection timed out',
            Uri.parse('https://matrix.graysons.network/_matrix/client/v3/sync'),
          ),
        ),
        'host=matrix.graysons.network ClientException: Connection timed out',
      );
      expect(
        networkErrorSummary(
          SyncConnectionException(
            TimeoutException(null, const Duration(seconds: 30)),
          ),
          endpoint: Uri.parse('https://matrix.x'),
        ),
        'host=matrix.x TimeoutException: timed out after 0:00:30.000000',
      );
      expect(
        networkErrorSummary(
          const SocketException(
            'Failed host lookup',
            osError: OSError('No address associated with hostname', 7),
          ),
        ),
        'host=unknown host SocketException: Failed host lookup '
        '(No address associated with hostname)',
      );
    });
  });
}
