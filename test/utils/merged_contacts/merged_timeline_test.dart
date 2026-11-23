// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:fluffychat/utils/merged_contacts/merged_timeline.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';

import 'fake_rooms.dart';

Event message(Room room, String id, int minute, {String? sender}) => Event(
  content: {'msgtype': 'm.text', 'body': id},
  type: EventTypes.Message,
  eventId: '\$$id',
  senderId: sender ?? '@other:x',
  originServerTs: DateTime(2026, 1, 1, 12, minute),
  room: room,
);

Event reaction(Room room, String id, String to, int minute) => Event(
  content: {
    'm.relates_to': {
      'rel_type': 'm.annotation',
      'event_id': '\$$to',
      'key': '👍',
    },
  },
  type: EventTypes.Reaction,
  eventId: '\$$id',
  senderId: '@other:x',
  originServerTs: DateTime(2026, 1, 1, 12, minute),
  room: room,
);

void main() {
  late Client client;
  late Room a, b;
  late Timeline ta, tb;
  late MergedTimeline merged;
  final inserts = <int>[];
  final removes = <int>[];
  var updates = 0;

  setUp(() async {
    client = await fakeMergedClient();
    a = addDirectChat(client, id: '!a:x', partner: '@a:x', name: 'A');
    b = addDirectChat(client, id: '!b:x', partner: '@b:x', name: 'B');
    inserts.clear();
    removes.clear();
    updates = 0;
    MergedTimeline? m;
    // Both children can still load history, so the merged window starts
    // above the newer of their oldest events (B's, at 20).
    ta = Timeline(
      room: a,
      chunk: TimelineChunk(
        events: [message(a, 'a30', 30), message(a, 'a10', 10)],
        nextBatch: '',
        prevBatch: '',
      ),
      onUpdate: () => m?.childChanged(),
    );
    tb = Timeline(
      room: b,
      chunk: TimelineChunk(
        events: [reaction(b, 'r', 'a30', 31), message(b, 'b20', 20)],
      ),
      onUpdate: () => m?.childChanged(),
    );
    m = merged = MergedTimeline.ofChildren(
      [ta, tb],
      onInsert: inserts.add,
      onRemove: removes.add,
      onUpdate: () => updates++,
    );
  });

  tearDown(() => merged.cancelSubscriptions());

  List<String> shown() => [for (final e in merged.events) e.eventId];

  test('interleaves the rooms by time and keeps each event\'s room', () {
    // Room A can still load history down from 10, room B from 20: B's
    // reaction at 31 and A's 30 show, events at or below 20 wait.
    expect(merged.canRequestHistory, isTrue);
    expect(shown(), [r'$r', r'$a30']);
    expect(merged.events[1].room, a);
    expect(merged.events[0].room, b);
  });

  test('reactions from any room aggregate onto their message', () {
    final target = merged.events.firstWhere((e) => e.eventId == r'$a30');
    final reactions = target.aggregatedEvents(
      merged,
      RelationshipTypes.reaction,
    );
    expect(reactions.map((e) => e.eventId), [r'$r']);
  });

  test('a new message in one room maps to its merged index', () {
    tb.events.insert(0, message(b, 'b40', 40));
    tb.onUpdate!();
    expect(inserts, [0]);
    expect(shown().first, r'$b40');
    expect(updates, 1);
  });

  test('a removed message maps to its merged index', () {
    tb.events.removeAt(0);
    tb.onUpdate!();
    expect(removes, [0]);
    expect(shown(), [r'$a30']);
  });

  test('finds events and their rooms', () async {
    expect((await merged.getEventById(r'$b20'))?.room, b);
    expect(merged.childOf(merged.events.first), tb);
  });

  test('read markers: each room up to its own newest shown event', () {
    final newest = merged.newestShownPerRoom;
    expect(newest[ta]?.eventId, r'$a30');
    expect(newest[tb]?.eventId, r'$r');
  });

  test('the new messages line sits above the oldest unread message', () {
    tb.events.insert(0, message(b, 'b40', 40));
    tb.onUpdate!();
    // A is read up to a10, so a30 is its first unread message; B is read
    // up to r, so b40 is. The oldest unread is a30, but nothing shown is
    // older than it yet, so there is no line.
    expect(merged.readMarkerEventId({'!a:x': r'$a10', '!b:x': r'$r'}), isNull);
    // With A read, B's b40 is the oldest unread: the line goes on the
    // message shown just below it.
    expect(merged.readMarkerEventId({'!b:x': r'$r'}), r'$r');
  });
}
