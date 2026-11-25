// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:matrix/matrix.dart';

/// Keeps a chat's preview, and so its place in the chat list, when a sync
/// brings it nothing to preview.
///
/// On a limited sync the SDK drops a room's last event. When the new
/// timeline slice holds no previewable event, as when a bridge only posts
/// bookkeeping state such as `com.beeper.room_features`, the SDK puts a
/// placeholder of type [EventTypes.refreshingLastEvent] in its place: sent
/// by the user ("You: Loading… Please wait." in the chat list) and dated by
/// the slice's first event, or by now, which moves the chat to the top. It
/// then asks the server for the newest previewable event. Until that
/// answers, or for good when it fails, the placeholder stays, and each later
/// sync of the room dates it anew.
///
/// This puts back the room's last real event, remembered before each sync,
/// and stores it, so the placeholder is never shown and the room keeps its
/// place. A reaction that was the last event and is then taken back is
/// replaced the same way, by the last event before it that is not a
/// reaction. The SDK's own refresh still replaces it when the server knows a
/// newer event. After the first sync, previews of either kind stored
/// earlier are fetched again from the server.
class LastEventKeeper {
  final Client client;

  /// The last real event of each room, as of before the running sync.
  final Map<String, Event> _kept = {};

  /// The last real event of each room that is not a reaction, to fall back
  /// on when a reaction that became the last event is taken back.
  final Map<String, Event> _keptMessage = {};

  LastEventKeeper._(this.client) {
    client.onSyncStatus.stream.listen((update) {
      // Sent before each sync request, well before its response is handled.
      if (update.status == SyncStatus.waitingForResponse) _rememberAll();
    });
    client.onSync.stream.listen(_afterSync);
  }

  /// Rooms whose stored last event is a placeholder or a removed reaction,
  /// saved before this keeper existed or while the app was closed, get the
  /// newest previewable event from the server that is neither.
  Future<void> _repairStored() async {
    final types = client.roomPreviewLastEvents
        .where((type) => type != EventTypes.Reaction)
        .toList();
    final repaired = <String>[];
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      final last = room.lastEvent;
      if (!_isPlaceholder(last) && !_isRemovedReaction(last)) continue;
      try {
        final result = await client.getRoomEvents(
          room.id,
          Direction.b,
          limit: 1,
          filter: jsonEncode(StateFilter(types: types).toJson()),
        );
        final found = result.chunk.firstOrNull;
        if (found == null) continue;
        var event = Event.fromMatrixEvent(
          found,
          room,
          status: EventStatus.synced,
        );
        if (event.type == EventTypes.Encrypted) {
          event = await client.encryption?.decryptRoomEvent(event) ?? event;
        }
        room.lastEvent = event;
        repaired.add(room.id);
      } catch (e, s) {
        Logs().w('Unable to repair the preview of ${room.id}', e, s);
      }
    }
    if (repaired.isNotEmpty) await _store(repaired);
  }

  static final Expando<LastEventKeeper> _keepers = Expando();

  /// Starts keeping the last events of [client]'s rooms.
  static LastEventKeeper attach(Client client) =>
      _keepers[client] ??= LastEventKeeper._(client);

  static bool _isPlaceholder(Event? event) =>
      event?.type == EventTypes.refreshingLastEvent;

  /// A removed reaction: the SDK keeps it as the last event, redacted, and
  /// the chat list would preview it as "Redacted by ...".
  static bool _isRemovedReaction(Event? event) =>
      event?.type == EventTypes.Reaction && event!.redacted;

  void _rememberAll() {
    for (final room in client.rooms) {
      _remember(room);
    }
  }

  void _remember(Room room) {
    final event = room.lastEvent;
    if (event == null || _isPlaceholder(event) || _isRemovedReaction(event)) {
      return;
    }
    _kept[room.id] = event;
    if (event.type != EventTypes.Reaction) _keptMessage[room.id] = event;
  }

  /// Whether stored previews were checked yet. The keeper is attached when
  /// the client is created, before its rooms are loaded, so this happens
  /// after the first sync, when they are.
  bool _repairedStored = false;

  Future<void> _afterSync(SyncUpdate sync) async {
    if (!_repairedStored) {
      _repairedStored = true;
      unawaited(_repairStored());
    }
    final roomIds = sync.rooms?.join?.keys;
    if (roomIds == null) return;
    final restored = <String>[];
    for (final roomId in roomIds) {
      final room = client.getRoomById(roomId);
      if (room == null) continue;
      final removedReaction = _isRemovedReaction(room.lastEvent);
      if (!_isPlaceholder(room.lastEvent) && !removedReaction) {
        _remember(room);
        continue;
      }
      final kept = removedReaction ? _keptMessage[roomId] : _kept[roomId];
      if (kept == null) continue;
      room.lastEvent = kept;
      restored.add(roomId);
    }
    if (restored.isEmpty) return;
    await _store(restored);
  }

  /// Runs the same empty sync the SDK runs after refreshing a last event:
  /// it stores the events put back, sorts the rooms and tells the chat list.
  Future<void> _store(List<String> restored) async {
    await client.database.transaction(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: '',
          rooms: RoomsUpdate(
            join: {
              for (final roomId in restored)
                roomId: JoinedRoomUpdate(
                  timeline: TimelineUpdate(limited: false),
                ),
            },
          ),
        ),
      ),
    );
  }
}
