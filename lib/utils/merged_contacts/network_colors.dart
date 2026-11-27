// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The bubble colour of each bridged network: the main colour of the
/// network's logo unless the user picked another one. A merged contact's
/// chat colours each message by the network it went out on; any other
/// bridged chat takes its own network's colour.
library;

import 'dart:convert';
import 'dart:ui';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:matrix/matrix.dart';

abstract class NetworkColors {
  /// Logo colours by bridge ID, the prefix of a bridge's user IDs
  /// (`@imessage_...` gives `imessage`).
  static const defaults = <String, Color>{
    'imessage': Color(0xFF34C759),
    'gmessages': Color(0xFF1A73E8),
    'whatsapp': Color(0xFF25D366),
    'telegram': Color(0xFF2AABEE),
    'signal': Color(0xFF3A76F0),
    'discord': Color(0xFF5865F2),
    'linkedin': Color(0xFF0A66C2),
    'instagram': Color(0xFFE1306C),
    'facebook': Color(0xFF0084FF),
    'meta': Color(0xFF0084FF),
    'slack': Color(0xFF4A154B),
    'twitter': Color(0xFF1D9BF0),
    'googlechat': Color(0xFF00AC47),
    'xbox': Color(0xFF107C10),
  };

  /// Text and icon colour on a bubble or button in [color]: white, as
  /// messaging apps put it on their own colours, including bright ones such
  /// as iMessage's green (luminance 0.42). Black only on a colour lighter
  /// than any network's, such as a pale custom pick.
  static Color foregroundOn(Color color) => color.computeLuminance() > 0.6
      ? const Color(0xFF000000)
      : const Color(0xFFFFFFFF);

  /// The bridge a direct chat goes through, or null for a chat with a plain
  /// Matrix user.
  static String? bridgeIdOf(Room room) {
    final localpart = room.directChatMatrixID?.localpart;
    if (localpart == null) return null;
    final underscore = localpart.indexOf('_');
    return underscore <= 0 ? null : localpart.substring(0, underscore);
  }

  /// The bridge any chat goes through: a direct chat's by its ghost (see
  /// [bridgeIdOf]), and a group's by the bridge bot its bridge state names
  /// (`@imessagebot` gives `imessage`), else the network that state names.
  /// Null for a plain Matrix room.
  static String? bridgeIdOfRoom(Room room) {
    final direct = bridgeIdOf(room);
    if (direct != null) return direct;
    final bridge = MatrixFeatures.forClient(room.client).bridgeOf(room);
    if (bridge == null) return null;
    final bot = bridge.bot?.localpart?.toLowerCase();
    if (bot != null && bot.length > 3 && bot.endsWith('bot')) {
      return bot.substring(0, bot.length - 3);
    }
    return bridge.network?.toLowerCase().replaceAll(' ', '');
  }

  static Map<String, int>? _picked;

  /// The user's picks by bridge ID, as ARGB values. Read once from the
  /// settings store and kept, because every message bubble asks.
  static Map<String, int> get _overrides {
    final cached = _picked;
    if (cached != null) return cached;
    final parsed = <String, int>{};
    try {
      final json = jsonDecode(AppSettings.networkBubbleColorOverrides.value);
      if (json is Map) {
        for (final MapEntry(:key, :value) in json.entries) {
          if (key is String && value is int) parsed[key] = value;
        }
      }
    } on FormatException {
      // A value this app did not write: fall back to the defaults.
    }
    return _picked = parsed;
  }

  /// The colour the user picked for [bridgeId], or null when they left the
  /// default.
  static Color? pickedFor(String bridgeId) {
    final argb = _overrides[bridgeId];
    return argb == null ? null : Color(argb);
  }

  /// The bubble colour for [bridgeId]: the user's pick, else the logo colour,
  /// else null for a network with neither.
  static Color? colorFor(String? bridgeId) =>
      bridgeId == null ? null : pickedFor(bridgeId) ?? defaults[bridgeId];

  /// Stores [color] as the pick for [bridgeId]; null goes back to the default.
  static Future<void> pick(String bridgeId, Color? color) {
    final next = {..._overrides};
    if (color == null) {
      next.remove(bridgeId);
    } else {
      next[bridgeId] = color.toARGB32();
    }
    _picked = next;
    return AppSettings.networkBubbleColorOverrides.setItem(jsonEncode(next));
  }
}
