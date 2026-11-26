// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// The people New Chat lists for a search: the user's chats, the contacts
/// their bridges know and the phone's address book, merged so each person
/// is one row, plus a typed phone number (or email) nobody matched.
///
/// Free of Flutter and Matrix SDK types (a chat is the type parameter), so
/// the merge is tested on plain values.
library;

import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/merged_contacts/contact_identifiers.dart';
import 'package:fluffychat/utils/merged_contacts/phone_number.dart';

/// A network a person is reachable on, for the row's icons. [key] is the
/// bridge's space room ID when known, so a chat's space and the bridge that
/// owns it count once.
class NetworkRef {
  final String key;
  final String name;
  final Uri? icon;

  const NetworkRef({required this.key, required this.name, this.icon});

  /// The network of [bridge].
  factory NetworkRef.ofBridge(BridgeInfo bridge) => NetworkRef(
    key: bridge.spaceRoomId ?? 'bridge:${bridge.name}',
    name: bridge.displayName,
    icon: bridge.icon,
  );
}

/// A chat the search found, with what is known about its other person.
class ChatPersonInput<C> {
  final C chat;
  final String name;
  final Uri? avatar;
  final String? phone;
  final String? email;

  /// The other person's Matrix ID in each of the chat's rooms.
  final List<String> userIds;
  final List<NetworkRef> networks;

  /// Whether the chat is a group rather than a chat with one person.
  final bool group;

  const ChatPersonInput({
    required this.chat,
    required this.name,
    this.avatar,
    this.phone,
    this.email,
    this.userIds = const [],
    this.networks = const [],
    this.group = false,
  });
}

/// One contact from a bridge's contact list.
class BridgeContactInput {
  final BridgeInfo bridge;
  final BridgeUser user;

  const BridgeContactInput(this.bridge, this.user);
}

/// One entry of the phone's address book. Numbers and emails are as the
/// address book stores them.
class PhoneBookEntry {
  final String name;
  final List<String> phones;
  final List<String> emails;

  const PhoneBookEntry({
    required this.name,
    this.phones = const [],
    this.emails = const [],
  });
}

/// One row of New Chat's results.
class NewChatPerson<C> {
  String name;
  Uri? avatar;

  /// The chat that opens on tap, when the person has one.
  C? chat;

  /// E.164 numbers, without repeats.
  final List<String> phones = [];

  /// Lower-cased emails, without repeats.
  final List<String> emails = [];
  final Set<String> userIds = {};

  /// The person as each bridge that lists them knows them, by bridge name.
  final Map<String, BridgeUser> bridgeUsers = {};
  final List<NetworkRef> networks = [];

  /// Whether the person is in the phone's address book.
  bool inPhoneBook = false;

  /// Whether this row is only the number (or email) typed into the
  /// search.
  bool typed = false;

  /// Whether [chat] is a group chat, which is not one person to add to a
  /// new group.
  bool group = false;

  NewChatPerson(this.name);

  String? get phone => phones.isEmpty ? null : phones.first;
  String? get email => emails.isEmpty ? null : emails.first;

  void _addPhone(String? phone) {
    if (phone != null && !phones.contains(phone)) phones.add(phone);
  }

  void _addEmail(String? email) {
    if (email != null && !emails.contains(email)) emails.add(email);
  }

  void _addNetwork(NetworkRef network) {
    if (!networks.any((known) => known.key == network.key)) {
      networks.add(network);
    }
  }
}

final _phoneLike = RegExp(r'^\+?[\d\s().\-]+$');
final _nonDigit = RegExp(r'\D');
final _email = RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$');

/// The E.164 number [query] is, when it is written as a phone number (only
/// digits, spaces, `+`, `-`, `.` and brackets, with at least seven digits)
/// and [normalizePhone] accepts it. Null for anything else, such as a name
/// or a Matrix ID.
String? typedPhoneNumber(String query, {String defaultRegion = 'US'}) {
  final text = query.trim();
  if (!_phoneLike.hasMatch(text)) return null;
  if (text.replaceAll(_nonDigit, '').length < 7) return null;
  return normalizePhone(text, defaultRegion: defaultRegion);
}

/// Whether a person with [name], [phones] and [emails] matches the search
/// [query]: the name or an email contains it, or, when it has three or more
/// digits, a number contains those digits.
bool matchesPersonQuery(
  String query, {
  required String name,
  List<String> phones = const [],
  List<String> emails = const [],
}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return false;
  if (name.toLowerCase().contains(needle)) return true;
  if (emails.any((email) => email.toLowerCase().contains(needle))) {
    return true;
  }
  final digits = needle.replaceAll(_nonDigit, '');
  if (digits.length >= 3 && _phoneLike.hasMatch(needle)) {
    return phones.any(
      (phone) => phone.replaceAll(_nonDigit, '').contains(digits),
    );
  }
  return false;
}

/// The lower-cased email [query] is, when it is written as one. Null for
/// anything else.
String? typedEmailAddress(String query) => _normalizeEmail(query);

String? _normalizeEmail(String raw) {
  final email = raw.trim().toLowerCase();
  return _email.hasMatch(email) ? email : null;
}

/// Merges the three sources into one row per person for [query].
///
/// [chats] are already filtered by the caller (the chat list's search);
/// bridge contacts and address book entries are filtered here with
/// [matchesPersonQuery]. A bridge contact or address book entry joins the
/// first row that shares a phone number, then an email, then (for bridge
/// contacts) a ghost Matrix ID; otherwise it starts a row. Two chats are
/// never merged, since each opens its own room.
///
/// Rows with a chat come first in [chats] order, then the rest by name. A
/// number typed as [query] that no row has gets a row of its own on top,
/// and so does a typed email when [typedEmail] is set.
List<NewChatPerson<C>> mergeNewChatPeople<C>({
  required String query,
  List<ChatPersonInput<C>> chats = const [],
  List<BridgeContactInput> bridgeContacts = const [],
  List<PhoneBookEntry> phoneBook = const [],
  String defaultRegion = 'US',
  bool typedEmail = false,
}) {
  final withChat = <NewChatPerson<C>>[];
  final others = <NewChatPerson<C>>[];
  final byPhone = <String, NewChatPerson<C>>{};
  final byEmail = <String, NewChatPerson<C>>{};
  final byUserId = <String, NewChatPerson<C>>{};

  void index(NewChatPerson<C> person) {
    for (final phone in person.phones) {
      byPhone.putIfAbsent(phone, () => person);
    }
    for (final email in person.emails) {
      byEmail.putIfAbsent(email, () => person);
    }
    for (final userId in person.userIds) {
      byUserId.putIfAbsent(userId, () => person);
    }
  }

  NewChatPerson<C>? find(
    List<String> phones,
    List<String> emails, [
    String? userId,
  ]) {
    for (final phone in phones) {
      if (byPhone[phone] case final person?) return person;
    }
    for (final email in emails) {
      if (byEmail[email] case final person?) return person;
    }
    return userId == null ? null : byUserId[userId];
  }

  for (final input in chats) {
    final person = NewChatPerson<C>(input.name)
      ..chat = input.chat
      ..avatar = input.avatar
      ..group = input.group;
    person._addPhone(input.phone);
    person._addEmail(input.email);
    person.userIds.addAll(input.userIds);
    input.networks.forEach(person._addNetwork);
    withChat.add(person);
    index(person);
  }

  for (final contact in bridgeContacts) {
    final user = contact.user;
    final identifiers = identifiersFromProfileList(
      user.identifiers,
      defaultRegion: defaultRegion,
    );
    final phones = [
      for (final id in identifiers)
        if (id.type == IdentifierType.phone) id.value,
    ];
    final emails = [
      for (final id in identifiers)
        if (id.type == IdentifierType.email) id.value,
    ];
    final name = user.name ?? phones.firstOrNull ?? emails.firstOrNull;
    if (name == null) continue;
    if (!matchesPersonQuery(
      query,
      name: name,
      phones: phones,
      emails: emails,
    )) {
      continue;
    }
    var person = find(phones, emails, user.mxid);
    if (person == null) {
      person = NewChatPerson<C>(name)..avatar = user.avatarUrl;
      others.add(person);
    }
    person.avatar ??= user.avatarUrl;
    phones.forEach(person._addPhone);
    emails.forEach(person._addEmail);
    if (user.mxid case final mxid?) person.userIds.add(mxid);
    person.bridgeUsers.putIfAbsent(contact.bridge.name, () => user);
    person._addNetwork(NetworkRef.ofBridge(contact.bridge));
    index(person);
  }

  for (final entry in phoneBook) {
    final phones = <String>[
      for (final raw in entry.phones)
        ?normalizePhone(raw, defaultRegion: defaultRegion),
    ];
    final emails = <String>[
      for (final raw in entry.emails) ?_normalizeEmail(raw),
    ];
    if (phones.isEmpty && emails.isEmpty) continue;
    final name = entry.name.trim().isNotEmpty
        ? entry.name.trim()
        : phones.isNotEmpty
        ? formatPhoneForDisplay(phones.first)
        : emails.first;
    if (!matchesPersonQuery(
      query,
      name: name,
      phones: phones,
      emails: emails,
    )) {
      continue;
    }
    var person = find(phones, emails);
    if (person == null) {
      person = NewChatPerson<C>(name);
      others.add(person);
    } else if (person.chat == null && !person.inPhoneBook) {
      // The address book name is the one the user chose.
      person.name = name;
    }
    person.inPhoneBook = true;
    phones.forEach(person._addPhone);
    emails.forEach(person._addEmail);
    index(person);
  }

  others.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
  final typed = typedPhoneNumber(query, defaultRegion: defaultRegion);
  final email = typedEmail ? typedEmailAddress(query) : null;
  return [
    if (typed != null && !byPhone.containsKey(typed))
      NewChatPerson<C>(formatPhoneForDisplay(typed))
        ..typed = true
        .._addPhone(typed),
    if (email != null && !byEmail.containsKey(email))
      NewChatPerson<C>(email)
        ..typed = true
        .._addEmail(email),
    ...withChat,
    ...others,
  ];
}

/// [bridges] in the order the compose screen's network switcher lists
/// them: iMessage, then Google Messages, then the rest as given.
List<BridgeInfo> orderBridgesForSwitcher(List<BridgeInfo> bridges) {
  int rank(BridgeInfo bridge) => switch (bridge.name) {
    'imessage' => 0,
    'gmessages' => 1,
    _ => 2,
  };
  final indexed = bridges.indexed.toList()
    ..sort((a, b) {
      final byRank = rank(a.$2).compareTo(rank(b.$2));
      return byRank != 0 ? byRank : a.$1.compareTo(b.$1);
    });
  return [for (final (_, bridge) in indexed) bridge];
}

/// What to pass [bridge]'s `resolve_identifier` and `create_dm` for
/// [person]: the ghost's Matrix ID when that bridge lists them, else their
/// phone number, else their email, else the other person's Matrix ID when
/// [person] is a chat with one person on [bridge]'s network. A number or
/// email is passed only where [lookups] says the bridge takes one. Null
/// when there is nothing to try.
String? identifierForBridge(
  NewChatPerson person,
  BridgeInfo bridge, {
  BridgeLookups? lookups,
}) {
  final known = person.bridgeUsers[bridge.name];
  final onBridge =
      !person.group &&
      person.userIds.length == 1 &&
      person.networks.any(
        (network) => network.key == NetworkRef.ofBridge(bridge).key,
      );
  return known?.mxid ??
      (lookups?.phone ?? true ? person.phone : null) ??
      (lookups?.email ?? true ? person.email : null) ??
      (onBridge ? person.userIds.single : null);
}
