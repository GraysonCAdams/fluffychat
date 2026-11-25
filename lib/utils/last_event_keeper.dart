// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

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
/// place. The SDK's own refresh still replaces it when the server knows a
/// newer event.
class LastEventKeeper {
  final Client client;

  /// The last real event of each room, as of before the running sync.
  final Map<String, Event> _kept = {};

  LastEventKeeper._(this.client) {
    client.onSyncStatus.stream.listen((update) {
      // Sent before each sync request, well before its response is handled.
      if (update.status == SyncStatus.waitingForResponse) _rememberAll();
    });
    client.onSync.stream.listen(_afterSync);
  }

  static final Expando<LastEventKeeper> _keepers = Expando();

  /// Starts keeping the last events of [client]'s rooms.
  static LastEventKeeper attach(Client client) =>
      _keepers[client] ??= LastEventKeeper._(client);

  static bool _isPlaceholder(Event? event) =>
      event?.type == EventTypes.refreshingLastEvent;

  void _rememberAll() {
    for (final room in client.rooms) {
      _remember(room);
    }
  }

  void _remember(Room room) {
    final event = room.lastEvent;
    if (event != null && !_isPlaceholder(event)) _kept[room.id] = event;
  }

  Future<void> _afterSync(SyncUpdate sync) async {
    final roomIds = sync.rooms?.join?.keys;
    if (roomIds == null) return;
    final restored = <String>[];
    for (final roomId in roomIds) {
      final room = client.getRoomById(roomId);
      if (room == null) continue;
      if (!_isPlaceholder(room.lastEvent)) {
        _remember(room);
        continue;
      }
      final kept = _kept[roomId];
      if (kept == null) continue;
      room.lastEvent = kept;
      restored.add(roomId);
    }
    if (restored.isEmpty) return;
    // The same empty sync the SDK runs after refreshing a last event: it
    // stores the event put back, sorts the rooms and tells the chat list.
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
