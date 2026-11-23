// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/message_search/snippet.dart';
import 'package:flutter_test/flutter_test.dart';

List<String> highlighted(MessageSnippet snippet) => [
  for (final (start, end) in snippet.highlights)
    snippet.text.substring(start, end),
];

void main() {
  test('short message is kept whole with the match marked', () {
    final snippet = buildSnippet('Dinner with Naveen tonight', ['naveen']);
    expect(snippet.text, 'Dinner with Naveen tonight');
    expect(highlighted(snippet), ['Naveen']);
  });

  test('marks word beginnings, not the middle of a word', () {
    final snippet = buildSnippet('Ann met Joanne and Anna', ['ann']);
    expect(highlighted(snippet), ['Ann', 'Ann']);
    expect(snippet.highlights, [(0, 3), (19, 22)]);
  });

  test('marks every term and every occurrence in order', () {
    final snippet = buildSnippet('pizza or pasta? Pizza!', ['pasta', 'pizza']);
    expect(highlighted(snippet), ['pizza', 'pasta', 'Pizza']);
  });

  test('overlapping terms mark the text once', () {
    final snippet = buildSnippet('Anna called', ['ann', 'anna']);
    expect(highlighted(snippet), ['Ann']);
  });

  test('long message is cut around the first match', () {
    final body =
        '${'lorem ipsum ' * 40}then Naveen arrived${' dolor sit' * 40}';
    final snippet = buildSnippet(body, ['naveen'], maxLength: 60);
    expect(snippet.text.startsWith('…'), isTrue);
    expect(snippet.text.endsWith('…'), isTrue);
    expect(snippet.text.length, lessThanOrEqualTo(62));
    expect(highlighted(snippet), ['Naveen']);
    // The cut begins on a word, not inside one.
    expect(snippet.text.substring(1), startsWith('ipsum then Naveen'));
  });

  test('match near the end keeps the window inside the message', () {
    final body = '${'lorem ipsum ' * 40}bye Naveen';
    final snippet = buildSnippet(body, ['naveen'], maxLength: 60);
    expect(snippet.text.endsWith('bye Naveen'), isTrue);
    expect(highlighted(snippet), ['Naveen']);
  });

  test('without a match the start of the message is shown', () {
    final body = 'running late ' * 30;
    final snippet = buildSnippet(body, ['ran'], maxLength: 40);
    expect(snippet.text, '${body.substring(0, 40)}…');
    expect(snippet.highlights, isEmpty);
  });

  test('line breaks collapse so the tile stays compact', () {
    final snippet = buildSnippet('first line\n\n  Naveen\tsecond', ['naveen']);
    expect(snippet.text, 'first line Naveen second');
    expect(highlighted(snippet), ['Naveen']);
  });
}
