// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/message_search/message_search_hit.dart';
import 'package:flutter_test/flutter_test.dart';

MessageSearchHit hit(String id, int ts, {String? senderName}) =>
    MessageSearchHit(
      eventId: id,
      roomId: '!room:example.org',
      senderId: '@naveen:example.org',
      senderName: senderName,
      body: 'body of $id',
      timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
    );

void main() {
  test('orders newest first across both lists', () {
    final merged = mergeHits(
      [hit(r'$a', 300), hit(r'$b', 100)],
      [hit(r'$c', 200), hit(r'$d', 400)],
    );
    expect(merged.map((h) => h.eventId), [r'$d', r'$a', r'$c', r'$b']);
  });

  test('lists an event once when both engines found it', () {
    final merged = mergeHits(
      [hit(r'$a', 300), hit(r'$b', 100)],
      [hit(r'$a', 300), hit(r'$c', 200)],
    );
    expect(merged.map((h) => h.eventId), [r'$a', r'$c', r'$b']);
  });

  test('a duplicate contributes the profile the first hit lacked', () {
    final localThenServer = mergeHits(
      [hit(r'$a', 300)],
      [hit(r'$a', 300, senderName: 'Naveen')],
    );
    expect(localThenServer.single.senderName, 'Naveen');
    final serverThenLocal = mergeHits(
      [hit(r'$a', 300, senderName: 'Naveen')],
      [hit(r'$a', 300)],
    );
    expect(serverThenLocal.single.senderName, 'Naveen');
  });

  test('equal timestamps keep one order however they arrive', () {
    final one = mergeHits([hit(r'$b', 100)], [hit(r'$a', 100)]);
    final other = mergeHits([hit(r'$a', 100)], [hit(r'$b', 100)]);
    expect(one.map((h) => h.eventId), [r'$a', r'$b']);
    expect(other.map((h) => h.eventId), [r'$a', r'$b']);
  });
}
