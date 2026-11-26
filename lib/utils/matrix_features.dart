// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/merged_contacts/contact_identifiers.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/phone_number.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Features that only matter when talking to other Matrix users. In
/// messenger mode, while every chat is bridged to another network, they are
/// hidden; each one comes back on its own when its trigger fires.
enum MatrixFeature {
  /// Set status in the account menu, and online dots on avatars.
  status,

  /// The user's own Matrix ID, invite link, QR code and Invite contact.
  identity,

  /// Full `@user:server` IDs. Hidden, the own server's domain is left out
  /// and bridge contacts show their phone number or username instead.
  fullUserIds,

  /// Creating and browsing spaces.
  spaces,

  /// Public rooms, the user directory and the server switch in search, and
  /// the space directory.
  explore,

  /// Matrix calls, encryption, permissions and room addresses inside a
  /// chat. Decided per chat: only plain Matrix rooms show them.
  roomPlumbing,

  /// Custom emoji and sticker packs.
  customEmotes,
}

/// How [MatrixFeatures] decides features that have no override.
enum MatrixFeaturesMode {
  /// Each feature shows when its trigger fires.
  auto,
  alwaysShow,
  alwaysHide,
}

/// A per-feature choice that beats the mode.
enum MatrixFeatureOverride { show, hide }

/// The bridge a room is a portal of, read from its `m.bridge` (or the older
/// `uk.half-shot.bridge`) state event.
class RoomBridge {
  /// The bridge bot's user ID, when the event names it.
  final String? bot;

  /// The remote network's name, such as "iMessage", when the event names it.
  final String? network;

  const RoomBridge({this.bot, this.network});

  static const stateTypes = ['m.bridge', 'uk.half-shot.bridge'];

  /// The bridge of [room] from state in memory, or null when none is
  /// loaded.
  static RoomBridge? fromState(Room room) {
    for (final type in stateTypes) {
      final events = room.states[type]?.values;
      if (events == null || events.isEmpty) continue;
      return fromContent(events.first.content);
    }
    return null;
  }

  /// Reads the content of an `m.bridge` event. Members of the wrong type
  /// are ignored, since bridges this app does not control write it.
  static RoomBridge fromContent(Map<String, Object?> content) {
    final bot = content['bridgebot'];
    final protocol = content['protocol'];
    final network = protocol is Map ? protocol['displayname'] : null;
    return RoomBridge(
      bot: bot is String && bot.isNotEmpty ? bot : null,
      network: network is String && network.isNotEmpty ? network : null,
    );
  }

  Map<String, String> toJson() => {'bot': ?bot, 'network': ?network};

  /// Reads the form written by [toJson].
  static RoomBridge fromJson(Object? json) {
    if (json is! Map) return const RoomBridge();
    final bot = json['bot'];
    final network = json['network'];
    return RoomBridge(
      bot: bot is String ? bot : null,
      network: network is String ? network : null,
    );
  }
}

/// What auto detection found on an account.
@immutable
class MatrixFeatureSignals {
  /// Matrix users outside bridged chats: joined members of non-bridged rooms
  /// who are not the user, a bridge bot or a bridge puppet.
  final int realContacts;

  /// Whether the user is in, or invited to, a space no bridge set up.
  final bool hasSpaces;

  /// Whether any chat or the account has custom emoji or stickers.
  final bool hasCustomEmotes;

  const MatrixFeatureSignals({
    this.realContacts = 0,
    this.hasSpaces = false,
    this.hasCustomEmotes = false,
  });

  /// Whether auto detection hides the Matrix-only features.
  bool get messengerMode => realContacts == 0;

  @override
  bool operator ==(Object other) =>
      other is MatrixFeatureSignals &&
      other.realContacts == realContacts &&
      other.hasSpaces == hasSpaces &&
      other.hasCustomEmotes == hasCustomEmotes;

  @override
  int get hashCode => Object.hash(realContacts, hasSpaces, hasCustomEmotes);
}

/// Answers whether a Matrix-only feature is worth showing, for the whole app
/// or for one chat. One instance exists per [Client], reached through
/// [forClient]; every gated screen asks it instead of detecting bridges
/// itself.
///
/// The answer comes from, in order: the feature's override in Settings >
/// Chats > Matrix features, the mode chosen there, and in auto mode the
/// feature's trigger ([autoRelevant]).
class MatrixFeatures extends ChangeNotifier {
  final Client client;

  /// Reads the state events of [room] that are not kept in memory, for
  /// rooms synced before the bridge state types were preloaded. Null skips
  /// that scan.
  final Future<List<StrippedStateEvent>> Function(Room room)? storedState;

  MatrixFeatures(this.client, {this.storedState}) {
    _syncSub = client.onSync.stream.listen((_) => _schedule());
    _loadScanCache();
    final storedState = this.storedState;
    if (storedState != null) unawaited(_scanStoredState(storedState));
  }

  static final Expando<MatrixFeatures> _instances = Expando();

  /// Whether [forClient] scans stored room state for bridges that predate
  /// preloading them. Widget tests turn it off to leave no work behind.
  @visibleForTesting
  static bool scanStoredState = true;

  /// The instance of [client], created on first use.
  static MatrixFeatures forClient(Client client) =>
      _instances[client] ??= MatrixFeatures(
        client,
        storedState: scanStoredState ? _databaseState : null,
      );

  /// Stops the instance of [client], if there is one, so the next
  /// [forClient] starts afresh.
  static void disposeFor(Client client) {
    _instances[client]?.dispose();
    _instances[client] = null;
  }

  static Future<List<StrippedStateEvent>> _databaseState(Room room) =>
      room.client.database.getUnimportantRoomEventStatesForRoom(
        scanExclusions(room.client.importantStateEvents),
        room,
      );

  /// The state types the stored state scan skips: those preloaded into
  /// memory, less the bridge types. A room synced before the bridge types
  /// were preloaded keeps its bridge event among the rest of its stored
  /// state, which is what the scan reads.
  @visibleForTesting
  static List<String> scanExclusions(Set<String> important) => [
    for (final type in important)
      if (!RoomBridge.stateTypes.contains(type)) type,
  ];

  StreamSubscription? _syncSub;
  Timer? _debounce;
  bool _disposed = false;

  /// How long after a sync the signals are worked out again.
  static const Duration debounce = Duration(milliseconds: 500);

  // Settings.

  /// The mode chosen in Settings > Chats > Matrix features.
  MatrixFeaturesMode get mode =>
      MatrixFeaturesMode.values
          .asNameMap()[AppSettings.matrixFeaturesMode.value] ??
      MatrixFeaturesMode.auto;

  Future<void> setMode(MatrixFeaturesMode mode) async {
    await AppSettings.matrixFeaturesMode.setItem(mode.name);
    notifyListeners();
  }

  /// The per-feature overrides, by feature. Parsed again only when the
  /// stored value changes, since avatars ask on every build.
  Map<MatrixFeature, MatrixFeatureOverride> get overrides {
    final raw = AppSettings.matrixFeatureOverrides.value;
    if (raw == _overridesRaw) return _overrides;
    _overridesRaw = raw;
    return _overrides = _parseOverrides(raw);
  }

  String? _overridesRaw;
  Map<MatrixFeature, MatrixFeatureOverride> _overrides = const {};

  static Map<MatrixFeature, MatrixFeatureOverride> _parseOverrides(String raw) {
    try {
      final json = jsonDecode(raw);
      if (json is! Map) return const {};
      final features = MatrixFeature.values.asNameMap();
      final choices = MatrixFeatureOverride.values.asNameMap();
      return {
        for (final entry in json.entries)
          ?features[entry.key]: ?choices[entry.value],
      };
    } catch (_) {
      return const {};
    }
  }

  /// Sets [feature]'s override, or removes it when [choice] is null.
  Future<void> setOverride(
    MatrixFeature feature,
    MatrixFeatureOverride? choice,
  ) async {
    final next = {
      for (final entry in overrides.entries) entry.key.name: entry.value.name,
    };
    if (choice == null) {
      next.remove(feature.name);
    } else {
      next[feature.name] = choice.name;
    }
    await AppSettings.matrixFeatureOverrides.setItem(jsonEncode(next));
    notifyListeners();
  }

  // Answers.

  /// Whether [feature] should show, in [room] when given. Per-chat features
  /// asked without a room answer for the account as a whole.
  bool isRelevant(MatrixFeature feature, {Room? room}) {
    final choice = overrides[feature];
    if (choice != null) return choice == MatrixFeatureOverride.show;
    return switch (mode) {
      MatrixFeaturesMode.alwaysShow => true,
      MatrixFeaturesMode.alwaysHide => false,
      MatrixFeaturesMode.auto => autoRelevant(feature, room: room),
    };
  }

  /// What auto mode decides for [feature], ignoring overrides.
  bool autoRelevant(MatrixFeature feature, {Room? room}) {
    final signals = this.signals;
    return switch (feature) {
      MatrixFeature.status ||
      MatrixFeature.identity ||
      MatrixFeature.fullUserIds ||
      MatrixFeature.explore => !signals.messengerMode,
      MatrixFeature.spaces => signals.hasSpaces,
      MatrixFeature.customEmotes => signals.hasCustomEmotes,
      MatrixFeature.roomPlumbing =>
        room == null ? !signals.messengerMode : !isBridged(room),
    };
  }

  /// What auto detection currently finds.
  MatrixFeatureSignals get signals {
    _ensureSignals();
    return _signals!;
  }

  MatrixFeatureSignals? _signals;

  void _schedule() {
    if (_disposed) return;
    _debounce?.cancel();
    _debounce = Timer(debounce, recompute);
  }

  /// Works the signals out again now, and tells listeners when they changed.
  void recompute() {
    if (_disposed) return;
    _debounce?.cancel();
    final previous = _signals;
    _signals = _computeSignals();
    if (previous != null && previous != _signals) notifyListeners();
  }

  // Bridges.

  /// Rooms found bridged by a scan of stored state, and rooms found plain.
  final Map<String, RoomBridge> _scannedBridges = {};
  final Set<String> _scannedPlain = {};

  /// Whether the stored state scan is still running. Until it ends, rooms it
  /// has not reached count as neither bridged nor plain.
  bool get scanning => _scanning;
  bool _scanning = false;

  /// The bridge [room] is a portal of, or null for a plain Matrix room.
  RoomBridge? bridgeOf(Room room) =>
      RoomBridge.fromState(room) ?? _scannedBridges[room.id];

  bool isBridged(Room room) => bridgeOf(room) != null;

  /// Whether nothing is known yet about [room]'s bridge, because its state
  /// was never loaded and the scan has not reached it.
  bool _unknown(Room room) =>
      _scanning &&
      room.partial &&
      RoomBridge.fromState(room) == null &&
      !_scannedBridges.containsKey(room.id) &&
      !_scannedPlain.contains(room.id);

  String get _scanCacheKey => scanCacheKeyFor(client.clientName);

  /// Where the stored state scan of the client named [clientName] keeps its
  /// results.
  @visibleForTesting
  static String scanCacheKeyFor(String clientName) =>
      'chat.fluffy.matrix_features.scan.v2.$clientName';

  /// Where an earlier scan kept results that marked every bridged room it
  /// read as plain, because it skipped the bridge types. It is cleared so
  /// those rooms are scanned again.
  static String _staleScanCacheKeyFor(String clientName) =>
      'chat.fluffy.matrix_features.scan.$clientName';

  void _loadScanCache() {
    try {
      unawaited(
        AppSettings.store.remove(_staleScanCacheKeyFor(client.clientName)),
      );
      final raw = AppSettings.store.getString(_scanCacheKey);
      if (raw == null) return;
      final json = jsonDecode(raw);
      if (json is! Map) return;
      final bridged = json['bridged'];
      if (bridged is Map) {
        for (final entry in bridged.entries) {
          if (entry.key is String) {
            _scannedBridges[entry.key as String] = RoomBridge.fromJson(
              entry.value,
            );
          }
        }
      }
      final plain = json['plain'];
      if (plain is List) _scannedPlain.addAll(plain.whereType<String>());
    } catch (e) {
      Logs().w('Unable to read the Matrix features scan cache', e);
    }
  }

  Future<void> _saveScanCache() => AppSettings.store.setString(
    _scanCacheKey,
    jsonEncode({
      'bridged': {
        for (final entry in _scannedBridges.entries)
          entry.key: entry.value.toJson(),
      },
      'plain': _scannedPlain.toList(),
    }),
  );

  /// Looks for bridge state in rooms whose state was never loaded. Bridge
  /// state types are preloaded from now on, but events stored before that
  /// stay in the part of the database read only when a chat opens. Each room
  /// is scanned once; the result is cached.
  Future<void> _scanStoredState(
    Future<List<StrippedStateEvent>> Function(Room room) load,
  ) async {
    _scanning = true;
    try {
      await client.roomsLoading;
      final rooms = client.rooms
          .where(
            (room) =>
                room.membership == Membership.join &&
                room.partial &&
                RoomBridge.fromState(room) == null &&
                !_scannedBridges.containsKey(room.id) &&
                !_scannedPlain.contains(room.id),
          )
          .toList();
      for (final room in rooms) {
        if (_disposed) return;
        try {
          final events = await load(room);
          final bridge = events
              .where((event) => RoomBridge.stateTypes.contains(event.type))
              .firstOrNull;
          if (bridge != null) {
            _scannedBridges[room.id] = RoomBridge.fromContent(bridge.content);
          } else {
            _scannedPlain.add(room.id);
          }
        } catch (e) {
          Logs().w('Unable to scan ${room.id} for bridge state', e);
        }
      }
      if (rooms.isNotEmpty) await _saveScanCache();
    } catch (e, s) {
      Logs().w('Unable to scan rooms for bridge state', e, s);
    } finally {
      _scanning = false;
      if (!_disposed) {
        final previous = _signals;
        _signals = _computeSignals();
        if (previous != _signals) notifyListeners();
      }
    }
  }

  // Detection.

  /// User IDs known in [room]: its heroes, the other person of a direct
  /// chat, and joined members in memory.
  static Set<String> _memberIds(Room room) => {
    ...?room.summary.mHeroes,
    ?room.directChatMatrixID,
    for (final user in room.getParticipants([Membership.join])) user.id,
  };

  /// Bridge bots and puppets, as of the last [signals].
  Set<String> get bridgeUsers {
    _ensureSignals();
    return _bridgeUsers;
  }

  void _ensureSignals() => _signals ??= _computeSignals();

  Set<String> _bridgeUsers = const {};

  /// The network of each puppet, by user ID, as of the last [signals].
  Map<String, String> _puppetNetworks = const {};

  /// A user on the own server whose name ends in "bot", such as a bridge's
  /// bot before it has set up any chat.
  bool _looksLikeBot(String userId) {
    final own = client.userID?.domain;
    return own != null &&
        userId.domain == own &&
        (userId.localpart?.toLowerCase().endsWith('bot') ?? false);
  }

  MatrixFeatureSignals _computeSignals() {
    final me = client.userID;
    final bridgeUsers = <String>{};
    final puppetNetworks = <String, String>{};
    final bridgedRooms = <String>{};
    final spaces = spacesByChild(client);
    for (final room in client.rooms) {
      if (room.membership != Membership.join || room.isSpace) continue;
      final bridge = bridgeOf(room);
      if (bridge == null) continue;
      bridgedRooms.add(room.id);
      final bot = bridge.bot;
      if (bot != null) bridgeUsers.add(bot);
      final network =
          bridge.network ?? spaces[room.id]?.getLocalizedDisplayname();
      for (final id in _memberIds(room)) {
        if (id == me) continue;
        bridgeUsers.add(id);
        if (network != null && id != bot) puppetNetworks[id] = network;
      }
    }

    final contacts = <String>{};
    final ownServer = me?.domain;
    var hasCustomEmotes = _hasEmotes(
      client.accountData['im.ponies.user_emotes']?.content,
    );
    for (final room in client.rooms) {
      if (room.membership != Membership.join || room.isSpace) continue;
      if (!hasCustomEmotes) {
        final packs = room.states['im.ponies.room_emotes']?.values;
        hasCustomEmotes =
            packs?.any((event) => _hasEmotes(event.content)) ?? false;
      }
      if (bridgedRooms.contains(room.id) || _unknown(room)) continue;
      if (room.tags.containsKey(TagType.serverNotice)) continue;
      for (final id in _memberIds(room)) {
        if (id == me || bridgeUsers.contains(id) || _looksLikeBot(id)) {
          continue;
        }
        // Accounts on the user's own server are not counted: on a server
        // run for bridges they are the user's own bots and agents, which
        // the app cannot tell from people. Matrix contacts are people on
        // other servers.
        if (ownServer != null && id.domain == ownServer) continue;
        contacts.add(id);
      }
    }

    var hasSpaces = false;
    for (final space in client.rooms) {
      if (!space.isSpace) continue;
      if (space.membership != Membership.join &&
          space.membership != Membership.invite) {
        continue;
      }
      if (_isBridgeSpace(space, bridgeUsers, bridgedRooms)) continue;
      hasSpaces = true;
      break;
    }

    _bridgeUsers = bridgeUsers;
    _puppetNetworks = puppetNetworks;
    return MatrixFeatureSignals(
      realContacts: contacts.length,
      hasSpaces: hasSpaces,
      hasCustomEmotes: hasCustomEmotes,
    );
  }

  static bool _hasEmotes(Map<String, Object?>? content) {
    final images = content?['images'];
    return images is Map && images.isNotEmpty;
  }

  /// Whether a bridge set [space] up to hold its chats: a bridge user
  /// created it, or every chat in it that the user is in is bridged.
  bool _isBridgeSpace(
    Room space,
    Set<String> bridgeUsers,
    Set<String> bridgedRooms,
  ) {
    final creator = space.getState(EventTypes.RoomCreate)?.senderId;
    if (creator != null &&
        (bridgeUsers.contains(creator) || _looksLikeBot(creator))) {
      return true;
    }
    final joined = [
      for (final child in space.spaceChildren)
        if (child.roomId case final id?)
          if (client.getRoomById(id)?.membership == Membership.join) id,
    ];
    return joined.isNotEmpty && joined.every(bridgedRooms.contains);
  }

  // Display.

  /// Whether [userId] is a bridge puppet or bot. With [room], any member of
  /// a bridged [room] other than the user counts too.
  bool isBridgeUser(String userId, {Room? room}) {
    if (userId == client.userID) return false;
    if (room != null && isBridged(room)) return true;
    return bridgeUsers.contains(userId);
  }

  /// The network [userId] is a puppet on, when known.
  String? networkOf(String userId, {Room? room}) {
    if (room != null) {
      final bridge = bridgeOf(room);
      if (bridge?.network case final network?) return network;
    }
    _ensureSignals();
    return _puppetNetworks[userId];
  }

  /// How [userId] is shown under a name. With full user IDs shown this is
  /// the ID itself. Otherwise a bridge contact shows the phone number or
  /// email address in their ID, then the network ([identifier] can supply
  /// one known elsewhere, such as from the bridge profile); a user on the own
  /// server shows only `@localpart`; other servers keep their domain.
  ///
  /// Only for display: anything copied or sent uses the full ID.
  String userLabel(String userId, {Room? room, String? identifier}) {
    if (isRelevant(MatrixFeature.fullUserIds, room: room)) return userId;
    if (isBridgeUser(userId, room: room)) {
      final handle = identifier ?? handleOf(userId);
      final network = networkOf(userId, room: room);
      final parts = [?handle, ?network];
      if (parts.isNotEmpty) return parts.join(' · ');
    }
    final own = client.userID?.domain;
    if (own != null && userId.domain == own) {
      return '@${userId.localpart ?? userId}';
    }
    return userId;
  }

  /// The phone number or email address embedded in a bridge puppet's user
  /// ID, formatted for display, or null when the ID carries none.
  static String? handleOf(String userId) {
    final identifier = identifiersFromUserId(userId).firstOrNull;
    if (identifier == null) return null;
    return identifier.type == IdentifierType.phone
        ? formatPhoneForDisplay(identifier.value)
        : identifier.value;
  }

  @override
  void dispose() {
    _disposed = true;
    _debounce?.cancel();
    _syncSub?.cancel();
    super.dispose();
  }
}
