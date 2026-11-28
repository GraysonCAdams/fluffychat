// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/utils/data_detectors/dart_data_detector.dart';
import 'package:fluffychat/utils/data_detectors/detection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// Finds data detections in a message's text and runs the actions the
/// platform offers for them.
///
/// Android and iOS answer through [ChannelDataDetector], backed by the
/// system's own classifier (TextClassifier on Android, NSDataDetector on
/// iOS). Every other platform uses [DartDataDetector], which has no system
/// actions, so Seam offers its own (see `seamActionsFor`).
abstract class DataDetectorPlatform {
  /// The detections in [text] in reading order, none overlapping. Relative
  /// dates ("tomorrow") count from [referenceTime], the time the message was
  /// sent.
  Future<List<Detection>> detect(
    String text, {
    required DateTime referenceTime,
  });

  /// Runs [detection]'s system action number [index]. False when it could
  /// not be run.
  Future<bool> runSystemAction(Detection detection, int index);

  static DataDetectorPlatform? _instance;

  /// The detector for this platform. Tests replace it.
  static DataDetectorPlatform get instance =>
      _instance ??= !kIsWeb && (Platform.isAndroid || Platform.isIOS)
      ? ChannelDataDetector()
      : DartDataDetector();

  @visibleForTesting
  static set instance(DataDetectorPlatform? value) => _instance = value;
}

/// The data detector of a mobile platform, behind the method channel
/// `chat.fluffy.fluffychat/data_detectors`. The native side owns detection
/// and the actions; Dart only shows them.
///
/// `detect`, with `{text: String, referenceTime: int}` (milliseconds since
/// the epoch), answers a list of maps in reading order:
///
/// ```
/// {
///   type: 'address' | 'phone' | 'date' | 'datetime' | 'flight',
///   start: int, end: int,          // UTF-16 offsets into text
///   token: String?,                // the native handle for runAction
///   actions: [                     // the system's actions, in its order
///     {title: String, description: String?, icon: Uint8List?},  // PNG
///   ],
/// }
/// ```
///
/// Entries of other types are skipped. `runAction`, with
/// `{token, index, text, referenceTime}` where `text` is the detected text
/// alone, runs one of those actions and answers whether it did. The native
/// side may have let go of the token; it then classifies `text` again and
/// runs that classification's action number `index`.
class ChannelDataDetector implements DataDetectorPlatform {
  static const channel = MethodChannel('chat.fluffy.fluffychat/data_detectors');

  /// The reference time of each token's detection, for [runSystemAction].
  final Map<String, DateTime> _referenceTimes = {};

  @override
  Future<List<Detection>> detect(
    String text, {
    required DateTime referenceTime,
  }) async {
    final List<Object?>? raw;
    try {
      raw = await channel.invokeListMethod<Object?>('detect', {
        'text': text,
        'referenceTime': referenceTime.millisecondsSinceEpoch,
      });
    } on MissingPluginException {
      return const [];
    } on PlatformException catch (e) {
      Logs().w('Data detection failed', e);
      return const [];
    }
    final detections = <Detection>[];
    for (final entry in raw ?? const []) {
      if (entry is! Map) continue;
      final type = DetectionType.fromWire(entry['type']);
      final start = entry['start'];
      final end = entry['end'];
      if (type == null || start is! int || end is! int) continue;
      if (start < 0 || end > text.length || start >= end) continue;
      final token = entry['token'] as String?;
      if (token != null) _referenceTimes[token] = referenceTime;
      detections.add(
        Detection(
          type: type,
          start: start,
          end: end,
          text: text.substring(start, end),
          token: token,
          systemActions: [
            for (final action in (entry['actions'] as List?) ?? const [])
              if (action is Map && action['title'] is String)
                SystemAction(
                  title: action['title'] as String,
                  description: action['description'] as String?,
                  icon: action['icon'] as Uint8List?,
                ),
          ],
        ),
      );
    }
    return detections;
  }

  @override
  Future<bool> runSystemAction(Detection detection, int index) async {
    try {
      return await channel.invokeMethod<bool>('runAction', {
            'token': detection.token,
            'index': index,
            'text': detection.text,
            'referenceTime':
                (_referenceTimes[detection.token] ?? DateTime.now())
                    .millisecondsSinceEpoch,
          }) ??
          false;
    } on PlatformException catch (e) {
      Logs().w('Data detector action failed', e);
      return false;
    }
  }
}
