// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:matrix/matrix.dart';
// The SDK does not export the chunk type, which a stored timeline is rebuilt
// with.
// ignore: implementation_imports
import 'package:matrix/src/models/timeline_chunk.dart';

/// Keeps the last loaded archive in the client's database so the archive page
/// can show it at once.
///
/// The homeserver only lists left rooms in a full `/sync` with
/// `include_leave`, which makes it build every joined room as well. On an
/// account with about 800 joined rooms that request takes Synapse 30 seconds
/// and returns 15 MB, however few rooms are archived. The page shows the
/// stored rooms while that request runs and swaps in its result.
///
/// The rooms are stored with [Client.database]'s custom cache, so they live in
/// the same encrypted database as the timelines and are deleted with it on
/// logout.
class ArchiveCache {
  static const cacheKey = 'chat.seam.archive';

  /// Requests in flight, by client, so reopening the page while the server is
  /// still working does not start a second full sync.
  static final Map<Client, Future<List<ArchivedRoom>>> _loading = {};

  /// The archive as stored by the last [refresh], or null when there is none.
  static Future<List<ArchivedRoom>?> read(Client client) async {
    try {
      final cached = await client.database.getCustomCacheObject(cacheKey);
      final rooms = cached?.content['rooms'];
      if (rooms is! List) return null;
      return rooms
          .whereType<Map<String, Object?>>()
          .map((json) => _fromJson(client, json))
          .toList();
    } catch (e, s) {
      Logs().w('Could not read the stored archive', e, s);
      return null;
    }
  }

  /// Loads the archive from the server and stores it.
  static Future<List<ArchivedRoom>> refresh(Client client) =>
      _loading[client] ??= () async {
        try {
          final archive = await client.loadArchiveWithTimeline();
          await store(client, archive);
          return archive;
        } finally {
          _loading.remove(client);
        }
      }();

  /// Stores [archive], replacing what was stored before.
  static Future<void> store(Client client, List<ArchivedRoom> archive) => client
      .database
      .cacheCustomObject(cacheKey, {'rooms': archive.map(_toJson).toList()});

  static Map<String, Object?> _toJson(ArchivedRoom archived) {
    final room = archived.room;
    return {
      'room_id': room.id,
      'prev_batch': archived.timeline.chunk.prevBatch,
      'account_data': room.roomAccountData.values
          .map((event) => event.toJson())
          .toList(),
      'state': [
        for (final byKey in room.states.values)
          for (final state in byKey.values) state.toJson(),
      ],
      // Newest first, as the timeline holds them.
      'timeline': archived.timeline.events.map((e) => e.toJson()).toList(),
    };
  }

  static ArchivedRoom _fromJson(Client client, Map<String, Object?> json) {
    final prevBatch = json['prev_batch'] as String? ?? '';
    final room = Room(
      id: json['room_id'] as String,
      prev_batch: prevBatch,
      membership: Membership.leave,
      client: client,
      roomAccountData: {
        for (final raw
            in (json['account_data'] as List? ?? [])
                .whereType<Map<String, Object?>>())
          raw['type'] as String: BasicEvent.fromJson(raw),
      },
    );
    for (final raw
        in (json['state'] as List? ?? []).whereType<Map<String, Object?>>()) {
      room.setState(Event.fromJson(raw, room), notifyRoomState: false);
    }
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(
        events: (json['timeline'] as List? ?? [])
            .whereType<Map<String, Object?>>()
            .map((raw) => Event.fromJson(raw, room))
            .toList(),
        prevBatch: prevBatch,
      ),
    );
    timeline.events.forEach(timeline.addAggregatedEvent);
    room.lastEvent = timeline.events.firstWhereOrNull(
      (event) => client.roomPreviewLastEvents.contains(event.type),
    );
    return ArchivedRoom(room: room, timeline: timeline);
  }
}
