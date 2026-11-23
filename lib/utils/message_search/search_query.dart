// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// What the user typed into the search bar, reduced to the words both search
/// engines understand.
///
/// The words are runs of letters and digits, lower-cased. Punctuation is
/// dropped because the local full-text index cannot match it, and passing it
/// through would let a stray quote break the local query or turn part of it
/// into an operator.
class SearchQuery {
  /// The trimmed text as typed. This is what the homeserver receives.
  final String text;

  /// Lower-cased words in typing order, without duplicates.
  final List<String> terms;

  const SearchQuery._(this.text, this.terms);

  /// Shorter input would match a large share of all messages while the user is
  /// still typing the first word, which costs both engines work for results
  /// nobody wants.
  static const minLength = 2;

  static final _word = RegExp(r'[\p{L}\p{N}]+', unicode: true);

  /// Returns null when [input] holds nothing worth searching for.
  static SearchQuery? parse(String input) {
    final text = input.trim();
    final terms = <String>[];
    for (final match in _word.allMatches(text.toLowerCase())) {
      final term = match[0]!;
      if (!terms.contains(term)) terms.add(term);
    }
    if (terms.isEmpty) return null;
    if (terms.fold<int>(0, (sum, term) => sum + term.length) < minLength) {
      return null;
    }
    return SearchQuery._(text, List.unmodifiable(terms));
  }

  /// The query in SQLite FTS5 syntax: every word has to occur, and each one
  /// also matches as the start of a longer word so results appear while the
  /// word is still being typed.
  ///
  /// A single letter only matches itself. As the start of a word it would
  /// match a large part of the vocabulary, which no index shortens: measured
  /// on 300,000 messages, such a lookup took 480 ms where a two-letter one
  /// took 1 ms.
  ///
  /// Each word is quoted, which makes it a plain string to FTS5 whatever
  /// letters and digits it consists of.
  String get ftsMatch =>
      terms.map((term) => term.length < 2 ? '"$term"' : '"$term"*').join(' ');

  @override
  bool operator ==(Object other) => other is SearchQuery && other.text == text;

  @override
  int get hashCode => text.hashCode;

  @override
  String toString() => 'SearchQuery($text)';
}
