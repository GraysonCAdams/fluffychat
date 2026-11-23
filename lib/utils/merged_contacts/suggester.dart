// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Suggests which direct chats belong to the same person, so the user can
/// merge them into one contact. It only suggests: nothing is merged without
/// the user accepting.
library;

import 'package:fluffychat/utils/merged_contacts/contact_identifiers.dart';

/// One direct chat as the suggester sees it.
class SuggesterChat {
  final String roomId;

  /// The space (network) the chat belongs to, or null if it is in none. A
  /// null network counts as different from every other network, including
  /// another null one.
  final String? networkId;

  /// The identifier from [primaryIdentifier], or null when the chat has
  /// none.
  final ContactIdentifier? identifier;

  /// The chat's display name as a name identifier, or null. Matched in
  /// addition to [identifier], because bridges expose different things: one
  /// puts the phone number in the user ID while another shows only the
  /// contact's name, and the name is then all the two chats have in common.
  final ContactIdentifier? name;

  /// The merged contact this room already belongs to, or null.
  final String? contactId;

  /// Whether the chat shows a person's name. A chat titled with a bare
  /// phone number, short code or email address is unnamed, and unnamed chats
  /// are never suggested: they are mostly automated senders, and a number
  /// alone does not tell the user who they would be merging.
  final bool named;

  const SuggesterChat({
    required this.roomId,
    this.networkId,
    this.identifier,
    this.name,
    this.contactId,
    this.named = true,
  });
}

/// Whether [displayName] reads as a person's name rather than an address:
/// it has at least one letter and is not an email address.
bool isContactName(String displayName) =>
    !displayName.contains('@') &&
    RegExp(r'\p{L}', unicode: true).hasMatch(displayName);

class MergeSuggestion {
  /// Sorted, at least two rooms. For a suggestion with
  /// [existingContactId], this includes the contact's rooms that share the
  /// identifier as well as the new ones.
  final List<String> roomIds;

  final ContactIdentifier matchedOn;

  /// True for a phone or email match (shown as a banner), false for a
  /// name-only match (only listed in the manage screen, since two people can
  /// share a name).
  final bool strong;

  /// Set when the suggestion adds rooms to this existing merged contact
  /// rather than creating a new one.
  final String? existingContactId;

  const MergeSuggestion({
    required this.roomIds,
    required this.matchedOn,
    required this.strong,
    this.existingContactId,
  });

  @override
  String toString() =>
      'MergeSuggestion($roomIds, $matchedOn, strong: $strong, '
      'existingContactId: $existingContactId)';
}

/// The key a dismissed pair of rooms is stored under. Order-independent, so
/// dismissing (a, b) also covers (b, a).
String dismissedPairKey(String a, String b) =>
    a.compareTo(b) <= 0 ? '$a|$b' : '$b|$a';

/// Reads the `dismissed_suggestions` account data form,
/// `[["!a:server", "!b:server"], ...]`, into [dismissedPairKey] keys.
/// Entries that are not a list of two different strings are ignored, since
/// account data can be written by other clients or older versions.
Set<String> dismissedPairKeysFromJson(Object? json) {
  if (json is! List) return {};
  final keys = <String>{};
  for (final entry in json) {
    if (entry is! List || entry.length != 2) continue;
    final a = entry[0];
    final b = entry[1];
    if (a is! String || b is! String || a == b) continue;
    keys.add(dismissedPairKey(a, b));
  }
  return keys;
}

/// Groups [chats] that share an identifier and returns the merges worth
/// offering.
///
/// Unnamed chats ([SuggesterChat.named] false) are left out before grouping.
/// Two chats belong to the same group when they share
/// [SuggesterChat.identifier] or [SuggesterChat.name], directly or through a
/// third chat. [MergeSuggestion.matchedOn] is a phone or email shared by at
/// least two of the group when there is one, otherwise the shared name.
/// A group becomes a suggestion when:
/// - it has at least two rooms, not all already in the same contact;
/// - its rooms belong to at most one existing contact. With one, the
///   suggestion adds the other rooms to it ([MergeSuggestion.existingContactId]).
///   Rooms in two different contacts are skipped: the user has to unmerge
///   first;
/// - no two rooms share a non-null network. A merged contact joins one
///   person's chats across networks; two chats on the same network with the
///   same identifier are a duplicate room from the bridge, or two people
///   sharing a name, so the whole group is skipped.
///
/// Dismissals: a room is dropped from a suggestion when its pair with every
/// other room of that suggestion is in [dismissedPairs] (keys from
/// [dismissedPairKey]). Each room is judged against the full group, before
/// any room is dropped. The suggestion is then discarded if fewer than two
/// rooms remain, or, when it targets an existing contact, if none of the
/// remaining rooms is new to that contact.
///
/// Results are ordered strong matches first, then by first room ID, then by
/// the matched value, so the output is stable for the same input.
///
/// Runs in time linear in the number of chats, plus the square of each
/// group's size for the dismissal check (groups are one person's chats, so
/// small).
List<MergeSuggestion> suggestMerges(
  List<SuggesterChat> chats, {
  Set<String> dismissedPairs = const {},
}) {
  // Keyed by room ID so a room listed twice is counted once.
  final byRoom = <String, SuggesterChat>{
    for (final chat in chats)
      if (chat.named && (chat.identifier != null || chat.name != null))
        chat.roomId: chat,
  };
  Set<ContactIdentifier> keysOf(SuggesterChat chat) => {
    if (chat.identifier != null) chat.identifier!,
    if (chat.name != null) chat.name!,
  };

  // Union-find over room IDs: rooms sharing a key end up under one root.
  final parent = <String, String>{for (final id in byRoom.keys) id: id};
  String find(String id) {
    while (parent[id] != id) {
      id = parent[id] = parent[parent[id]!]!;
    }
    return id;
  }

  final firstRoomWithKey = <ContactIdentifier, String>{};
  for (final chat in byRoom.values) {
    for (final key in keysOf(chat)) {
      final other = firstRoomWithKey.putIfAbsent(key, () => chat.roomId);
      parent[find(chat.roomId)] = find(other);
    }
  }
  final groups = <String, List<SuggesterChat>>{};
  for (final chat in byRoom.values) {
    groups.putIfAbsent(find(chat.roomId), () => []).add(chat);
  }

  final suggestions = <MergeSuggestion>[];
  for (final members in groups.values) {
    if (members.length < 2) continue;
    final keyCounts = <ContactIdentifier, int>{};
    for (final chat in members) {
      for (final key in keysOf(chat)) {
        keyCounts[key] = (keyCounts[key] ?? 0) + 1;
      }
    }
    final shared = [
      for (final MapEntry(:key, :value) in keyCounts.entries)
        if (value > 1) key,
    ]..sort((a, b) {
      final aName = a.type == IdentifierType.name ? 1 : 0;
      final bName = b.type == IdentifierType.name ? 1 : 0;
      if (aName != bName) return aName - bName;
      return a.value.compareTo(b.value);
    });
    final identifier = shared.first;

    final contactIds = {
      for (final chat in members)
        if (chat.contactId != null) chat.contactId!,
    };
    if (contactIds.length > 1) continue;
    final existingContactId = contactIds.isEmpty ? null : contactIds.single;
    if (existingContactId != null &&
        members.every((chat) => chat.contactId == existingContactId)) {
      continue;
    }

    final networks = <String>{};
    final sharesNetwork = members.any(
      (chat) => chat.networkId != null && !networks.add(chat.networkId!),
    );
    if (sharesNetwork) continue;
    final strong = identifier.type != IdentifierType.name;

    final kept = members
        .where(
          (chat) => members.any(
            (other) =>
                other.roomId != chat.roomId &&
                !dismissedPairs.contains(
                  dismissedPairKey(chat.roomId, other.roomId),
                ),
          ),
        )
        .toList();
    if (kept.length < 2) continue;
    if (existingContactId != null &&
        kept.every((chat) => chat.contactId == existingContactId)) {
      continue;
    }

    suggestions.add(
      MergeSuggestion(
        roomIds: kept.map((chat) => chat.roomId).toList()..sort(),
        matchedOn: identifier,
        strong: strong,
        existingContactId: existingContactId,
      ),
    );
  }

  suggestions.sort((a, b) {
    if (a.strong != b.strong) return a.strong ? -1 : 1;
    final byRoom = a.roomIds.first.compareTo(b.roomIds.first);
    if (byRoom != 0) return byRoom;
    return a.matchedOn.value.compareTo(b.matchedOn.value);
  });
  return suggestions;
}
