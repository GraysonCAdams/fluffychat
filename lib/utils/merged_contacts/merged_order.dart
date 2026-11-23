// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// What [MergedOrder] needs to know about one room's loaded timeline.
class MergeSource<E> {
  /// The loaded events, newest first.
  final List<E> events;

  /// Whether older events can still be loaded.
  final bool canRequestHistory;

  /// Whether newer events can still be loaded: the timeline was opened
  /// around an older message and has not caught up with the present.
  final bool canRequestFuture;

  const MergeSource(
    this.events, {
    this.canRequestHistory = false,
    this.canRequestFuture = false,
  });
}

/// The time window in which every room has loaded all of its events, so
/// showing the merged events inside it leaves no gaps. Events at or below
/// [lower] or at or above [upper] stay hidden until the rooms that set the
/// bound load further.
class MergeHorizon {
  /// Milliseconds since epoch, or null for no lower bound.
  final int? lower;

  /// Milliseconds since epoch, or null for no upper bound.
  final int? upper;

  /// True when some room has loaded nothing yet but can load: nothing can
  /// be shown safely until it does.
  final bool blocked;

  const MergeHorizon({this.lower, this.upper, this.blocked = false});

  bool contains(int timestamp) =>
      !blocked &&
      (lower == null || timestamp > lower!) &&
      (upper == null || timestamp < upper!);

  @override
  String toString() => 'MergeHorizon($lower, $upper, blocked: $blocked)';
}

/// One change between two merged lists, for timeline callbacks.
sealed class MergeChange {
  final int index;

  const MergeChange(this.index);
}

class MergeInsert extends MergeChange {
  const MergeInsert(super.index);

  @override
  bool operator ==(Object other) =>
      other is MergeInsert && other.index == index;

  @override
  int get hashCode => index.hashCode;

  @override
  String toString() => 'insert($index)';
}

class MergeRemove extends MergeChange {
  const MergeRemove(super.index);

  @override
  bool operator ==(Object other) =>
      other is MergeRemove && other.index == index;

  @override
  int get hashCode => -index.hashCode - 1;

  @override
  String toString() => 'remove($index)';
}

class MergeUpdate extends MergeChange {
  const MergeUpdate(super.index);

  @override
  bool operator ==(Object other) =>
      other is MergeUpdate && other.index == index;

  @override
  int get hashCode => index.hashCode ^ 0x5bd1e995;

  @override
  String toString() => 'change($index)';
}

/// Merges several rooms' event lists into one timeline, newest first,
/// without ever showing a gap.
///
/// The rooms load their history independently, so at any moment one room
/// may have loaded a month back and another only an hour. Showing every
/// loaded event would put the month-old events of the first room right
/// below the hour-old events of the second, and the second room's missing
/// month would pop in between later. So only events inside the
/// [MergeHorizon] are shown: newer than the newest "oldest loaded event" of
/// the rooms that can still load history, and older than the oldest
/// "newest loaded event" of the rooms opened around an older message.
/// Loading history from the room that sets the bound ([historySource])
/// widens the window.
///
/// Generic over the event type so it is unit tested with plain values; the
/// app uses it with SDK events in MergedTimeline.
class MergedOrder<E> {
  final int Function(E event) timestamp;

  /// A key that stays the same while an event goes from sending to sent.
  final String Function(E event) key;

  /// Whether two versions of an event with the same key show the same
  /// thing. Identity by default: the SDK replaces an event's object when
  /// the event changes (decrypted, edited, sent).
  final bool Function(E a, E b) same;

  const MergedOrder({
    required this.timestamp,
    required this.key,
    this.same = identical,
  });

  MergeHorizon horizon(
    List<MergeSource<E>> sources, {
    Set<int> stalled = const {},
  }) {
    int? lower;
    int? upper;
    var blocked = false;
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (source.canRequestHistory && !stalled.contains(i)) {
        if (source.events.isEmpty) {
          blocked = true;
        } else {
          final oldest = _oldest(source.events);
          if (lower == null || oldest > lower) lower = oldest;
        }
      }
      if (source.canRequestFuture) {
        if (source.events.isEmpty) {
          blocked = true;
        } else {
          final newest = _newest(source.events);
          if (upper == null || newest < upper) upper = newest;
        }
      }
    }
    return MergeHorizon(lower: lower, upper: upper, blocked: blocked);
  }

  int _oldest(List<E> events) =>
      events.map(timestamp).reduce((a, b) => a < b ? a : b);

  int _newest(List<E> events) =>
      events.map(timestamp).reduce((a, b) => a > b ? a : b);

  /// The shown events of all [sources], newest first. Equal timestamps are
  /// ordered by the sources' order, then by key, so the order is stable.
  List<E> merge(List<MergeSource<E>> sources, {Set<int> stalled = const {}}) {
    final window = horizon(sources, stalled: stalled);
    if (window.blocked) return [];
    final entries = <(E, int)>[
      for (var i = 0; i < sources.length; i++)
        for (final event in sources[i].events)
          if (window.contains(timestamp(event))) (event, i),
    ];
    entries.sort((a, b) {
      final byTime = timestamp(b.$1).compareTo(timestamp(a.$1));
      if (byTime != 0) return byTime;
      final bySource = a.$2.compareTo(b.$2);
      if (bySource != 0) return bySource;
      return key(a.$1).compareTo(key(b.$1));
    });
    return [for (final entry in entries) entry.$1];
  }

  /// The source to load older events from: the one whose oldest loaded
  /// event is newest, since it holds the window's lower bound. A source
  /// that has loaded nothing goes first. Null when none can load.
  int? historySource(
    List<MergeSource<E>> sources, {
    Set<int> stalled = const {},
  }) {
    int? best;
    int? bestOldest;
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (!source.canRequestHistory || stalled.contains(i)) continue;
      if (source.events.isEmpty) return i;
      final oldest = _oldest(source.events);
      if (bestOldest == null || oldest > bestOldest) {
        best = i;
        bestOldest = oldest;
      }
    }
    return best;
  }

  /// The source to load newer events from: the one whose newest loaded
  /// event is oldest, since it holds the window's upper bound.
  int? futureSource(List<MergeSource<E>> sources) {
    int? best;
    int? bestNewest;
    for (var i = 0; i < sources.length; i++) {
      final source = sources[i];
      if (!source.canRequestFuture) continue;
      if (source.events.isEmpty) return i;
      final newest = _newest(source.events);
      if (bestNewest == null || newest < bestNewest) {
        best = i;
        bestNewest = newest;
      }
    }
    return best;
  }

  /// The changes that turn [before] into [after], both as returned by
  /// [merge]: removals first, from the last index down, so each index is
  /// valid when applied in order; then insertions in ascending order of
  /// their final index; then updates of events that kept their place but
  /// changed (by identity), at their final index.
  ///
  /// An event whose key stayed but whose position among the others changed
  /// (its timestamp moved when the server confirmed it) is removed and
  /// inserted again.
  List<MergeChange> diff(List<E> before, List<E> after) {
    final afterKeys = <String, int>{
      for (var i = 0; i < after.length; i++) key(after[i]): i,
    };
    // Events present in both lists stay in place as long as they keep their
    // order. They are picked greedily in the order of [before]: not always
    // the fewest changes when an event moved, but always a correct sequence,
    // and minimal in the common case of events only arriving or leaving.
    final kept = <String>{};
    var lastAfterIndex = -1;
    for (final event in before) {
      final index = afterKeys[key(event)];
      if (index == null) continue;
      if (index > lastAfterIndex) {
        kept.add(key(event));
        lastAfterIndex = index;
      }
    }
    final changes = <MergeChange>[];
    for (var i = before.length - 1; i >= 0; i--) {
      if (!kept.contains(key(before[i]))) changes.add(MergeRemove(i));
    }
    final beforeByKey = {for (final event in before) key(event): event};
    final updates = <MergeChange>[];
    for (var i = 0; i < after.length; i++) {
      final k = key(after[i]);
      if (!kept.contains(k)) {
        changes.add(MergeInsert(i));
      } else if (!same(beforeByKey[k] as E, after[i])) {
        updates.add(MergeUpdate(i));
      }
    }
    return [...changes, ...updates];
  }
}
