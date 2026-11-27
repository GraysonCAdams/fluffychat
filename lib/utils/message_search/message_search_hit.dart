// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// One message found by a search engine.
class MessageSearchHit {
  final String eventId;
  final String roomId;
  final String senderId;

  /// Display name and avatar of the sender as the homeserver reported them
  /// with the result. The local index does not store profiles, so its hits
  /// leave these null and the room's member list fills them in.
  final String? senderName;
  final Uri? senderAvatar;

  /// Plain text of the message.
  final String body;
  final DateTime timestamp;

  /// The message's `msgtype`, such as `m.image`, as the homeserver reported
  /// it. The local index does not store it, so its hits leave it null.
  final String? msgtype;

  const MessageSearchHit({
    required this.eventId,
    required this.roomId,
    required this.senderId,
    required this.body,
    required this.timestamp,
    this.senderName,
    this.senderAvatar,
    this.msgtype,
  });

  /// The same message found by another engine adds what this hit lacks.
  MessageSearchHit mergedWith(MessageSearchHit other) => MessageSearchHit(
    eventId: eventId,
    roomId: roomId,
    senderId: senderId,
    body: body,
    timestamp: timestamp,
    senderName: senderName ?? other.senderName,
    senderAvatar: senderAvatar ?? other.senderAvatar,
    msgtype: msgtype ?? other.msgtype,
  );
}

/// One page of results from a [MessageSearchSource].
class MessageSearchPage {
  final List<MessageSearchHit> hits;

  /// Passed back to the source to fetch the following page. Null on the last
  /// page.
  final Object? nextCursor;

  /// Words to emphasise in addition to the query terms. The homeserver may
  /// match other forms of a word than the one typed and reports them here.
  final List<String> highlights;

  const MessageSearchPage({
    required this.hits,
    this.nextCursor,
    this.highlights = const [],
  });

  static const empty = MessageSearchPage(hits: []);
}

/// Adds [incoming] to [current] and returns the result newest first, with
/// each event listed once no matter how many engines found it.
List<MessageSearchHit> mergeHits(
  List<MessageSearchHit> current,
  Iterable<MessageSearchHit> incoming,
) {
  final byEventId = <String, MessageSearchHit>{
    for (final hit in current) hit.eventId: hit,
  };
  for (final hit in incoming) {
    final known = byEventId[hit.eventId];
    byEventId[hit.eventId] = known == null ? hit : known.mergedWith(hit);
  }
  return byEventId.values.toList()..sort((a, b) {
    final byTime = b.timestamp.compareTo(a.timestamp);
    // Bridges can import many messages with one timestamp. The event ID keeps
    // their order stable between merges.
    return byTime != 0 ? byTime : a.eventId.compareTo(b.eventId);
  });
}
