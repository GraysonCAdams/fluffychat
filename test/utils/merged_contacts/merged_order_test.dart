// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/merged_contacts/merged_order.dart';
import 'package:flutter_test/flutter_test.dart';

typedef Ev = (String, int);

/// Records with the same content are equal, which here means unchanged.
final order = MergedOrder<Ev>(
  timestamp: _ts,
  key: _key,
  same: (a, b) => a == b,
);

int _ts(Ev e) => e.$2;
int _ts3((String, int, String) e) => e.$2;
String _key3((String, int, String) e) => e.$1;
String _key(Ev e) => e.$1;

/// Events named by key, newest first, from (key, time) pairs.
List<Ev> evs(List<Ev> events) => events;

MergeSource<Ev> src(
  List<Ev> events, {
  bool history = false,
  bool future = false,
}) => MergeSource(events, canRequestHistory: history, canRequestFuture: future);

List<String> keys(List<Ev> events) => [for (final e in events) e.$1];

/// Applies [changes] to [before] the way a list view would, taking the
/// inserted and updated events from [after].
List<Ev> apply(List<Ev> before, List<Ev> after, List<MergeChange> changes) {
  final list = List.of(before);
  for (final change in changes) {
    switch (change) {
      case MergeRemove(:final index):
        list.removeAt(index);
      case MergeInsert(:final index):
        list.insert(index, after[index]);
      case MergeUpdate(:final index):
        list[index] = after[index];
    }
  }
  return list;
}

void main() {
  group('ordering', () {
    test('interleaves rooms newest first', () {
      final merged = order.merge([
        src([('a3', 30), ('a1', 10)]),
        src([('b4', 40), ('b2', 20)]),
      ]);
      expect(keys(merged), ['b4', 'a3', 'b2', 'a1']);
    });

    test('equal timestamps order by room, then key, stably', () {
      final sources = [
        src([('a-z', 10), ('a-y', 10)]),
        src([('b-a', 10)]),
      ];
      expect(keys(order.merge(sources)), ['a-y', 'a-z', 'b-a']);
      // Same result whatever order a room lists its own ties in.
      expect(
        keys(
          order.merge([
            src([('a-y', 10), ('a-z', 10)]),
            src([('b-a', 10)]),
          ]),
        ),
        ['a-y', 'a-z', 'b-a'],
      );
    });

    test(
      'a room listing its events out of time order still merges by time',
      () {
        final merged = order.merge([
          src([('a1', 10), ('a3', 30)]),
          src([('b2', 20)]),
        ]);
        expect(keys(merged), ['a3', 'b2', 'a1']);
      },
    );
  });

  group('safe horizon', () {
    test('hides events older than another room has loaded', () {
      // Room A has loaded back to 50, room B all the way to 5. B's events
      // before 50 could have A's unloaded events between them.
      final sources = [
        src([('a60', 60), ('a50', 50)], history: true),
        src([('b55', 55), ('b20', 20), ('b5', 5)], history: true),
      ];
      expect(order.horizon(sources).lower, 50);
      expect(keys(order.merge(sources)), ['a60', 'b55']);
    });

    test('an exhausted room does not hold the window back', () {
      final sources = [
        src([('a60', 60), ('a50', 50)]),
        src([('b55', 55), ('b20', 20)], history: true),
      ];
      expect(keys(order.merge(sources)), ['a60', 'b55', 'a50']);
    });

    test('everything shows once every room is exhausted', () {
      final sources = [
        src([('a60', 60), ('a50', 50)]),
        src([('b55', 55), ('b20', 20)]),
      ];
      expect(keys(order.merge(sources)), ['a60', 'b55', 'a50', 'b20']);
    });

    test('an empty room that can still load blocks everything', () {
      final sources = [
        src([('a60', 60)]),
        src([], history: true),
      ];
      expect(order.horizon(sources).blocked, isTrue);
      expect(order.merge(sources), isEmpty);
      expect(order.historySource(sources), 1);
    });

    test('an empty, exhausted room is ignored', () {
      final sources = [
        src([('a60', 60)]),
        src([]),
      ];
      expect(keys(order.merge(sources)), ['a60']);
    });

    test('a stalled room stops holding the window', () {
      final sources = [
        src([('a60', 60), ('a10', 10)]),
        src([('b55', 55)], history: true),
      ];
      expect(keys(order.merge(sources)), ['a60']);
      expect(keys(order.merge(sources, stalled: {1})), ['a60', 'b55', 'a10']);
      expect(order.historySource(sources, stalled: {1}), isNull);
    });

    test('equal timestamps at the bound wait for the slower room', () {
      final sources = [
        src([('a20', 20), ('a10', 10)], history: true),
        src([('b30', 30), ('b10', 10)], history: true),
      ];
      // Both rooms reach back to 10, and either may hold more at 10.
      expect(keys(order.merge(sources)), ['b30', 'a20']);
      // Room A loads further back; B still sets the bound at 10.
      final next = [
        src([('a20', 20), ('a10', 10), ('a5', 5)], history: true),
        sources[1],
      ];
      expect(keys(order.merge(next)), ['b30', 'a20']);
      expect(order.historySource(next), 1);
      // B is exhausted: everything down to A's bound shows.
      final last = [
        next[0],
        src([('b30', 30), ('b10', 10)]),
      ];
      expect(keys(order.merge(last)), ['b30', 'a20', 'a10', 'b10']);
    });

    test('upper bound around a jumped-to message', () {
      // Room A was opened around an old message and has not caught up;
      // room B is live. B's events newer than A's newest loaded one wait.
      final sources = [
        src([('a40', 40), ('a30', 30), ('a20', 20)], future: true),
        src([('b90', 90), ('b35', 35), ('b25', 25)]),
      ];
      expect(order.horizon(sources).upper, 40);
      expect(keys(order.merge(sources)), ['b35', 'a30', 'b25', 'a20']);
      expect(order.futureSource(sources), 0);
    });
  });

  group('which room loads history', () {
    test('the room whose oldest loaded event is newest', () {
      final sources = [
        src([('a60', 60), ('a50', 50)], history: true),
        src([('b55', 55), ('b20', 20)], history: true),
        src([('c70', 70), ('c40', 40)], history: true),
      ];
      expect(order.historySource(sources), 0);
    });

    test('none when no room can load', () {
      expect(
        order.historySource([
          src([('a1', 1)]),
        ]),
        isNull,
      );
    });

    test('loading from the chosen room always reveals more', () {
      // Repeatedly load from the chosen source and check the shown list
      // only grows at its old end, which is what "no gap" means.
      final full = [
        [for (var t = 100; t > 0; t -= 7) ('a$t', t)],
        [for (var t = 99; t > 0; t -= 3) ('b$t', t)],
        [for (var t = 98; t > 0; t -= 11) ('c$t', t)],
      ];
      final loaded = [3, 3, 3];
      var shown = <Ev>[];
      for (var step = 0; step < 100; step++) {
        final sources = [
          for (var i = 0; i < full.length; i++)
            src(
              full[i].take(loaded[i]).toList(),
              history: loaded[i] < full[i].length,
            ),
        ];
        final merged = order.merge(sources);
        expect(
          keys(merged.take(shown.length).toList()),
          keys(shown),
          reason: 'step $step changed already shown events',
        );
        shown = merged;
        final next = order.historySource(sources);
        if (next == null) break;
        loaded[next] += 2;
      }
      // Keys start with the room's letter, so on equal times they sort in
      // room order, as the merge does.
      final everything = [for (final f in full) ...f]
        ..sort((a, b) {
          final byTime = b.$2.compareTo(a.$2);
          return byTime != 0 ? byTime : a.$1.compareTo(b.$1);
        });
      expect(keys(shown), keys(everything));
    });
  });

  group('diff', () {
    test('a new message on top is one insert at 0', () {
      final before = [('a2', 20), ('b1', 10)];
      final after = [('b3', 30), ('a2', 20), ('b1', 10)];
      final changes = order.diff(before, after);
      expect(changes, [const MergeInsert(0)]);
      expect(apply(before, after, changes), after);
    });

    test('a message from another room lands in the middle', () {
      final before = [('a3', 30), ('a1', 10)];
      final after = [('a3', 30), ('b2', 20), ('a1', 10)];
      expect(order.diff(before, after), [const MergeInsert(1)]);
    });

    test('a removal maps to its merged index', () {
      final before = [('a3', 30), ('b2', 20), ('a1', 10)];
      final after = [('a3', 30), ('a1', 10)];
      expect(order.diff(before, after), [const MergeRemove(1)]);
    });

    test('history revealed at the old end appends', () {
      final before = [('a3', 30), ('b2', 20)];
      final after = [('a3', 30), ('b2', 20), ('a1', 10), ('b0', 5)];
      expect(order.diff(before, after), [
        const MergeInsert(2),
        const MergeInsert(3),
      ]);
    });

    test('a changed event keeps its index', () {
      // By default an event is unchanged only when it is the same object,
      // as the SDK replaces an event object when it changes.
      const byIdentity = MergedOrder<(String, int, String)>(
        timestamp: _ts3,
        key: _key3,
      );
      final before = [('a3', 30, 'hello'), ('b2', 20, 'hi')];
      final after = [before[0], ('b2', 20, 'hi, edited')];
      expect(byIdentity.diff(before, after), [const MergeUpdate(1)]);
      expect(byIdentity.diff(after, after), isEmpty);
    });

    test('a moved event is removed and inserted', () {
      final before = [('x', 50), ('a3', 30), ('b2', 20)];
      final after = [('a3', 30), ('x', 25), ('b2', 20)];
      final changes = order.diff(before, after);
      expect(keys(apply(before, after, changes)), keys(after));
      expect(changes.whereType<MergeInsert>(), isNotEmpty);
    });

    test('mixed changes apply to the right list', () {
      final before = [('a5', 50), ('b4', 40), ('a3', 30), ('b1', 10)];
      final after = [
        ('b6', 60),
        ('a5', 50),
        ('a3', 30),
        ('c2', 20),
        ('b1', 10),
      ];
      final changes = order.diff(before, after);
      expect(keys(apply(before, after, changes)), keys(after));
    });
  });
}
