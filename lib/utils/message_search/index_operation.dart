// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// A change to the local message index that follows from one timeline event.
sealed class IndexOperation {
  const IndexOperation();

  /// Works out what an event means for the index, from the few fields that
  /// matter. Returns null for events that do not touch it.
  ///
  /// The fields are passed one by one because they come from two places: live
  /// events arrive as objects, while stored events are read column-wise
  /// straight out of the SDK database without decoding their JSON in Dart.
  static IndexOperation? fromEvent({
    required String? type,
    required String? eventId,
    required String? roomId,
    required String? senderId,
    required int? timestamp,
    required String? body,
    int? status,
    String? redacts,
    bool isRedacted = false,
    String? relationType,
    String? relatesToEventId,
    String? replacementBody,
  }) {
    if (type == 'm.room.redaction') {
      return redacts == null ? null : RemoveMessage(redacts);
    }
    if (eventId == null) return null;
    // A message that is still being sent, or failed to send, is stored under
    // a transaction ID. It shows up again under its real ID once sent.
    if (status != null && status < _statusSent) return null;
    if (isRedacted) return RemoveMessage(eventId);
    // An encrypted event that could not be decrypted keeps the type
    // m.room.encrypted and is skipped here like every other non-message.
    if (type != 'm.room.message') return null;
    if (roomId == null || senderId == null || timestamp == null) return null;

    if (relationType == 'm.replace' && relatesToEventId != null) {
      final text = _indexable(replacementBody ?? body);
      if (text == null) return null;
      return IndexMessage(
        eventId: relatesToEventId,
        roomId: roomId,
        senderId: senderId,
        timestamp: timestamp,
        body: text,
        editTimestamp: timestamp,
      );
    }
    final text = _indexable(body);
    if (text == null) return null;
    return IndexMessage(
      eventId: eventId,
      roomId: roomId,
      senderId: senderId,
      timestamp: timestamp,
      body: text,
    );
  }

  /// Same as [fromEvent], for an event in the JSON form the SDK uses for
  /// storage and for [Event.toJson].
  static IndexOperation? fromEventJson(Map<String, Object?> json) {
    final content = json['content'];
    final unsigned = json['unsigned'];
    final relation = content is Map ? content['m.relates_to'] : null;
    final replacement = content is Map ? content['m.new_content'] : null;
    return fromEvent(
      type: _string(json['type']),
      eventId: _string(json['event_id']),
      roomId: _string(json['room_id']),
      senderId: _string(json['sender']),
      timestamp: json['origin_server_ts'] is int
          ? json['origin_server_ts']! as int
          : null,
      body: content is Map ? _string(content['body']) : null,
      status: json['status'] is int ? json['status']! as int : null,
      redacts: _string(json['redacts']),
      isRedacted: unsigned is Map && unsigned['redacted_because'] != null,
      relationType: relation is Map ? _string(relation['rel_type']) : null,
      relatesToEventId: relation is Map ? _string(relation['event_id']) : null,
      replacementBody: replacement is Map ? _string(replacement['body']) : null,
    );
  }

  /// Event content is whatever the sender put there, so a field that should
  /// be text may hold anything.
  static String? _string(Object? value) => value is String ? value : null;

  /// The SDK's `EventStatus.sent`. Lower values are `sending` and `error`.
  static const _statusSent = 1;

  /// A single pasted log file should not take megabytes of index. Text past
  /// this length is not searchable.
  static const maxBodyLength = 20000;

  static String? _indexable(String? body) {
    if (body == null) return null;
    final text = body.trim();
    if (text.isEmpty) return null;
    return text.length > maxBodyLength
        ? text.substring(0, maxBodyLength)
        : text;
  }
}

/// Add a message, or replace its text when it is already indexed.
class IndexMessage extends IndexOperation {
  /// The event the result opens. For an edit this is the edited message, so
  /// that a search finds the message once, with its current text.
  final String eventId;
  final String roomId;
  final String senderId;
  final int timestamp;
  final String body;

  /// When the edit that produced [body] was sent, or 0 for original text.
  /// Events can be indexed in any order, and the newest edit has to win.
  final int editTimestamp;

  const IndexMessage({
    required this.eventId,
    required this.roomId,
    required this.senderId,
    required this.timestamp,
    required this.body,
    this.editTimestamp = 0,
  });
}

/// Drop a message that was redacted.
class RemoveMessage extends IndexOperation {
  final String eventId;

  const RemoveMessage(this.eventId);
}

/// How much the local index holds and what it costs on disk.
class LocalMessageIndexStats {
  final int messages;
  final int bytes;

  const LocalMessageIndexStats({required this.messages, required this.bytes});
}
