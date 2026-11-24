// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'contact_identifiers.dart';
import 'networks.dart';
import 'store.dart';
import 'suggester.dart';

/// Fetches the `com.beeper.bridge.identifiers` profile field of a user:
/// the list, or null when the user has none.
typedef ProfileIdentifiersFetcher = Future<Object?> Function(String userId);

/// Finds direct chats that look like the same person and offers them for
/// merging ([suggestions]). Runs off the chat list's build path: once the
/// first sync is in, then again a few seconds after the set of direct chats
/// or the merged contacts change.
///
/// Identifiers come from the other person's user ID where a bridge encodes
/// them, else from the bridge's profile field (fetched once per user, one
/// request at a time, and cached on the device), else from the chat's name.
class MergeSuggestionService {
  final Client client;
  final ProfileIdentifiersFetcher fetchProfileIdentifiers;
  final bool Function() isEnabled;
  final String Function() phoneRegion;
  final SharedPreferences? cache;

  /// Pending suggestions, strong (same phone or email) first.
  final ValueNotifier<List<MergeSuggestion>> suggestions = ValueNotifier(
    const [],
  );

  MergeSuggestionService(
    this.client, {
    ProfileIdentifiersFetcher? fetchProfileIdentifiers,
    bool Function()? isEnabled,
    String Function()? phoneRegion,
    this.cache,
  }) : fetchProfileIdentifiers =
           fetchProfileIdentifiers ?? _profileFetcher(client),
       isEnabled =
           isEnabled ?? (() => AppSettings.mergedContactSuggestions.value),
       phoneRegion = phoneRegion ?? defaultPhoneRegion;

  static final Expando<MergeSuggestionService> _services = Expando();

  /// The service of [client], created and started on first use.
  static MergeSuggestionService forClient(Client client) =>
      _services[client] ??= MergeSuggestionService(
        client,
        cache: AppSettings.store,
      )..start();

  /// The region for numbers without a country code: the setting, else the
  /// device's region, else the US (the bridges this was built for).
  static String defaultPhoneRegion() {
    final setting = AppSettings.mergedContactsPhoneRegion.value;
    if (setting.isNotEmpty) return setting;
    return PlatformDispatcher.instance.locale.countryCode ?? 'US';
  }

  static ProfileIdentifiersFetcher _profileFetcher(Client client) =>
      (userId) async {
        try {
          final field = await client.getProfileField(userId, _profileField);
          return field[_profileField];
        } on MatrixException catch (e) {
          if (e.error == MatrixError.M_NOT_FOUND) return null;
          rethrow;
        }
      };

  static const String _profileField = 'com.beeper.bridge.identifiers';
  static const String _cachePrefix = 'chat.fluffy.merged_contacts.profile.';

  /// How long a fetched profile list is trusted, and how long an empty one
  /// is (shorter, as the bridge may start publishing numbers).
  static const Duration cacheLifetime = Duration(days: 7);
  static const Duration emptyCacheLifetime = Duration(days: 1);

  /// Profile requests per pass, so a large account fetches over a few passes
  /// rather than flooding the server.
  static const int maxFetchesPerPass = 50;

  static const Duration debounce = Duration(seconds: 3);

  late final MergedContactsStore _store = MergedContactsStore.forClient(client);

  /// Forgets and disposes the service of [client], for example on logout.
  static void disposeFor(Client client) {
    _services[client]?.dispose();
    _services[client] = null;
  }

  final Map<String, Object?> _profiles = {};
  final List<StreamSubscription> _subscriptions = [];
  Timer? _debounceTimer;
  bool _started = false;
  bool _running = false;
  bool _disposed = false;

  void start() {
    if (_started) return;
    _started = true;
    _subscriptions.add(
      client.onSync.stream
          .where(
            (sync) =>
                (sync.rooms?.leave?.isNotEmpty ?? false) ||
                (sync.rooms?.invite?.isNotEmpty ?? false) ||
                (sync.accountData?.any((e) => e.type == 'm.direct') ?? false) ||
                (sync.rooms?.join?.values.any(
                      (room) =>
                          room.state?.any(
                            (e) =>
                                e.type == EventTypes.RoomMember ||
                                e.type == EventTypes.RoomName,
                          ) ??
                          false,
                    ) ??
                    false),
          )
          .listen((_) => schedule()),
    );
    _store.revision.addListener(schedule);
    () async {
      await _store.loaded;
      await client.firstSyncReceived;
      schedule(immediately: true);
    }();
  }

  /// Recomputes the suggestions after [debounce], or at once.
  void schedule({bool immediately = false}) {
    if (_disposed) return;
    _debounceTimer?.cancel();
    _debounceTimer = Timer(immediately ? Duration.zero : debounce, refresh);
  }

  /// Recomputes the suggestions from what is already known, synchronously
  /// and even while [refresh] is waiting on profile lookups. For a change the
  /// user just made, so the list moves on without waiting for the debounce.
  void recomputeNow() {
    if (_disposed || !isEnabled()) return;
    _compute();
  }

  /// Recomputes the suggestions now, then fetches missing profile
  /// identifiers and recomputes once more if any were found.
  Future<void> refresh() async {
    if (_running || _disposed) return;
    _running = true;
    try {
      if (!isEnabled()) {
        suggestions.value = const [];
        return;
      }
      _compute();
      if (await _fetchMissingProfiles() && !_disposed) _compute();
    } finally {
      _running = false;
    }
  }

  List<Room> get _directChats => [
    for (final room in client.rooms)
      if (room.membership == Membership.join &&
          !room.isSpace &&
          room.isDirectChat)
        room,
  ];

  static ContactIdentifier? _nameIdentifier(String displayName) {
    final name = normalizeName(displayName);
    return name.isEmpty ? null : ContactIdentifier(IdentifierType.name, name);
  }

  void _compute() {
    final store = _store;
    final spaces = spacesByChild(client);
    final region = phoneRegion();
    final chats = <SuggesterChat>[];
    for (final room in _directChats) {
      final partner = room.directChatMatrixID!;
      final displayName = room.getLocalizedDisplayname();
      chats.add(
        SuggesterChat(
          roomId: room.id,
          networkId: spaces[room.id]?.id,
          identifier: primaryIdentifier(
            userId: partner,
            profileIdentifiers: _cachedProfile(partner),
            displayName: displayName,
            defaultRegion: region,
          ),
          name: _nameIdentifier(displayName),
          contactId: store.contactForRoom(room.id)?.id,
          named: isContactName(displayName),
        ),
      );
    }
    suggestions.value = suggestMerges(
      chats,
      dismissedPairs: {
        for (final pair in store.stored.dismissedSuggestions)
          dismissedPairKey(pair[0], pair[1]),
      },
    );
  }

  /// Bridge ghosts (a `<bridge>_` localpart) whose user ID carries no phone
  /// number or email, such as Google Messages contacts. Plain Matrix users
  /// have no bridge profile field, so they are not asked.
  static bool _mayHaveProfileIdentifiers(String userId) {
    final localpart = userId.localpart ?? '';
    return RegExp(r'^[a-z0-9]+_').hasMatch(localpart) &&
        identifiersFromUserId(userId).isEmpty;
  }

  /// The phone number the other person of the direct chat [room] is known
  /// by, from their user ID, their fetched profile or the chat's name. Null
  /// for a group chat and when no number is known.
  ContactIdentifier? phoneOf(Room room) {
    final partner = room.directChatMatrixID;
    if (partner == null) return null;
    final identifier = primaryIdentifier(
      userId: partner,
      profileIdentifiers: _cachedProfile(partner),
      displayName: room.getLocalizedDisplayname(),
      defaultRegion: phoneRegion(),
    );
    return identifier?.type == IdentifierType.phone ? identifier : null;
  }

  Object? _cachedProfile(String userId) {
    if (_profiles.containsKey(userId)) return _profiles[userId];
    final raw = cache?.getString('$_cachePrefix$userId');
    if (raw == null) return null;
    try {
      final json = jsonDecode(raw) as Map<String, Object?>;
      final fetched = json['fetched'] as int;
      final value = json['value'];
      final lifetime = value is List && value.isNotEmpty
          ? cacheLifetime
          : emptyCacheLifetime;
      if (DateTime.now().millisecondsSinceEpoch - fetched >
          lifetime.inMilliseconds) {
        return null;
      }
      return _profiles[userId] = value;
    } catch (_) {
      return null;
    }
  }

  /// Whether [userId]'s profile list is known and fresh, including knowing
  /// that it has none.
  bool _isCached(String userId) {
    _cachedProfile(userId);
    return _profiles.containsKey(userId);
  }

  /// Fetches profile identifiers not known yet. Returns whether any user
  /// turned out to have some.
  Future<bool> _fetchMissingProfiles() async {
    final missing = {
      for (final room in _directChats)
        if (_mayHaveProfileIdentifiers(room.directChatMatrixID!) &&
            !_isCached(room.directChatMatrixID!))
          room.directChatMatrixID!,
    }.take(maxFetchesPerPass);
    var found = false;
    for (final userId in missing) {
      if (_disposed) break;
      Object? value;
      try {
        value = await fetchProfileIdentifiers(userId);
      } catch (e) {
        // Not cached: asked again on a later pass.
        Logs().v('Unable to fetch bridge identifiers of $userId', e);
        continue;
      }
      _profiles[userId] = value;
      await cache?.setString(
        '$_cachePrefix$userId',
        jsonEncode({
          'fetched': DateTime.now().millisecondsSinceEpoch,
          'value': value,
        }),
      );
      if (identifiersFromProfileList(value).isNotEmpty) found = true;
    }
    return found;
  }

  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    // On logout the store may already be gone.
    try {
      _store.revision.removeListener(schedule);
    } catch (_) {}
    for (final subscription in _subscriptions) {
      subscription.cancel();
    }
    suggestions.dispose();
  }
}
