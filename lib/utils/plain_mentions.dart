// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:matrix/matrix.dart';

/// Finds "@Name" mentions in a plain text message body, as SMS, Google
/// Messages and older iMessage messages carry them, so they can show as
/// pills like the links of a formatted mention.
///
/// A name is a member's display name or its first word, matched without
/// regard to case. It counts only when it names exactly one member: with
/// two members called Drew, "@Drew" stays text while "@Drew Andersen" is
/// a pill. The "@" must not follow a letter, digit or the punctuation of an
/// address, so e-mail addresses and URLs stay as they are, and the name must
/// end at a word boundary.
class PlainMentions {
  /// Each lower-cased name, longest first, with the IDs of the members it
  /// can mean.
  final List<MapEntry<String, Set<String>>> _names;

  PlainMentions._(this._names);

  /// The names of [members], as (user ID, display name) pairs.
  factory PlainMentions(Iterable<(String, String)> members) {
    final names = <String, Set<String>>{};
    void add(String name, String id) {
      final key = name.trim().toLowerCase();
      if (key.isEmpty) return;
      (names[key] ??= {}).add(id);
    }

    for (final (id, displayName) in members) {
      add(displayName, id);
      final words = displayName.trim().split(RegExp(r'\s+'));
      if (words.length > 1) add(words.first, id);
    }
    return PlainMentions._(
      names.entries.toList()
        ..sort((a, b) => b.key.length.compareTo(a.key.length)),
    );
  }

  /// The members [event] can mention: those of its room, and in a merged
  /// contact's chat those of its other rooms too. A name found in the
  /// event's own room wins, so the same person on two networks is not
  /// taken for two people.
  static PlainMentions ofEvent(Event event) {
    final room = event.room;
    final own = PlainMentions(_members(room));
    final contact = MergedContact.ofRoom(room.client, room.id);
    if (contact == null) return own;
    final others = PlainMentions([
      for (final other in contact.rooms)
        if (other.id != room.id) ..._members(other),
    ]);
    return PlainMentions._(
      [
        ...own._names,
        for (final entry in others._names)
          if (!own._names.any((e) => e.key == entry.key)) entry,
      ]..sort((a, b) => b.key.length.compareTo(a.key.length)),
    );
  }

  /// The members of [room] with their display names, and the user also by
  /// the localpart of their ID ("@gray"), as people who know them by it
  /// write it.
  static Iterable<(String, String)> _members(Room room) => [
    for (final user in room.getParticipants())
      (user.id, user.calcDisplayname()),
    if (room.client.userID case final me?)
      if (me.localpart case final localpart?) (me, localpart),
  ];

  static final _letterOrDigit = RegExp(r'[\p{L}\p{N}]', unicode: true);

  /// Characters that, right before "@", make it part of an address.
  static const _addressChars = '._%+-/:@#=&?~';

  static bool _isWordChar(String char) =>
      char == '_' || _letterOrDigit.hasMatch(char);

  /// The mentions in [text], in order, as its "@" offset, the length of
  /// "@Name" and the member's user ID.
  List<(int, int, String)> find(String text) {
    final found = <(int, int, String)>[];
    var i = 0;
    while (true) {
      i = text.indexOf('@', i);
      if (i < 0) break;
      final match = _at(text, i);
      if (match == null) {
        i++;
        continue;
      }
      found.add((i, match.$1 + 1, match.$2));
      i += match.$1 + 1;
    }
    return found;
  }

  /// The length of the name after the "@" at [at] and who it means, or
  /// null when it is no mention.
  (int, String)? _at(String text, int at) {
    if (at > 0) {
      final before = text[at - 1];
      if (_isWordChar(before) || _addressChars.contains(before)) return null;
    }
    final start = at + 1;
    for (final MapEntry(key: name, value: ids) in _names) {
      final end = start + name.length;
      if (end > text.length) continue;
      if (text.substring(start, end).toLowerCase() != name) continue;
      if (!_endsWord(text, end)) continue;
      // The longest name that fits decides: when it means more than one
      // member, a shorter one would too.
      return ids.length == 1 ? (name.length, ids.single) : null;
    }
    return null;
  }

  /// Whether a name ending at [end] ends a word: the text ends, or what
  /// follows is neither a word character nor a "." or "-" running on into
  /// one, as in a domain.
  static bool _endsWord(String text, int end) {
    if (end >= text.length) return true;
    final next = text[end];
    if (_isWordChar(next) || next == '@') return false;
    if ((next == '.' || next == '-') &&
        end + 1 < text.length &&
        _isWordChar(text[end + 1])) {
      return false;
    }
    return true;
  }

  /// The plain [body] of [event] as HTML for the message renderer, see
  /// [toHtml]. A body without "@" skips looking up the members.
  static String htmlOf(Event event, String body) =>
      body.contains('@') ? ofEvent(event).toHtml(body) : _escape(body);

  static String _escape(String text) =>
      text.replaceAll('<', '&lt;').replaceAll('>', '&gt;');

  /// [text] as HTML for the message renderer, with each mention a
  /// matrix.to link to its member and "<" and ">" escaped.
  String toHtml(String text) {
    const escape = _escape;
    final html = StringBuffer();
    var last = 0;
    for (final (at, length, userId) in find(text)) {
      html
        ..write(escape(text.substring(last, at)))
        ..write('<a href="https://matrix.to/#/$userId">')
        ..write(escape(text.substring(at + 1, at + length)))
        ..write('</a>');
      last = at + length;
    }
    html.write(escape(text.substring(last)));
    return html.toString();
  }
}
