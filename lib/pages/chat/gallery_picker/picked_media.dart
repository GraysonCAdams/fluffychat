// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:cross_file/cross_file.dart';
import 'package:flutter/foundation.dart';
import 'package:photo_manager/photo_manager.dart';

/// One item the user has picked: either an asset from the device gallery
/// or a photo or video just captured with the in-picker camera.
sealed class PickedMedia {
  const PickedMedia();

  /// Stable identity used for selection lookups and widget keys.
  String get id;

  bool get isVideo;

  /// Width divided by height as the media is displayed upright. Used to size
  /// the preview cards without decoding the full image first.
  double get aspectRatio;
}

/// A photo or video from the device gallery, read through photo_manager.
class GalleryMedia extends PickedMedia {
  final AssetEntity entity;

  const GalleryMedia(this.entity);

  @override
  String get id => 'asset:${entity.id}';

  @override
  bool get isVideo => entity.type == AssetType.video;

  @override
  double get aspectRatio {
    final size = entity.orientatedSize;
    if (size.width <= 0 || size.height <= 0) return 1;
    return size.width / size.height;
  }
}

/// A photo or video captured by the camera view while the picker was open.
/// The file lives in the app cache until it is sent.
class CapturedMedia extends PickedMedia {
  final XFile file;

  @override
  final bool isVideo;

  @override
  final double aspectRatio;

  const CapturedMedia({
    required this.file,
    required this.isVideo,
    required this.aspectRatio,
  });

  @override
  String get id => 'capture:${file.path}';
}

/// The ordered set of picked media.
///
/// Listeners of the notifier itself hear every change (the send preview
/// needs the whole list). Grid tiles instead watch [isSelected] for their own
/// id, so toggling one tile rebuilds only the tiles whose state changed
/// rather than the whole grid.
class MediaSelection extends ChangeNotifier {
  final List<PickedMedia> _items = [];
  final Map<String, ValueNotifier<bool>> _flags = {};

  /// Picked media in the order the user picked them.
  List<PickedMedia> get items => List.unmodifiable(_items);

  int get length => _items.length;

  bool get isEmpty => _items.isEmpty;

  bool contains(String id) => _items.any((item) => item.id == id);

  /// Per-item selected flag. The notifier is created on first use and kept
  /// until the selection is disposed, so a tile scrolled back into view
  /// picks up the current state.
  ValueListenable<bool> isSelected(String id) =>
      _flags.putIfAbsent(id, () => ValueNotifier(contains(id)));

  void add(PickedMedia media) {
    if (contains(media.id)) return;
    _items.add(media);
    _flags[media.id]?.value = true;
    notifyListeners();
  }

  void remove(String id) {
    final before = _items.length;
    _items.removeWhere((item) => item.id == id);
    if (_items.length == before) return;
    _flags[id]?.value = false;
    notifyListeners();
  }

  void toggle(PickedMedia media) =>
      contains(media.id) ? remove(media.id) : add(media);

  @override
  void dispose() {
    for (final flag in _flags.values) {
      flag.dispose();
    }
    super.dispose();
  }
}
