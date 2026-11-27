// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:async/async.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'model.dart';
import 'same_groups.dart';

/// Where a [MergedContactsStore] reads and writes its account data, and how
/// it learns which rooms can be merged. The app uses [ClientMergedContactsBackend];
/// tests use a fake.
abstract class MergedContactsBackend {
  /// The current content of the account data event, or null when unset.
  Map<String, Object?>? read();

  Future<void> write(Map<String, Object?> content);

  /// Fires after the account data event changed on the server, whoever
  /// wrote it, including this device's own writes coming back.
  Stream<void> get onRemoteChange;

  /// Fires when rooms may have become usable or unusable for merging: a room
  /// was left or joined, or the direct chat list changed.
  Stream<void> get onRoomsChanged;

  /// Whether [roomId] is a joined chat, one-to-one or group, that can be
  /// part of a contact.
  bool isUsableRoom(String roomId);

  /// Completes once the account data and the rooms are loaded.
  Future<void> get ready;

  /// The group chats on one bridge with the same people, each the room IDs
  /// most recently active first with the group's own name, if any.
  List<({List<String> rooms, String? name})> sameGroups() => const [];

  int now() => DateTime.now().millisecondsSinceEpoch;

  void dispose() {}
}

/// Account data and rooms of a matrix [Client].
class ClientMergedContactsBackend extends MergedContactsBackend {
  final Client client;

  ClientMergedContactsBackend(this.client);

  @override
  Map<String, Object?>? read() =>
      client.accountData[MergedContactsData.accountDataType]?.content;

  @override
  Future<void> write(Map<String, Object?> content) => client.setAccountData(
    client.userID!,
    MergedContactsData.accountDataType,
    content,
  );

  @override
  Stream<void> get onRemoteChange => client.onSync.stream.where(
    (sync) =>
        sync.accountData?.any(
          (event) => event.type == MergedContactsData.accountDataType,
        ) ??
        false,
  );

  /// Fires on what can change which rooms merge: joins and leaves, the
  /// direct chat list, members, and new messages, which decide the most
  /// recently active of same-people groups.
  Stream<void> get _onRoomsChanged => client.onSync.stream.where(
    (sync) =>
        (sync.rooms?.leave?.isNotEmpty ?? false) ||
        (sync.rooms?.invite?.isNotEmpty ?? false) ||
        (sync.accountData?.any((event) => event.type == 'm.direct') ?? false) ||
        (sync.rooms?.join?.values.any(
              (update) =>
                  (update.timeline?.events?.isNotEmpty ?? false) ||
                  (update.state?.any(
                        (event) => event.type == EventTypes.RoomMember,
                      ) ??
                      false),
            ) ??
            false),
  );

  @override
  bool isUsableRoom(String roomId) {
    final room = client.getRoomById(roomId);
    return room != null && room.membership == Membership.join && !room.isSpace;
  }

  @override
  Future<void> get ready async {
    await client.roomsLoading;
    await client.accountDataLoading;
  }

  @override
  Stream<void> get onRoomsChanged =>
      StreamGroup.merge([_onRoomsChanged, _membersLoaded.stream]);

  /// Fires when the member list of a group, missing from memory when the
  /// same-people groups were looked for, has been loaded.
  final StreamController<void> _membersLoaded = StreamController.broadcast();

  @override
  List<({List<String> rooms, String? name})> sameGroups() => [
    for (final group in findSameGroups(client, onIncomplete: _loadMembers))
      (rooms: group.roomIds, name: group.name),
  ];

  /// The groups whose members were asked for, so each is asked once.
  final Set<String> _asked = {};

  /// Loads [room]'s members once a session, shared with the chat list's
  /// group avatars so the server is asked once, then looks again.
  void _loadMembers(Room room) {
    if (!_asked.add(room.id)) return;
    GroupAvatar.loadMembers(room).then((_) {
      if (!_membersLoaded.isClosed) _membersLoaded.add(null);
    });
  }

  @override
  void dispose() => _membersLoaded.close();
}

/// Merged contacts of one account: the account data event
/// `im.fluffychat.merged_contacts` read into an index from room ID to
/// contact, and every change to it.
///
/// One store exists per [Client], reached through [forClient], so the chat
/// list, the chat screen and the push handler all see the same contacts
/// without passing the store around.
class MergedContactsStore {
  final MergedContactsBackend backend;

  MergedContactsStore(this.backend) {
    _remoteSub = backend.onRemoteChange.listen((_) => _onRemote());
    _roomsSub = backend.onRoomsChanged.listen((_) => _reindex());
    _stored = MergedContactsData.fromJson(backend.read());
    _reindex();
    loaded = backend.ready.then((_) {
      if (_disposed) return;
      _stored = MergedContactsData.fromJson(backend.read());
      _reindex(force: true);
    });
  }

  /// Completes once the account data and rooms are loaded and indexed.
  /// Code that runs before the app is up, like the push handler, waits for
  /// it before asking for contacts.
  late final Future<void> loaded;

  static final Expando<MergedContactsStore> _stores = Expando();

  /// The store of [client], created on first use.
  static MergedContactsStore forClient(Client client) => _stores[client] ??=
      MergedContactsStore(ClientMergedContactsBackend(client));

  /// Forgets and disposes the store of [client], for example on logout.
  static void disposeFor(Client client) {
    _stores[client]?.dispose();
    _stores[client] = null;
  }

  StreamSubscription<void>? _remoteSub;
  StreamSubscription<void>? _roomsSub;
  bool _disposed = false;

  MergedContactsData _stored = MergedContactsData.empty;

  /// What this device last wrote, kept for [repairWindow] to repair a
  /// write from another device that overwrote it (see
  /// [MergedContactsData.reconcile]).
  MergedContactsData? _lastWrite;
  int _lastWriteAt = 0;

  /// How long after a write this device still repairs an overwrite. Two
  /// devices only race within seconds; a longer window could bring back a
  /// contact whose tombstone another device has since pruned.
  static const Duration repairWindow = Duration(minutes: 5);

  List<MergedContactEntry> _contacts = const [];
  Map<String, MergedContactEntry> _byRoom = const {};
  Map<String, MergedContactEntry> _byId = const {};

  /// Counts changes to the contacts as shown, so widgets can listen and
  /// caches can tell whether they are stale.
  final ValueNotifier<int> revision = ValueNotifier(0);

  /// The stored event, tombstones and unusable rooms included.
  MergedContactsData get stored => _stored;

  /// The contacts as shown, each with at least two usable rooms.
  List<MergedContactEntry> get contacts => _contacts;

  /// The contact [roomId] belongs to, if any. Constant time, as the chat
  /// list asks for every room it lists.
  MergedContactEntry? contactForRoom(String roomId) => _byRoom[roomId];

  MergedContactEntry? contactById(String id) => _byId[id];

  bool get isEmpty => _contacts.isEmpty;

  void _onRemote() {
    final remote = MergedContactsData.fromJson(backend.read());
    _stored = remote;
    _reindex();
    // Another device may have written a copy that predates this device's
    // last edit. Write the reconciled copy back so the edit survives; once
    // both devices agree the reconciled copy equals the remote one and
    // nothing more is written.
    if (backend.now() - _lastWriteAt > repairWindow.inMilliseconds) {
      _lastWrite = null;
    }
    final lastWrite = _lastWrite;
    // A write of this device still on its way lands after this copy, so
    // there is nothing to repair yet.
    if (lastWrite == null || _writesInFlight > 0) return;
    final repaired = MergedContactsData.reconcile(remote, lastWrite);
    if (repaired.sameAs(remote)) return;
    _commit(repaired).catchError(
      (Object e, StackTrace s) =>
          Logs().w('Unable to repair merged contacts', e, s),
    );
  }

  void _reindex({bool force = false}) {
    if (_disposed) return;
    final contacts = [..._stored.normalized(backend.isUsableRoom)];
    contacts.addAll(_automaticContacts(contacts));
    if (!force && _sameContacts(contacts, _contacts)) return;
    _contacts = contacts;
    _byId = {for (final contact in contacts) contact.id: contact};
    _byRoom = {
      for (final contact in contacts)
        for (final room in contact.rooms) room: contact,
    };
    revision.value++;
  }

  /// A contact for each set of same-people groups on one bridge that the
  /// user has not split up and none of whose rooms is in [stored], a
  /// contact the user made. Its rooms are most recently active first, and
  /// new messages go to the first.
  List<MergedContactEntry> _automaticContacts(List<MergedContactEntry> stored) {
    final claimed = {for (final contact in stored) ...contact.rooms};
    final dismissed = {
      for (final pair in _stored.dismissedSuggestions)
        _pairKey(pair[0], pair[1]),
    };
    final result = <MergedContactEntry>[];
    for (final group in backend.sameGroups()) {
      final rooms = [
        for (final room in group.rooms)
          if (!claimed.contains(room) && backend.isUsableRoom(room)) room,
      ];
      if (rooms.length < 2) continue;
      var split = false;
      for (var i = 0; i < rooms.length && !split; i++) {
        for (var j = i + 1; j < rooms.length && !split; j++) {
          split = dismissed.contains(_pairKey(rooms[i], rooms[j]));
        }
      }
      if (split) continue;
      claimed.addAll(rooms);
      result.add(
        MergedContactEntry(
          id: _automaticId(rooms),
          rooms: rooms,
          sendVia: rooms.first,
          updated: 0,
          name: group.name,
        ),
      );
    }
    return result;
  }

  /// The same ID for the same rooms whichever is most recent, so the
  /// conversation keeps its route as messages arrive.
  static String _automaticId(List<String> rooms) {
    final sorted = [...rooms]..sort();
    final hash = sorted.join('|').hashCode.toUnsigned(32).toRadixString(16);
    return '${MergedContactEntry.automaticIdPrefix}$hash';
  }

  static bool _sameContacts(
    List<MergedContactEntry> a,
    List<MergedContactEntry> b,
  ) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i].id != b[i].id ||
          jsonEncode(a[i].toJson()) != jsonEncode(b[i].toJson())) {
        return false;
      }
    }
    return true;
  }

  /// Applies [change] to the newest known copy of the event, shows the
  /// result at once and writes it. A failed write puts the previous copy
  /// back and rethrows.
  Future<void> _update(
    MergedContactsData Function(MergedContactsData data, int now) change,
  ) async {
    final now = backend.now();
    final remote = MergedContactsData.fromJson(backend.read());
    final lastWrite = _lastWrite;
    final base =
        lastWrite == null || now - _lastWriteAt > repairWindow.inMilliseconds
        ? remote
        : MergedContactsData.reconcile(remote, lastWrite);
    final next = change(base, now).withoutOldTombstones(now);
    await _commit(next);
  }

  int _writesInFlight = 0;

  Future<void> _commit(MergedContactsData next) async {
    final previous = _stored;
    _lastWrite = next;
    _lastWriteAt = backend.now();
    _stored = next;
    _reindex();
    _writesInFlight++;
    try {
      await backend.write(next.toJson());
    } catch (_) {
      _lastWrite = null;
      _stored = previous;
      _reindex();
      rethrow;
    } finally {
      _writesInFlight--;
    }
  }

  static final Random _random = Random.secure();

  static String _newId() =>
      'c_${List.generate(8, (_) => _random.nextInt(16).toRadixString(16)).join()}';

  static MergedContactsData _withContact(
    MergedContactsData data,
    MergedContactEntry contact,
  ) => MergedContactsData(
    contacts: {...data.contacts, contact.id: contact},
    dismissedSuggestions: data.dismissedSuggestions,
  );

  /// Merges [roomIds] into one contact and returns its ID. Rooms already in
  /// other contacts move to this one. With [intoContactId] the rooms are
  /// added to that contact, after its own. A contact the app made for
  /// same-people groups is not stored, so adding to it stores a new
  /// contact with its rooms and [roomIds], whose ID is returned.
  Future<String> merge(
    List<String> roomIds, {
    String? intoContactId,
    String? name,
    Map<String, Object?>? identifier,
  }) async {
    final automatic = intoContactId == null ? null : _byId[intoContactId];
    if (automatic != null && automatic.automatic) {
      return merge(
        [...automatic.rooms, ...roomIds],
        name: name ?? automatic.name,
        identifier: identifier,
      );
    }
    final id = intoContactId ?? _newId();
    await _update((data, now) {
      final existing = data.contacts[id];
      final rooms = <String>[
        if (existing != null && !existing.removed) ...existing.rooms,
      ];
      for (final room in roomIds) {
        if (!rooms.contains(room)) rooms.add(room);
      }
      var result = data;
      // A room lives in one contact only: take it out of any other.
      for (final other in data.contacts.values) {
        if (other.id == id || other.removed) continue;
        if (!other.rooms.any(rooms.contains)) continue;
        final left = other.rooms.where((r) => !rooms.contains(r)).toList();
        result = _withContact(
          result,
          left.length < 2
              ? other.copyWith(removed: true, rooms: const [], updated: now)
              : other.copyWith(
                  rooms: left,
                  sendVia: () => other.sendViaIn(left),
                  updated: now,
                ),
        );
      }
      final contact = existing != null && !existing.removed
          ? existing.copyWith(
              rooms: rooms,
              updated: now,
              name: name == null ? null : () => name,
              identifier: identifier == null ? null : () => identifier,
            )
          : MergedContactEntry(
              id: id,
              rooms: rooms,
              sendVia: rooms.first,
              updated: now,
              name: name,
              identifier: identifier,
            );
      return _withContact(result, contact);
    });
    return id;
  }

  /// Dissolves the contact; its rooms show as separate chats again. A
  /// contact the app made for same-people groups is split by remembering
  /// each pair of its rooms as kept apart, so it is not made again.
  Future<void> unmerge(String contactId) {
    final automatic = _byId[contactId];
    if (automatic != null && automatic.automatic) {
      return dismissSuggestions(_pairsOf(automatic.rooms));
    }
    return _unmergeStored(contactId);
  }

  static List<(String, String)> _pairsOf(List<String> rooms) => [
    for (var i = 0; i < rooms.length; i++)
      for (var j = i + 1; j < rooms.length; j++) (rooms[i], rooms[j]),
  ];

  Future<void> _unmergeStored(String contactId) => _update((data, now) {
    final contact = data.contacts[contactId];
    if (contact == null) return data;
    return _withContact(
      data,
      contact.copyWith(removed: true, rooms: const [], updated: now),
    );
  });

  /// Takes [roomId] out of its contact, dissolving the contact when fewer
  /// than two rooms would be left. From a contact the app made for
  /// same-people groups, the room is remembered as kept apart from the
  /// others.
  Future<void> removeRoom(String roomId) {
    final automatic = _byRoom[roomId];
    if (automatic != null && automatic.automatic) {
      return dismissSuggestions([
        for (final other in automatic.rooms)
          if (other != roomId) (roomId, other),
      ]);
    }
    return _removeStoredRoom(roomId);
  }

  Future<void> _removeStoredRoom(String roomId) => _update((data, now) {
    var result = data;
    for (final contact in data.contacts.values) {
      if (contact.removed || !contact.rooms.contains(roomId)) continue;
      final left = contact.rooms.where((r) => r != roomId).toList();
      result = _withContact(
        result,
        left.length < 2
            ? contact.copyWith(removed: true, rooms: const [], updated: now)
            : contact.copyWith(
                rooms: left,
                sendVia: () => contact.sendViaIn(left),
                updated: now,
              ),
      );
    }
    return result;
  });

  Future<void> _edit(
    String contactId,
    MergedContactEntry Function(MergedContactEntry contact, int now) edit,
  ) => _update((data, now) {
    final contact = data.contacts[contactId];
    if (contact == null || contact.removed) return data;
    return _withContact(data, edit(contact, now));
  });

  /// Makes [roomId] the network new messages go to by default.
  Future<void> setSendVia(String contactId, String roomId) => _edit(
    contactId,
    (contact, now) => contact.copyWith(sendVia: () => roomId, updated: now),
  );

  Future<void> setSendMode(String contactId, SendMode mode) => _edit(
    contactId,
    (contact, now) => contact.copyWith(sendMode: mode, updated: now),
  );

  /// Sets the contact's name; null or blank goes back to the room's name.
  Future<void> rename(String contactId, String? name) => _edit(
    contactId,
    (contact, now) => contact.copyWith(
      name: () => name == null || name.trim().isEmpty ? null : name.trim(),
      updated: now,
    ),
  );

  Future<void> setFallback(String contactId, bool fallback) => _edit(
    contactId,
    (contact, now) => contact.copyWith(fallback: fallback, updated: now),
  );

  /// Moves [roomId] to [index] in the contact's room order, which is the
  /// order networks are offered in and the fallback order.
  Future<void> reorderRoom(String contactId, String roomId, int index) =>
      _edit(contactId, (contact, now) {
        final rooms = List.of(contact.rooms)..remove(roomId);
        rooms.insert(index.clamp(0, rooms.length), roomId);
        return contact.copyWith(rooms: rooms, updated: now);
      });

  /// Remembers that [roomA] and [roomB] are not the same person, so the
  /// pair is not suggested again.
  Future<void> dismissSuggestion(String roomA, String roomB) =>
      dismissSuggestions([(roomA, roomB)]);

  /// Remembers every pair in [pairs] as not the same person, in one write.
  Future<void> dismissSuggestions(Iterable<(String, String)> pairs) => _update((
    data,
    now,
  ) {
    final dismissed = [...data.dismissedSuggestions];
    final known = {for (final pair in dismissed) _pairKey(pair[0], pair[1])};
    for (final (a, b) in pairs) {
      if (known.add(_pairKey(a, b))) {
        dismissed.add(a.compareTo(b) <= 0 ? [a, b] : [b, a]);
      }
    }
    return MergedContactsData(
      contacts: data.contacts,
      dismissedSuggestions: dismissed,
    );
  });

  static String _pairKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  void dispose() {
    _disposed = true;
    _remoteSub?.cancel();
    _roomsSub?.cancel();
    backend.dispose();
    revision.dispose();
  }
}
