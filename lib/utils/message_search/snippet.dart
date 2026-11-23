// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// A stretch of a message short enough for a result tile, with the places
/// where the search words occur.
class MessageSnippet {
  /// Single-line text. Starts or ends with an ellipsis where the message
  /// continues beyond it.
  final String text;

  /// Half-open `(start, end)` ranges into [text] to emphasise, in order and
  /// not overlapping.
  final List<(int, int)> highlights;

  const MessageSnippet(this.text, this.highlights);
}

final _wordCharacter = RegExp(r'[\p{L}\p{N}]', unicode: true);
final _lineBreaks = RegExp(r'\s+');

/// Cuts [body] down to about [maxLength] characters around the first place
/// one of [terms] starts a word, and marks every such place.
///
/// Matching follows the engines: case is ignored and a term matches the
/// beginning of a longer word, but not its middle. When nothing matches (the
/// homeserver may have matched a different word form, or an accented
/// spelling), the snippet is the start of the message without highlights.
MessageSnippet buildSnippet(
  String body,
  Iterable<String> terms, {
  int maxLength = 120,
}) {
  // Result tiles show one or two lines, so line breaks only waste the space.
  final flat = body.replaceAll(_lineBreaks, ' ').trim();
  final lower = flat.toLowerCase();
  // On the web, lower-casing changes the length of a few characters (the
  // Turkish dotted capital I becomes two code units). The offsets found in
  // the lower-cased text would then point at the wrong place in the
  // original, so such a message is shown without highlights.
  final searchable = lower.length == flat.length;

  final matches = <(int, int)>[];
  if (searchable) {
    for (final term in terms) {
      final needle = term.toLowerCase();
      if (needle.isEmpty) continue;
      var from = 0;
      while (true) {
        final at = lower.indexOf(needle, from);
        if (at < 0) break;
        final startsWord = at == 0 || !_wordCharacter.hasMatch(lower[at - 1]);
        if (startsWord) matches.add((at, at + needle.length));
        from = at + needle.length;
      }
    }
    matches.sort((a, b) => a.$1.compareTo(b.$1));
  }

  var start = 0;
  var end = flat.length;
  if (flat.length > maxLength) {
    if (matches.isEmpty) {
      end = maxLength;
    } else {
      // Keep a quarter of the room for what leads up to the match, so the
      // match has context on both sides.
      start = matches.first.$1 - maxLength ~/ 4;
      if (start < 0) start = 0;
      end = start + maxLength;
      if (end > flat.length) {
        end = flat.length;
        start = end - maxLength;
      }
      // Begin at a word boundary when one is close.
      final space = flat.indexOf(' ', start);
      if (start > 0 && space >= 0 && space < matches.first.$1) {
        start = space + 1;
      }
    }
  }

  final prefix = start > 0 ? '…' : '';
  final suffix = end < flat.length ? '…' : '';
  final highlights = <(int, int)>[];
  var covered = 0;
  for (final (matchStart, matchEnd) in matches) {
    if (matchStart < start || matchEnd > end) continue;
    // Two terms can match the same text ("ann" and "anna"): keep the first.
    if (matchStart < covered) continue;
    highlights.add((
      matchStart - start + prefix.length,
      matchEnd - start + prefix.length,
    ));
    covered = matchEnd;
  }
  return MessageSnippet(
    '$prefix${flat.substring(start, end)}$suffix',
    highlights,
  );
}
