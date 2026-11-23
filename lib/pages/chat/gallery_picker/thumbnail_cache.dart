// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:collection';
import 'dart:typed_data';

import 'package:photo_manager/photo_manager.dart';

/// Keeps recently requested gallery thumbnails in memory.
///
/// Each entry holds the pending request and, once it finishes, the bytes.
/// Sharing the request means a tile rebuilt while still loading does not ask
/// the platform twice; keeping the bytes lets a tile scrolled back into view
/// paint on its first frame (via [peek]) instead of flashing a placeholder.
/// The least recently used entries are evicted past [capacity], which bounds
/// memory while the user flings through a large library.
class ThumbnailCache {
  /// Edge length in pixels requested from the platform. Large enough for a
  /// third of a phone screen at high density.
  static const int thumbnailSize = 300;

  final int capacity;

  final LinkedHashMap<String, _Entry> _entries = LinkedHashMap();

  ThumbnailCache({this.capacity = 400});

  /// Thumbnail bytes if they have already been loaded, otherwise null.
  Uint8List? peek(AssetEntity entity) => _entries[entity.id]?.bytes;

  Future<Uint8List?> load(AssetEntity entity) {
    final existing = _entries.remove(entity.id);
    if (existing != null) {
      // Re-insert to mark the entry as most recently used.
      _entries[entity.id] = existing;
      return existing.future;
    }
    final entry = _Entry(
      entity.thumbnailDataWithSize(
        const ThumbnailSize.square(thumbnailSize),
        quality: 85,
      ),
    );
    _entries[entity.id] = entry;
    while (_entries.length > capacity) {
      _entries.remove(_entries.keys.first);
    }
    return entry.future;
  }
}

class _Entry {
  final Future<Uint8List?> future;
  Uint8List? bytes;

  _Entry(this.future) {
    // Errors are left to whoever awaits [future]; this only records bytes.
    future.then((value) => bytes = value, onError: (Object _) => null);
  }
}
