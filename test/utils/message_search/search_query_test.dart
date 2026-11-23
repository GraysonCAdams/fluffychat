// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/message_search/search_query.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SearchQuery.parse', () {
    test('splits into lower-cased words and keeps the typed text', () {
      final query = SearchQuery.parse('  Naveen  Dinner ')!;
      expect(query.text, 'Naveen  Dinner');
      expect(query.terms, ['naveen', 'dinner']);
    });

    test('drops punctuation and repeated words', () {
      final query = SearchQuery.parse('"naveen" OR (naveen) café-2024!')!;
      expect(query.terms, ['naveen', 'or', 'café', '2024']);
    });

    test('returns null for input too short to be worth a search', () {
      expect(SearchQuery.parse(''), isNull);
      expect(SearchQuery.parse('   '), isNull);
      expect(SearchQuery.parse('n'), isNull);
      expect(SearchQuery.parse('"*"'), isNull);
      expect(SearchQuery.parse('na'), isNotNull);
      expect(SearchQuery.parse('a b'), isNotNull);
    });

    test('compares by typed text', () {
      expect(SearchQuery.parse('naveen '), SearchQuery.parse(' naveen'));
      expect(SearchQuery.parse('naveen'), isNot(SearchQuery.parse('navee')));
    });
  });

  group('SearchQuery.ftsMatch', () {
    test('quotes every word and makes it a prefix', () {
      expect(SearchQuery.parse('Naveen din')!.ftsMatch, '"naveen"* "din"*');
    });

    test('cannot be turned into FTS5 syntax by the input', () {
      // Unquoted, OR and NEAR are operators and * - ^ : " have meaning.
      expect(
        SearchQuery.parse('ab" OR near(bc) -cd ^de col:ef *')!.ftsMatch,
        '"ab"* "or"* "near"* "bc"* "cd"* "de"* "col"* "ef"*',
      );
    });

    test('a single letter is matched as a whole word', () {
      expect(SearchQuery.parse('a naveen')!.ftsMatch, '"a" "naveen"*');
    });
  });
}
