// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// Support levels a bridge gives a feature in `com.beeper.room_features`,
/// as defined by `CapabilitySupportLevel` in mautrix-go
/// (`event/capabilities.go`).
abstract final class CapabilityLevel {
  /// Unsupported, and messages using it are rejected.
  static const int rejected = -2;

  /// Unsupported with no fallback: the message goes through, but data may be
  /// lost.
  static const int dropped = -1;

  /// Unsupported, but the bridge may have a fallback.
  static const int unsupported = 0;

  /// Partially supported, for example converted to another format.
  static const int partial = 1;

  /// Fully supported.
  static const int full = 2;

  /// Whether content at [level] arrives intact: neither dropped nor
  /// rejected.
  static bool usable(int level) => level >= unsupported;

  /// Whether a bridge refuses a message using a feature at [level]
  /// (mautrix-go `CapabilitySupportLevel.Reject`).
  static bool rejects(int level) => level <= rejected;
}

/// Message types that are keys of the `file` map. Besides the real
/// `msgtype` values, mautrix uses the voice flag's key for voice messages.
abstract final class CapabilityMsgType {
  static const String image = MessageTypes.Image;
  static const String video = MessageTypes.Video;
  static const String audio = MessageTypes.Audio;
  static const String file = MessageTypes.File;
  static const String voice = 'org.matrix.msc3245.voice';
}

/// What a room accepts for one message type: one entry of the `file` map,
/// mautrix-go's `FileFeatures`.
class FileFeatures {
  /// Support level per mime type. Keys are exact (`image/png`), a subtype
  /// wildcard (`image/*`) or `*/*`.
  final Map<String, int> mimeTypes;

  /// Support level for a caption on this message type. Absent is 0.
  final int caption;

  /// Largest accepted file in bytes, or null for no limit.
  final int? maxSize;

  const FileFeatures({
    required this.mimeTypes,
    this.caption = CapabilityLevel.unsupported,
    this.maxSize,
  });

  /// Parses one entry, or returns null when [json] is not an object.
  /// Members of the wrong type are skipped.
  static FileFeatures? fromJson(Object? json) {
    if (json is! Map) return null;
    final mimeTypes = <String, int>{};
    final rawMimes = json['mime_types'];
    if (rawMimes is Map) {
      for (final entry in rawMimes.entries) {
        final key = entry.key;
        final level = entry.value;
        if (key is String && level is int) {
          mimeTypes[key.toLowerCase()] = level;
        }
      }
    }
    final caption = json['caption'];
    final maxSize = json['max_size'];
    return FileFeatures(
      mimeTypes: mimeTypes,
      caption: caption is int ? caption : CapabilityLevel.unsupported,
      maxSize: maxSize is int && maxSize > 0 ? maxSize : null,
    );
  }

  /// The support level of [mimeType], looked up as mautrix-go's
  /// `GetMimeSupport` does: the exact type, then the type without
  /// parameters, then `type/*`, then `*/*`, else rejected. The most specific
  /// listed key wins even when a wildcard has a higher level.
  int mimeSupport(String mimeType) {
    final mime = mimeType.toLowerCase().trim();
    final exact = mimeTypes[mime];
    if (exact != null) return exact;
    final semicolon = mime.indexOf(';');
    if (semicolon != -1) {
      final plain = mimeTypes[mime.substring(0, semicolon).trim()];
      if (plain != null) return plain;
    }
    final slash = mime.indexOf('/');
    if (slash > 0) {
      final general = mimeTypes['${mime.substring(0, slash)}/*'];
      if (general != null) return general;
    }
    return mimeTypes['*/*'] ?? CapabilityLevel.rejected;
  }

  /// Mime types listed at a usable level, for telling the user what the
  /// chat takes.
  List<String> get usableMimeTypes => [
    for (final entry in mimeTypes.entries)
      if (CapabilityLevel.usable(entry.value)) entry.key,
  ];
}

/// The media part of a room's `com.beeper.room_features` state event, which
/// mautrix bridges publish to say what the remote network accepts.
///
/// A room without the event, or with one whose `file` member is missing or
/// not an object, has no restrictions: everything is accepted, so plain
/// Matrix rooms behave as if this class did not exist.
class RoomFeatures {
  static const String eventType = 'com.beeper.room_features';

  /// Features per message type, or null when the room states none.
  final Map<String, FileFeatures>? file;

  const RoomFeatures({this.file});

  static const RoomFeatures unrestricted = RoomFeatures();

  bool get isUnrestricted => file == null;

  /// Parses the content of a `com.beeper.room_features` event.
  factory RoomFeatures.fromJson(Object? content) {
    if (content is! Map) return unrestricted;
    final rawFile = content['file'];
    if (rawFile is! Map) return unrestricted;
    final file = <String, FileFeatures>{};
    for (final entry in rawFile.entries) {
      final key = entry.key;
      final features = FileFeatures.fromJson(entry.value);
      if (key is String && features != null) file[key] = features;
    }
    return RoomFeatures(file: file);
  }

  /// The features of [room], from its newest `com.beeper.room_features`
  /// event. Each bridge sends the event under its own state key, so the one
  /// with the latest timestamp wins. Reads only state already in memory;
  /// see [load].
  factory RoomFeatures.of(Room room) {
    final events = room.states[eventType]?.values;
    if (events == null || events.isEmpty) return unrestricted;
    StrippedStateEvent? newest;
    var newestTs = -1;
    for (final event in events) {
      final ts = event is Event
          ? event.originServerTs.millisecondsSinceEpoch
          : 0;
      if (newest == null || ts > newestTs) {
        newest = event;
        newestTs = ts;
      }
    }
    return RoomFeatures.fromJson(newest?.content);
  }

  /// Like [RoomFeatures.of], after loading the room's remaining state from
  /// the database. The SDK keeps only a few state types in memory until a
  /// room's timeline is opened, and a merged contact can send to a room that
  /// was never opened.
  static Future<RoomFeatures> load(Room room) async {
    try {
      await room.postLoad();
    } catch (e, s) {
      Logs().w('Unable to load room state for room features', e, s);
    }
    return RoomFeatures.of(room);
  }

  /// The entry for [msgType], or null when the room has none (a restricted
  /// room then refuses that message type).
  FileFeatures? featuresFor(String msgType) => file?[msgType];

  /// The support level of [mimeType] sent as [msgType].
  int mimeSupport(String msgType, String mimeType) {
    final file = this.file;
    if (file == null) return CapabilityLevel.full;
    final features = file[msgType];
    if (features == null) return CapabilityLevel.rejected;
    return features.mimeSupport(mimeType);
  }

  /// Whether [mimeType] sent as [msgType] arrives intact.
  bool acceptsMime(String msgType, String mimeType) =>
      CapabilityLevel.usable(mimeSupport(msgType, mimeType));

  /// Whether the bridge refuses [mimeType] sent as [msgType].
  bool rejectsMime(String msgType, String mimeType) =>
      CapabilityLevel.rejects(mimeSupport(msgType, mimeType));

  /// Whether a caption on [msgType] arrives intact. A message type the room
  /// has no entry for is refused whole, so its caption level does not
  /// matter and this returns true.
  bool acceptsCaption(String msgType) {
    final features = featuresFor(msgType);
    if (features == null) return true;
    return CapabilityLevel.usable(features.caption);
  }

  /// Largest accepted [msgType] file in bytes, or null for no limit.
  int? maxSize(String msgType) => featuresFor(msgType)?.maxSize;
}
