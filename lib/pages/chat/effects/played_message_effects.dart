// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Which messages have had their effect play, so each plays by itself only
/// once: scrolling a message back into view, reopening the chat or
/// restarting the app does not play it again.
///
/// Kept in the settings store as the newest [_capacity] ids. A message
/// older than [maxAge] never plays by itself, which covers everything that
/// has dropped off the list and the history of a freshly signed in device.
abstract class PlayedMessageEffects {
  static const _capacity = 400;

  /// How old a message can be and still play its effect by itself.
  static const maxAge = Duration(days: 1);

  static List<String>? _loaded;

  /// Counts up each time a message is marked played, so a widget that
  /// waits for an effect to have played can listen for it.
  static final changes = ValueNotifier<int>(0);

  static List<String> get _ids {
    final loaded = _loaded;
    if (loaded != null) return loaded;
    final ids = <String>[];
    try {
      final json = jsonDecode(AppSettings.playedMessageEffects.value);
      if (json is List) ids.addAll(json.whereType<String>());
    } on FormatException {
      // A value this app did not write: start over.
    }
    return _loaded = ids;
  }

  /// The ids [event] is known by: its transaction id while it is sending
  /// and on the device that sent it, and its event id.
  static Iterable<String> _keysOf(Event event) => {
    ?event.transactionId,
    event.eventId,
  };

  static bool hasPlayed(Event event) => _keysOf(event).any(_ids.contains);

  /// Whether [event]'s effect should play by itself now.
  static bool shouldAutoPlay(Event event, {DateTime? now}) =>
      !hasPlayed(event) &&
      (now ?? DateTime.now()).difference(event.originServerTs) < maxAge;

  static void markPlayed(Event event) {
    final ids = _ids;
    var changed = false;
    for (final key in _keysOf(event)) {
      if (ids.contains(key)) continue;
      ids.add(key);
      changed = true;
    }
    if (!changed) return;
    if (ids.length > _capacity) ids.removeRange(0, ids.length - _capacity);
    AppSettings.playedMessageEffects.setItem(jsonEncode(ids));
    changes.value++;
  }

  /// Forgets what was loaded, so the next question reads the store again.
  static void resetForTest() => _loaded = null;
}
