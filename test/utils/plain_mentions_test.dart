// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/plain_mentions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final mentions = PlainMentions([
    ('@harrison:x', 'Harrison Young'),
    ('@drew:x', 'Drew Andersen'),
    ('@drew2:x', 'Drew Barrymore'),
    ('@gray:x', 'Gray'),
  ]);

  /// The user IDs [text] mentions, in order.
  List<String> ids(String text) => [
    for (final (_, _, id) in mentions.find(text)) id,
  ];

  test('a first name or a full name, whatever its case', () {
    expect(ids('after @Harrison and I'), ['@harrison:x']);
    expect(ids('@Harrison Young said'), ['@harrison:x']);
    expect(ids('ask @harrison'), ['@harrison:x']);
    expect(ids('@HARRISON YOUNG'), ['@harrison:x']);
    expect(ids('Friday, @Gray'), ['@gray:x']);
  });

  test('covers the whole full name, not only the first word', () {
    final found = mentions.find('hey @Harrison Young!');
    expect(found, [(4, 15, '@harrison:x')]);
  });

  test('ends at a word boundary', () {
    expect(ids('@Harrison.'), ['@harrison:x']);
    expect(ids('@Harrison, hi'), ['@harrison:x']);
    expect(ids('@Harrison’s car'), ['@harrison:x']);
    expect(ids("@Harrison's car"), ['@harrison:x']);
    expect(ids('(@Harrison)'), ['@harrison:x']);
    expect(ids('@Harrisonville'), isEmpty);
    expect(ids('@harrison.com'), isEmpty);
    expect(ids('@harrison_y'), isEmpty);
  });

  test('a name two members share stays text', () {
    expect(ids('@Drew are you in'), isEmpty);
    expect(ids('@Drew Andersen are you in'), ['@drew:x']);
    expect(ids('@drew barrymore'), ['@drew2:x']);
  });

  test('leaves e-mail addresses, URLs and other handles alone', () {
    expect(ids('mail harrison@harrison.com'), isEmpty);
    expect(ids('mail me at bob@Harrison'), isEmpty);
    expect(ids('https://x.com/@harrison'), isEmpty);
    expect(ids('https://example.com/?u=@harrison'), isEmpty);
    expect(ids('see you @2pm'), isEmpty);
    expect(ids('@someone else'), isEmpty);
    expect(ids('just an @ sign'), isEmpty);
    expect(ids('@'), isEmpty);
  });

  test('turns mentions into links and escapes the rest', () {
    expect(
      mentions.toHtml('<b> after @Harrison and I'),
      '&lt;b&gt; after <a href="https://matrix.to/#/@harrison:x">Harrison</a>'
      ' and I',
    );
    expect(mentions.toHtml('no one here'), 'no one here');
  });
}
