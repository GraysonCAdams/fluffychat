// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

/// Which member room a merged contact sends a new message to.
enum SendMode {
  /// Always the contact's `send_via` room, unless the user picks another one
  /// for a single message.
  preferred('preferred'),

  /// The room of the newest message the other person sent, so a reply goes
  /// back on the network they last wrote from.
  lastReceived('last_received');

  final String jsonValue;

  const SendMode(this.jsonValue);

  static SendMode fromJson(Object? value) => SendMode.values.firstWhere(
    (mode) => mode.jsonValue == value,
    orElse: () => SendMode.preferred,
  );
}

/// One merged contact as stored in the `im.fluffychat.merged_contacts`
/// account data event. Everything shown about the contact (name fallback,
/// avatar, unread counts) is derived from its rooms at runtime; only the
/// user's choices are stored.
class MergedContactEntry {
  final String id;

  /// A name the user gave the contact. Null shows the `send_via` room's
  /// name, or for group chats a name made from the rooms as they are now
  /// (see `MergedContact.displayName`).
  final String? name;

  /// Whether [name] was set by renaming the contact (`name_set`). A group
  /// contact's [name] without it may be one an earlier version stored as
  /// it was shown, which is not kept when it is the rooms' own name.
  final bool nameSet;

  /// Member room IDs, most preferred first. Can hold rooms that are no
  /// longer usable; [MergedContactsData.normalized] drops those from the
  /// view without forgetting them.
  final List<String> rooms;

  /// The room a new message goes to by default. Read through [sendViaIn].
  final String? sendVia;

  final SendMode sendMode;

  /// Milliseconds since epoch of the last change to this contact. Decides
  /// which device's copy of the contact survives a conflicting write.
  final int updated;

  /// Set on a contact the user unmerged. The entry stays for a while so a
  /// device that has not seen the unmerge cannot bring the contact back with
  /// an older copy (see [MergedContactsData.reconcile]).
  final bool removed;

  /// The identifier the contact was suggested by, as
  /// `{"type": "phone", "value": "+1404..."}`, kept so a new chat with the
  /// same identifier on another network can be offered for this contact.
  final Map<String, Object?>? identifier;

  /// Whether a failed send offers to resend through the next network. Off
  /// unless the user turns it on, since a silent move to SMS could leak a
  /// message meant for an encrypted network.
  final bool fallback;

  const MergedContactEntry({
    required this.id,
    required this.rooms,
    required this.updated,
    this.name,
    this.nameSet = false,
    this.sendVia,
    this.sendMode = SendMode.preferred,
    this.removed = false,
    this.identifier,
    this.fallback = false,
  });

  /// The prefix of the ID of a contact the app made by itself for group
  /// chats on one bridge with the same people (see `findSameGroups`). Such
  /// a contact lives in memory only and is never stored.
  static const automaticIdPrefix = 'auto_';

  /// Whether the app made this contact by itself for same-people groups.
  bool get automatic => id.startsWith(automaticIdPrefix);

  /// The `send_via` room if it is one of [usableRooms], else the first of
  /// them in the stored order.
  String? sendViaIn(List<String> usableRooms) {
    final sendVia = this.sendVia;
    if (sendVia != null && usableRooms.contains(sendVia)) return sendVia;
    return usableRooms.isEmpty ? null : usableRooms.first;
  }

  MergedContactEntry copyWith({
    List<String>? rooms,
    String? Function()? name,
    bool? nameSet,
    String? Function()? sendVia,
    SendMode? sendMode,
    int? updated,
    bool? removed,
    Map<String, Object?>? Function()? identifier,
    bool? fallback,
  }) => MergedContactEntry(
    id: id,
    rooms: rooms ?? this.rooms,
    name: name == null ? this.name : name(),
    nameSet: nameSet ?? this.nameSet,
    sendVia: sendVia == null ? this.sendVia : sendVia(),
    sendMode: sendMode ?? this.sendMode,
    updated: updated ?? this.updated,
    removed: removed ?? this.removed,
    identifier: identifier == null ? this.identifier : identifier(),
    fallback: fallback ?? this.fallback,
  );

  /// Parses one contact, or returns null for an entry too malformed to use.
  static MergedContactEntry? fromJson(String id, Object? json) {
    if (json is! Map) return null;
    final updated = json['updated'];
    final rooms = json['rooms'];
    final roomIds = <String>[];
    if (rooms is List) {
      for (final room in rooms) {
        if (room is String && room.isNotEmpty && !roomIds.contains(room)) {
          roomIds.add(room);
        }
      }
    }
    final name = json['name'];
    final sendVia = json['send_via'];
    final identifier = json['identifier'];
    return MergedContactEntry(
      id: id,
      rooms: roomIds,
      updated: updated is int ? updated : 0,
      name: name is String && name.trim().isNotEmpty ? name : null,
      nameSet: json['name_set'] == true,
      sendVia: sendVia is String ? sendVia : null,
      sendMode: SendMode.fromJson(json['send_mode']),
      removed: json['removed'] == true,
      identifier: identifier is Map
          ? Map<String, Object?>.from(identifier.cast<String, Object?>())
          : null,
      fallback: json['fallback'] == true,
    );
  }

  Map<String, Object?> toJson() => removed
      ? {'removed': true, 'rooms': const <String>[], 'updated': updated}
      : {
          'name': ?name,
          if (nameSet) 'name_set': true,
          'rooms': rooms,
          'send_via': ?sendVia,
          'send_mode': sendMode.jsonValue,
          'updated': updated,
          'identifier': ?identifier,
          if (fallback) 'fallback': true,
        };
}

/// The whole `im.fluffychat.merged_contacts` event.
class MergedContactsData {
  static const String accountDataType = 'im.fluffychat.merged_contacts';
  static const int version = 1;

  /// How long an unmerged contact's tombstone is kept. Long enough for any
  /// device that is used at all to sync it.
  static const Duration tombstoneLifetime = Duration(days: 30);

  /// Every contact by ID, tombstones included.
  final Map<String, MergedContactEntry> contacts;

  /// Pairs of room IDs the user said are not the same person.
  final List<List<String>> dismissedSuggestions;

  const MergedContactsData({
    this.contacts = const {},
    this.dismissedSuggestions = const [],
  });

  static const MergedContactsData empty = MergedContactsData();

  /// Contacts that are not tombstones, in ID order.
  Iterable<MergedContactEntry> get active =>
      contacts.values.where((contact) => !contact.removed);

  /// Reads the account data content. Anything unreadable becomes empty
  /// rather than an error, so a bad write by another client cannot break
  /// the chat list.
  static MergedContactsData fromJson(Object? json) {
    if (json is! Map) return empty;
    final contacts = <String, MergedContactEntry>{};
    final rawContacts = json['contacts'];
    if (rawContacts is Map) {
      for (final entry in rawContacts.entries) {
        final id = entry.key;
        if (id is! String) continue;
        final contact = MergedContactEntry.fromJson(id, entry.value);
        if (contact != null) contacts[id] = contact;
      }
    }
    final dismissed = <List<String>>[];
    final rawDismissed = json['dismissed_suggestions'];
    if (rawDismissed is List) {
      for (final pair in rawDismissed) {
        if (pair is List &&
            pair.length == 2 &&
            pair[0] is String &&
            pair[1] is String) {
          dismissed.add([pair[0] as String, pair[1] as String]);
        }
      }
    }
    return MergedContactsData(
      contacts: contacts,
      dismissedSuggestions: dismissed,
    );
  }

  /// The event content, with contacts in ID order so two equal data sets
  /// always encode to the same JSON.
  Map<String, Object?> toJson() {
    final ids = contacts.keys.toList()..sort();
    return {
      'version': version,
      'contacts': {for (final id in ids) id: contacts[id]!.toJson()},
      'dismissed_suggestions': dismissedSuggestions,
    };
  }

  /// Whether [other] stores exactly the same thing.
  bool sameAs(MergedContactsData other) =>
      jsonEncode(toJson()) == jsonEncode(other.toJson());

  /// Combines two copies of the event, keeping the newer copy of each
  /// contact by `updated` (a tie keeps [a]). Dismissed pairs are united,
  /// since a dismissal is never taken back.
  ///
  /// Account data is one event written whole, so two devices editing at once
  /// would otherwise lose the whole of whichever write landed first. With
  /// this, a device that sees its own edit overwritten writes the reconciled
  /// copy back, and only an edit to the same contact can be lost.
  static MergedContactsData reconcile(
    MergedContactsData a,
    MergedContactsData b,
  ) {
    final contacts = <String, MergedContactEntry>{...a.contacts};
    for (final contact in b.contacts.values) {
      final existing = contacts[contact.id];
      if (existing == null || contact.updated > existing.updated) {
        contacts[contact.id] = contact;
      }
    }
    final dismissed = <List<String>>[...a.dismissedSuggestions];
    final seen = {for (final pair in dismissed) _pairKey(pair[0], pair[1])};
    for (final pair in b.dismissedSuggestions) {
      if (seen.add(_pairKey(pair[0], pair[1]))) dismissed.add(pair);
    }
    return MergedContactsData(
      contacts: contacts,
      dismissedSuggestions: dismissed,
    );
  }

  static String _pairKey(String a, String b) =>
      a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

  /// Drops tombstones older than [tombstoneLifetime] before [now].
  MergedContactsData withoutOldTombstones(int now) {
    final cutoff = now - tombstoneLifetime.inMilliseconds;
    return MergedContactsData(
      contacts: {
        for (final contact in contacts.values)
          if (!contact.removed || contact.updated >= cutoff)
            contact.id: contact,
      },
      dismissedSuggestions: dismissedSuggestions,
    );
  }

  /// The contacts as the app should show them: tombstones left out, rooms
  /// that [isUsable] rejects (left, or no longer direct chats) dropped, each
  /// room in at most one contact, and contacts with fewer than two rooms
  /// left dissolved.
  ///
  /// When two contacts claim the same room, the more recently updated one
  /// keeps it: that is the merge the user made last.
  List<MergedContactEntry> normalized(bool Function(String roomId) isUsable) {
    final byNewest = active.toList()
      ..sort((a, b) {
        final byUpdated = b.updated.compareTo(a.updated);
        return byUpdated != 0 ? byUpdated : a.id.compareTo(b.id);
      });
    final claimed = <String>{};
    final result = <MergedContactEntry>[];
    for (final contact in byNewest) {
      final rooms = [
        for (final room in contact.rooms)
          if (!claimed.contains(room) && isUsable(room)) room,
      ];
      if (rooms.length < 2) continue;
      claimed.addAll(rooms);
      result.add(
        contact.copyWith(rooms: rooms, sendVia: () => contact.sendViaIn(rooms)),
      );
    }
    result.sort((a, b) => a.id.compareTo(b.id));
    return result;
  }
}
