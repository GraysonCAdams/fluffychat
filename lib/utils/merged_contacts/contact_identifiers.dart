// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Extracts the identifier a direct chat is matched on when suggesting
/// merged contacts: a phone number, else an email address, else a display
/// name.
///
/// Inputs are plain strings and decoded JSON so this file stays free of
/// Flutter and Matrix SDK types and runs on every platform, including web.
library;

import 'dart:convert';

import 'package:fluffychat/utils/merged_contacts/phone_number.dart';

enum IdentifierType { phone, email, name }

/// One identifier of a contact, in normalised form: E.164 for phones,
/// lower-cased for emails, [normalizeName] output for names.
class ContactIdentifier {
  final IdentifierType type;
  final String value;

  const ContactIdentifier(this.type, this.value);

  Map<String, String> toJson() => {'type': type.name, 'value': value};

  /// Reads the form written by [toJson]. Returns null for anything else
  /// (unknown type, missing or empty value), since this is read back from
  /// account data that other clients or older versions may have written.
  static ContactIdentifier? fromJson(Object? json) {
    if (json is! Map) return null;
    final type = IdentifierType.values.asNameMap()[json['type']];
    final value = json['value'];
    if (type == null || value is! String || value.isEmpty) return null;
    return ContactIdentifier(type, value);
  }

  @override
  bool operator ==(Object other) =>
      other is ContactIdentifier && other.type == type && other.value == value;

  @override
  int get hashCode => Object.hash(type, value);

  @override
  String toString() => 'ContactIdentifier(${type.name}, $value)';
}

/// A ghost localpart that embeds a handle, as the iMessage bridge does:
/// `imessage_tel=3a+14045551234` or `imessage_mailto=3aalice=40example.com`.
/// The prefix is not fixed to `imessage` so other bridges using the same
/// shape are recognised too. Group 1 is the scheme, group 2 the still
/// escaped handle.
final _handleLocalpart = RegExp(r'^.+?_(tel|mailto)=3a(.+)$');

final _email = RegExp(r'^[^@\s]+@[^@\s]+$');

final _lowerAsciiLetter = RegExp(r'^[a-z]$');

/// Decodes mautrix localpart escaping: `=XX` is the byte with hex value XX,
/// `__` is `_`, and `_` before a letter marks that letter as upper case
/// (localparts must be lower case). Bytes are collected and decoded as UTF-8
/// because a non-ASCII character is escaped as several `=XX` sequences.
String _decodeLocalpart(String escaped) {
  final bytes = <int>[];
  for (var i = 0; i < escaped.length; i++) {
    final c = escaped[i];
    if (c == '=' && i + 2 < escaped.length) {
      final byte = int.tryParse(escaped.substring(i + 1, i + 3), radix: 16);
      if (byte != null) {
        bytes.add(byte);
        i += 2;
        continue;
      }
    }
    if (c == '_' && i + 1 < escaped.length) {
      final next = escaped[i + 1];
      if (next == '_') {
        bytes.add('_'.codeUnitAt(0));
        i++;
        continue;
      }
      if (_lowerAsciiLetter.hasMatch(next)) {
        bytes.addAll(utf8.encode(next.toUpperCase()));
        i++;
        continue;
      }
    }
    bytes.addAll(utf8.encode(c));
  }
  return utf8.decode(bytes, allowMalformed: true);
}

String? _normalizeEmail(String raw) {
  final email = raw.trim().toLowerCase();
  return _email.hasMatch(email) ? email : null;
}

ContactIdentifier? _fromHandle(
  String scheme,
  String handle,
  String defaultRegion,
) {
  switch (scheme.toLowerCase()) {
    case 'tel':
      final phone = normalizePhone(handle, defaultRegion: defaultRegion);
      return phone == null
          ? null
          : ContactIdentifier(IdentifierType.phone, phone);
    case 'mailto':
      final email = _normalizeEmail(handle);
      return email == null
          ? null
          : ContactIdentifier(IdentifierType.email, email);
  }
  return null;
}

/// Identifiers embedded in a bridge ghost's Matrix user ID, such as
/// `@imessage_tel=3a+14045551234:server` (a phone) or
/// `@imessage_mailto=3aalice=40example.com:server` (an email).
///
/// Returns an empty list for IDs that carry no handle, which includes
/// Google Messages ghosts (`@gmessages_1.42:server`, whose number is only in
/// the profile) and ordinary Matrix users.
List<ContactIdentifier> identifiersFromUserId(
  String userId, {
  String defaultRegion = 'US',
}) {
  var localpart = userId.startsWith('@') ? userId.substring(1) : userId;
  // The server name starts at the first colon: an escaped localpart never
  // contains a literal one.
  final colon = localpart.indexOf(':');
  if (colon != -1) localpart = localpart.substring(0, colon);

  final match = _handleLocalpart.firstMatch(localpart);
  if (match == null) return const [];
  final identifier = _fromHandle(
    match[1]!,
    _decodeLocalpart(match[2]!),
    defaultRegion,
  );
  return identifier == null ? const [] : [identifier];
}

/// Identifiers from the decoded JSON value of the
/// `com.beeper.bridge.identifiers` profile field, a list of URIs such as
/// `["tel:+14045551234", "mailto:bob@example.com"]`.
///
/// Anything that is not a list, entries that are not strings, unknown
/// schemes and unparseable values are skipped, because the field is written
/// by bridges this app does not control. Duplicates are removed, keeping the
/// first occurrence.
List<ContactIdentifier> identifiersFromProfileList(
  Object? field, {
  String defaultRegion = 'US',
}) {
  if (field is! List) return const [];
  final result = <ContactIdentifier>[];
  for (final entry in field) {
    if (entry is! String) continue;
    final colon = entry.indexOf(':');
    if (colon == -1) continue;
    final identifier = _fromHandle(
      entry.substring(0, colon).trim(),
      entry.substring(colon + 1),
      defaultRegion,
    );
    if (identifier != null && !result.contains(identifier)) {
      result.add(identifier);
    }
  }
  return result;
}

final _whitespace = RegExp(r'\s+');

/// Anything that is not a letter, combining mark, digit or whitespace.
/// Unicode-aware so names such as "Zoë" or "Søren" keep their letters.
final _punctuation = RegExp(r'[^\p{L}\p{M}\p{N}\s]', unicode: true);

/// Normalises a display name for name matching: lower case, punctuation
/// removed, whitespace collapsed to single spaces and trimmed, so
/// "Harrison  Young!" and "harrison young" compare equal.
String normalizeName(String displayName) => displayName
    .toLowerCase()
    .replaceAll(_punctuation, '')
    .replaceAll(_whitespace, ' ')
    .trim();

/// The single identifier a chat is matched on, taking the first available
/// in this order:
///
/// 1. Phone: from [userId], then [profileIdentifiers] (the decoded
///    `com.beeper.bridge.identifiers` field), then [displayName] when it is
///    itself a phone number (unnamed SMS contacts are shown as
///    "(866) 405-4049").
/// 2. Email: from [userId], then [profileIdentifiers].
/// 3. Name: [normalizeName] of [displayName], when not empty.
///
/// Returns null when none of these yields anything.
ContactIdentifier? primaryIdentifier({
  required String userId,
  Object? profileIdentifiers,
  String? displayName,
  String defaultRegion = 'US',
}) {
  final candidates = [
    ...identifiersFromUserId(userId, defaultRegion: defaultRegion),
    ...identifiersFromProfileList(
      profileIdentifiers,
      defaultRegion: defaultRegion,
    ),
  ];
  for (final identifier in candidates) {
    if (identifier.type == IdentifierType.phone) return identifier;
  }
  if (displayName != null) {
    final phone = normalizePhone(displayName, defaultRegion: defaultRegion);
    if (phone != null) return ContactIdentifier(IdentifierType.phone, phone);
  }
  for (final identifier in candidates) {
    if (identifier.type == IdentifierType.email) return identifier;
  }
  if (displayName != null) {
    final name = normalizeName(displayName);
    if (name.isNotEmpty) return ContactIdentifier(IdentifierType.name, name);
  }
  return null;
}
