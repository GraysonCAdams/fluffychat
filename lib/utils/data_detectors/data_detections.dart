// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/data_detectors/data_detector_platform.dart';
import 'package:fluffychat/utils/data_detectors/detection.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// The data detections of messages, found once per event and text and
/// kept, and which message of each chat shows assist chips.
///
/// A message is classified the first time it is built, which in the
/// timeline's lazy list means when it scrolls into view; never again for
/// the same text. Only the newest message of a chat that has detections
/// shows chips (see [chipsEventOf]).
class DataDetections {
  DataDetections._();

  static final DataDetections instance = DataDetections._();

  /// At most this many messages' results are kept.
  static const maxEntries = 500;

  final Map<String, List<Detection>> _results = {};
  final Map<String, Future<List<Detection>>> _pending = {};
  final Map<String, ValueNotifier<({String eventId, DateTime sent})?>> _newest =
      {};

  static String _key(String eventId, String text) =>
      '$eventId|${text.length}|${text.hashCode}';

  /// The detections of [eventId] reading [text], if they are known yet.
  List<Detection>? cached(String eventId, String text) =>
      _results[_key(eventId, text)];

  /// The detections of [event] reading [text], from the cache or from the
  /// platform's detector.
  Future<List<Detection>> detect(Event event, String text) {
    final key = _key(event.eventId, text);
    final known = _results[key];
    if (known != null) return SynchronousFuture(known);
    return _pending[key] ??= () async {
      final watch = Stopwatch()..start();
      List<Detection> found;
      try {
        found = await DataDetectorPlatform.instance.detect(
          text,
          referenceTime: event.originServerTs,
        );
      } catch (e, s) {
        Logs().w('Data detection failed', e, s);
        found = const [];
      }
      Logs().v(
        'Data detection of ${text.length} characters took '
        '${watch.elapsedMilliseconds} ms, found ${found.length}',
      );
      _pending.remove(key);
      if (_results.length >= maxEntries) {
        _results.remove(_results.keys.first);
      }
      _results[key] = found;
      if (found.isNotEmpty) _offerChips(event);
      return found;
    }();
  }

  /// Which message of [roomId] shows assist chips: the newest one found to
  /// have detections. Older ones keep their underlines and menus.
  ValueListenable<({String eventId, DateTime sent})?> chipsEventOf(
    String roomId,
  ) => _newest.putIfAbsent(roomId, () => ValueNotifier(null));

  void _offerChips(Event event) {
    final notifier = _newest.putIfAbsent(
      event.roomId!,
      () => ValueNotifier(null),
    );
    final current = notifier.value;
    if (current == null || event.originServerTs.isAfter(current.sent)) {
      notifier.value = (eventId: event.eventId, sent: event.originServerTs);
    }
  }

  @visibleForTesting
  void clear() {
    _results.clear();
    _pending.clear();
    for (final notifier in _newest.values) {
      notifier.value = null;
    }
  }

  /// The plain text to look for detections in, or null when [event] is not
  /// a text message that should have any: one hidden by Invisible Ink, or
  /// a redacted one. Text in code and links is skipped when the message is
  /// rendered (see HtmlMessage).
  static String? textOf(Event event) {
    if (event.type != EventTypes.Message || event.redacted) return null;
    if (!{
      MessageTypes.Text,
      MessageTypes.Notice,
      MessageTypes.Emote,
    }.contains(event.messageType)) {
      return null;
    }
    if (effectOf(event) == MessageEffect.invisibleInk) return null;
    final text = event.calcUnlocalizedBody(
      hideReply: event.inReplyToEventId() != null,
    );
    if (text.trim().isEmpty) return null;
    return text;
  }

  /// At most this many detections of a message get a chip, in reading
  /// order. The rest are only underlined.
  static const maxChips = 2;
}
