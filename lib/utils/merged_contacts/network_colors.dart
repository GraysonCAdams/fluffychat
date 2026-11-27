// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The bubble colour of each bridged network: the main colour of the
/// network's logo unless the user picked another one. A merged contact's
/// chat colours each message by the network it went out on; any other
/// bridged chat takes its own network's colour. The picks are kept in the
/// account's data as well (see [NetworkColorSync]), so every device of the
/// account shows the same colours.
library;

import 'dart:async';
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

  /// Stores [color] as the pick for [bridgeId]; null goes back to the
  /// default. With [client], the account's data gets the new picks too, for
  /// the account's other devices.
  static Future<void> pick(
    String bridgeId,
    Color? color, {
    Client? client,
  }) async {
    final next = {..._overrides};
    if (color == null) {
      next.remove(bridgeId);
    } else {
      next[bridgeId] = color.toARGB32();
    }
    await _store(next);
    if (client != null) await NetworkColorSync.upload(client, next);
  }

  static Future<void> _store(Map<String, int> picks) {
    _picked = picks;
    return AppSettings.networkBubbleColorOverrides.setItem(jsonEncode(picks));
  }
}

/// Keeps the network colour picks of [NetworkColors] in step with the
/// account's data, where every device of the account reads and writes
/// them: picks from the account replace this device's, and a device that
/// has picks the account does not have yet hands them over.
class NetworkColorSync {
  /// The account data event the picks are in, each colour an ARGB int:
  /// `{"colors": {"imessage": 4280391411, ...}}`.
  static const String accountDataType = 'dev.seam.network_bubble_colors';

  final Client client;
  StreamSubscription<SyncUpdate>? _subscription;

  NetworkColorSync._(this.client);

  /// Starts following [client]'s account data. The first sync, which
  /// comes once the account data is loaded, settles who is right: picks in
  /// the account replace this device's, else this device's picks go to the
  /// account. Later syncs that change the picks replace this device's.
  static NetworkColorSync attach(Client client) {
    final sync = NetworkColorSync._(client);
    sync._subscription = client.onSync.stream.listen(sync._onSync);
    return sync;
  }

  bool _settled = false;

  Future<void> _onSync(SyncUpdate update) async {
    final changed =
        update.accountData?.any((event) => event.type == accountDataType) ??
        false;
    if (_settled && !changed) return;
    final firstSync = !_settled;
    _settled = true;
    final stored = picksIn(client.accountData[accountDataType]?.content);
    if (stored != null) {
      await NetworkColors._store(stored);
    } else if (firstSync && NetworkColors._overrides.isNotEmpty) {
      await upload(client, NetworkColors._overrides);
    }
  }

  /// The picks in an account data event's [content], or null when it holds
  /// none this app can read.
  static Map<String, int>? picksIn(Map<String, Object?>? content) {
    final colors = content?['colors'];
    if (colors is! Map) return null;
    return {
      for (final MapEntry(:key, :value) in colors.entries)
        if (key is String && value is int) key: value,
    };
  }

  /// Writes [picks] to [client]'s account data.
  static Future<void> upload(Client client, Map<String, int> picks) async {
    final userId = client.userID;
    if (userId == null) return;
    try {
      await client.setAccountData(userId, accountDataType, {'colors': picks});
    } catch (e, s) {
      Logs().w('Could not store the network colours in account data', e, s);
    }
  }

  void dispose() => _subscription?.cancel();
}
