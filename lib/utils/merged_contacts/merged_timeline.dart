// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
// The SDK does not export the chunk type, which implementing Timeline needs.
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';

import 'merged_order.dart';

/// The timelines of a merged contact's rooms shown as one.
///
/// It is a [Timeline] to everything that reads one (the event list, message
/// widgets, reply and edit lookups), so the chat screen shows a merged
/// contact with the same code as a single room. Each event keeps its own
/// room, so acting on it reaches the right network. Which events are shown
/// is decided by [MergedOrder]: only those every room has loaded up to, so
/// the merged list never has a gap.
class MergedTimeline implements Timeline {
  /// The rooms' own timelines, in the contact's room order.
  final List<Timeline> children;

  @override
  final void Function()? onUpdate;
  @override
  final void Function(int index)? onChange;
  @override
  final void Function(int index)? onInsert;
  @override
  final void Function(int index)? onRemove;
  @override
  final void Function()? onNewEvent;

  static final MergedOrder<Event> _order = MergedOrder<Event>(
    timestamp: (event) => event.originServerTs.millisecondsSinceEpoch,
    // A message keeps its transaction ID from sending to sent, while its
    // event ID changes.
    key: (event) => event.transactionId ?? event.eventId,
  );

  /// Rooms whose history requests stopped bringing anything new while they
  /// still claim to have more. They no longer hold the window back, so one
  /// broken room cannot hide the others' history forever.
  final Set<int> _stalled = {};
  final List<int> _emptyRequests;

  /// Consecutive history requests that brought nothing before a room counts
  /// as stalled.
  static const int maxEmptyHistoryRequests = 3;

  List<Event> _events = const [];
  Map<String, Map<String, Set<Event>>> _aggregated = const {};

  MergedTimeline._(
    this.children, {
    this.onUpdate,
    this.onChange,
    this.onInsert,
    this.onRemove,
    this.onNewEvent,
  }) : _emptyRequests = List.filled(children.length, 0);

  /// Opens the timeline of every room in [rooms]. With [eventContextId] the
  /// timelines open around that message: its room ([eventContextRoomId],
  /// else whichever room has it) around the message itself, and the others
  /// around the message nearest its time, so the window around it has no
  /// gaps either.
  static Future<MergedTimeline> open(
    List<Room> rooms, {
    void Function()? onUpdate,
    void Function(int index)? onInsert,
    void Function(int index)? onChange,
    void Function(int index)? onRemove,
    void Function()? onNewEvent,
    String? eventContextId,
    String? eventContextRoomId,
  }) async {
    MergedTimeline? merged;
    // The children report to the merged timeline, which recomputes its list
    // and reports the merged indexes onwards. Updates while the timelines
    // are still opening are covered by the first computation below.
    void childUpdate() => merged?.childChanged();

    Future<Timeline> openRoom(Room room, String? contextId) =>
        room.getTimeline(onUpdate: childUpdate, eventContextId: contextId);

    final List<Timeline> children;
    if (eventContextId == null) {
      children = await Future.wait(rooms.map((room) => openRoom(room, null)));
    } else {
      children = await _openAround(
        rooms,
        eventContextId,
        eventContextRoomId,
        openRoom,
      );
    }
    final timeline = MergedTimeline._(
      children,
      onUpdate: onUpdate,
      onInsert: onInsert,
      onChange: onChange,
      onRemove: onRemove,
      onNewEvent: onNewEvent,
    );
    timeline._recompute();
    return merged = timeline;
  }

  static Future<List<Timeline>> _openAround(
    List<Room> rooms,
    String eventId,
    String? roomId,
    Future<Timeline> Function(Room room, String? contextId) openRoom,
  ) async {
    // The room holding the message: the given one, else the first that can
    // load its context.
    final ordered = [
      ...rooms.where((room) => room.id == roomId),
      ...rooms.where((room) => room.id != roomId),
    ];
    Timeline? context;
    for (final room in ordered) {
      try {
        final timeline = await openRoom(room, eventId);
        if (timeline.events.any((event) => event.eventId == eventId)) {
          context = timeline;
          break;
        }
        timeline.cancelSubscriptions();
      } catch (e, s) {
        Logs().v('Message $eventId is not in ${room.id}', e, s);
      }
    }
    if (context == null) {
      throw Exception('Message $eventId is in none of the merged rooms');
    }
    final at = context.events
        .firstWhere((event) => event.eventId == eventId)
        .originServerTs
        .millisecondsSinceEpoch;
    final children = <Timeline>[];
    for (final room in rooms) {
      if (room == context.room) {
        children.add(context);
        continue;
      }
      // The other rooms open around their message nearest that time, as
      // fragments too. A room with nothing that old opens live and is
      // ordered by the window like any other.
      String? nearest;
      try {
        nearest = (await room.client.getEventByTimestamp(
          room.id,
          at,
          Direction.b,
        )).eventId;
      } catch (e) {
        Logs().v('No message before $at in ${room.id}', e);
      }
      try {
        children.add(await openRoom(room, nearest));
      } catch (e, s) {
        Logs().w('Unable to open ${room.id} around $nearest', e, s);
        children.add(await openRoom(room, null));
      }
    }
    return children;
  }

  List<MergeSource<Event>> get _sources => [
    for (final child in children)
      MergeSource(
        child.events,
        canRequestHistory: child.canRequestHistory,
        canRequestFuture: child.canRequestFuture,
      ),
  ];

  void _recompute() {
    _events = _order.merge(_sources, stalled: _stalled);
    _aggregated = {for (final child in children) ...child.aggregatedEvents};
  }

  /// A merged timeline over [children] that are already open. Their
  /// `onUpdate` must call [childChanged]; [open] wires that up.
  @visibleForTesting
  factory MergedTimeline.ofChildren(
    List<Timeline> children, {
    void Function()? onUpdate,
    void Function(int index)? onInsert,
    void Function(int index)? onChange,
    void Function(int index)? onRemove,
  }) => MergedTimeline._(
    children,
    onUpdate: onUpdate,
    onInsert: onInsert,
    onChange: onChange,
    onRemove: onRemove,
  ).._recompute();

  /// Recomputes the shown list after a child changed and reports the
  /// changes by merged index.
  void childChanged() {
    final before = _events;
    _recompute();
    final changes = _order.diff(before, _events);
    for (final change in changes) {
      switch (change) {
        case MergeRemove(:final index):
          onRemove?.call(index);
        case MergeInsert(:final index):
          onInsert?.call(index);
        case MergeUpdate(:final index):
          onChange?.call(index);
      }
    }
    if (changes.any((change) => change is MergeInsert && change.index == 0)) {
      onNewEvent?.call();
    }
    onUpdate?.call();
  }

  /// The child timeline [event] belongs to.
  Timeline? childOf(Event event) =>
      children.firstWhereOrNull((child) => child.room.id == event.roomId);

  /// The rooms' own timelines with the newest event each shows, for read
  /// receipts: each room is marked read up to its own newest shown event.
  Map<Timeline, Event> get newestShownPerRoom {
    final result = <Timeline, Event>{};
    for (final event in _events) {
      if (!event.status.isSynced) continue;
      final child = childOf(event);
      if (child != null && !result.containsKey(child)) result[child] = event;
    }
    return result;
  }

  /// The event the "new messages" line is drawn at: the newest shown event
  /// older than the oldest unread one across the rooms. [fullyRead] maps
  /// each room with unread messages to its read marker event.
  String? readMarkerEventId(Map<String, String> fullyRead) {
    Event? oldestUnread;
    for (final child in children) {
      final marker = fullyRead[child.room.id];
      if (marker == null) continue;
      final index = child.events.indexWhere((e) => e.eventId == marker);
      if (index <= 0) continue;
      final firstUnread = child.events[index - 1];
      if (oldestUnread == null ||
          firstUnread.originServerTs.isBefore(oldestUnread.originServerTs)) {
        oldestUnread = firstUnread;
      }
    }
    if (oldestUnread == null) return null;
    final shownIndex = _events.indexOf(oldestUnread);
    if (shownIndex < 0 || shownIndex + 1 >= _events.length) return null;
    return _events[shownIndex + 1].eventId;
  }

  // Timeline

  /// The first room, which the few callers that want "the room" of a
  /// timeline get. Everything that acts on a message uses the message's own
  /// room instead.
  @override
  Room get room => children.first.room;

  @override
  List<Event> get events => _events;

  @override
  Map<String, Map<String, Set<Event>>> get aggregatedEvents => _aggregated;

  @override
  bool get canRequestHistory =>
      _order.historySource(_sources, stalled: _stalled) != null;

  @override
  bool get canRequestFuture => children.any((child) => child.canRequestFuture);

  @override
  bool get isRequestingHistory =>
      children.any((child) => child.isRequestingHistory);

  @override
  set isRequestingHistory(bool value) {}

  @override
  bool get isRequestingFuture =>
      children.any((child) => child.isRequestingFuture);

  @override
  set isRequestingFuture(bool value) {}

  @override
  bool get allowNewEvent => children.every((child) => child.allowNewEvent);

  @override
  set allowNewEvent(bool value) {}

  @override
  bool get isFragmentedTimeline =>
      children.any((child) => child.isFragmentedTimeline);

  @override
  set isFragmentedTimeline(bool value) {}

  bool _requestingHistory = false;

  /// Loads older events from the room holding the window's lower bound.
  /// One request may reveal nothing new (that room's older events can all
  /// be older than another room's bound), so callers ask again while
  /// [canRequestHistory], as the event list does when scrolled to the top.
  @override
  Future<void> requestHistory({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  }) async {
    if (_requestingHistory) return;
    final index = _order.historySource(_sources, stalled: _stalled);
    if (index == null) return;
    _requestingHistory = true;
    final child = children[index];
    final before = child.events.length;
    try {
      await child.requestHistory(historyCount: historyCount, filter: filter);
    } finally {
      _requestingHistory = false;
    }
    if (child.events.length > before) {
      _emptyRequests[index] = 0;
    } else if (child.canRequestHistory &&
        ++_emptyRequests[index] >= maxEmptyHistoryRequests) {
      Logs().w(
        '${child.room.id} keeps returning no history, not waiting on it',
      );
      _stalled.add(index);
    }
    childChanged();
  }

  @override
  Future<void> requestFuture({
    int historyCount = Room.defaultHistoryCount,
    StateFilter? filter,
  }) async {
    final index = _order.futureSource(_sources);
    if (index == null) return;
    await children[index].requestFuture(
      historyCount: historyCount,
      filter: filter,
    );
    childChanged();
  }

  @override
  Future<Event?> getEventById(String id) async {
    for (final event in _events) {
      if (event.eventId == id) return event;
    }
    for (final child in children) {
      final event = child.events.firstWhereOrNull((e) => e.eventId == id);
      if (event != null) return event;
    }
    // Event IDs are unique across rooms; only the room holding it finds it.
    for (final child in children) {
      try {
        final event = await child.getEventById(id);
        if (event != null) return event;
      } catch (e) {
        Logs().v('$id not in ${child.room.id}', e);
      }
    }
    return null;
  }

  @override
  void cancelSubscriptions() {
    for (final child in children) {
      child.cancelSubscriptions();
    }
  }

  @override
  void requestKeys({
    bool tryOnlineBackup = true,
    bool onlineKeyBackupOnly = true,
  }) {
    for (final child in children) {
      child.requestKeys(
        tryOnlineBackup: tryOnlineBackup,
        onlineKeyBackupOnly: onlineKeyBackupOnly,
      );
    }
  }

  /// Marks each room read up to [eventId] when given (in that event's own
  /// room only), else every room up to its own newest shown event.
  @override
  Future<void> setReadMarker({String? eventId, bool? public}) async {
    if (eventId != null) {
      final event = _events.firstWhereOrNull((e) => e.eventId == eventId);
      final child = event == null ? null : childOf(event);
      await child?.setReadMarker(eventId: eventId, public: public);
      return;
    }
    await Future.wait(
      newestShownPerRoom.entries.map(
        (entry) => entry.key.setReadMarker(
          eventId: entry.value.eventId,
          public: public,
        ),
      ),
    );
  }

  @override
  void addAggregatedEvent(Event event) =>
      childOf(event)?.addAggregatedEvent(event);

  @override
  void removeAggregatedEvent(Event event) =>
      childOf(event)?.removeAggregatedEvent(event);

  @override
  Future<void> fetchAggregatedEvents(
    String eventId,
    String relType, {
    String? eventType,
  }) async {
    final event = _events.firstWhereOrNull((e) => e.eventId == eventId);
    final child = event == null ? null : childOf(event);
    if (child == null) return;
    await child.fetchAggregatedEvents(eventId, relType, eventType: eventType);
    childChanged();
  }

  // Room-specific members the chat screen does not use with a merged
  // timeline; they act on the first room, like [room].

  @override
  Future<int> getRoomEvents({
    int historyCount = Room.defaultHistoryCount,
    direction = Direction.b,
    StateFilter? filter,
  }) => children.first.getRoomEvents(
    historyCount: historyCount,
    direction: direction,
    filter: filter,
  );

  @override
  Stream<List<Event>> searchEvent({
    String? searchTerm,
    int requestHistoryCount = 100,
    int maxHistoryRequests = 10,
    String? sinceEventId,
    int? limit,
    bool Function(Event)? searchFunc,
  }) =>
      // ignore: deprecated_member_use
      children.first.searchEvent(
        searchTerm: searchTerm,
        requestHistoryCount: requestHistoryCount,
        maxHistoryRequests: maxHistoryRequests,
        sinceEventId: sinceEventId,
        limit: limit,
        searchFunc: searchFunc,
      );

  @override
  Stream<(List<Event>, String?)> startSearch({
    String? searchTerm,
    int requestHistoryCount = 100,
    int maxHistoryRequests = 10,
    String? prevBatch,
    String? sinceEventId,
    int? limit,
    bool Function(Event)? searchFunc,
  }) =>
      // ignore: deprecated_member_use
      children.first.startSearch(
        searchTerm: searchTerm,
        requestHistoryCount: requestHistoryCount,
        maxHistoryRequests: maxHistoryRequests,
        prevBatch: prevBatch,
        limit: limit,
        searchFunc: searchFunc,
      );

  /// A chunk holding the shown events. Only read: the merged list is built
  /// from the children's chunks.
  @override
  TimelineChunk get chunk => TimelineChunk(events: _events);

  @override
  set chunk(TimelineChunk value) =>
      throw UnsupportedError('A merged timeline has no chunk of its own');

  // The children hold the stream subscriptions.

  @override
  StreamSubscription<Event>? get timelineSub => null;
  @override
  set timelineSub(StreamSubscription<Event>? value) {}
  @override
  StreamSubscription<Event>? get historySub => null;
  @override
  set historySub(StreamSubscription<Event>? value) {}
  @override
  StreamSubscription<SyncUpdate>? get roomSub => null;
  @override
  set roomSub(StreamSubscription<SyncUpdate>? value) {}
  @override
  StreamSubscription<String>? get sessionIdReceivedSub => null;
  @override
  set sessionIdReceivedSub(StreamSubscription<String>? value) {}
  @override
  StreamSubscription<String>? get cancelSendEventSub => null;
  @override
  set cancelSendEventSub(StreamSubscription<String>? value) {}
}
