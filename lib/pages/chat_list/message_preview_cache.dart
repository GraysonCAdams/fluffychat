// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:collection';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:matrix/matrix.dart';

/// Remembers the localized preview body of the last event of a chat.
///
/// Building that body parses the message as Markdown and HTML, which is far
/// too slow to repeat for every chat list tile on every rebuild while the
/// list scrolls. The key holds everything the body can depend on: the event
/// and its state, the localization, the kind of localization wrapper, and the
/// display names the localized text can embed. A change to any of those
/// gives a new key, so a cached body is never stale. The "Sender: " prefix
/// is added by the caller and is not part of the cached text.
abstract final class MessagePreviewCache {
  static const int _maxEntries = 500;

  // A LinkedHashMap iterates in insertion order. A hit is moved to the end,
  // so the first entry is always the least recently used one.
  static final LinkedHashMap<Object, String> _cache = LinkedHashMap();

  static String? _memberName(Room room, String? userId) {
    if (userId == null) return null;
    return room
        .getState(EventTypes.RoomMember, userId)
        ?.asUser(room)
        .displayName;
  }

  static String localizedBody(
    Event event,
    L10n l10n,
    MatrixLocals previewLocals,
  ) {
    // An effect that hides the message hides it here too.
    String compute() =>
        effectPreviewOf(event, l10n) ??
        event.calcLocalizedBody(
          previewLocals,
          hideReply: true,
          hideEdit: true,
          plaintextBody: true,
          removeMarkdown: true,
        );

    // A message that could not be decrypted keeps its event id and type
    // while its content can change between decryption attempts, so the key
    // would not catch every change.
    if (event.type == EventTypes.Encrypted) return compute();

    final room = event.room;
    // Read straight from the unsigned data: Event.redacted parses the whole
    // redaction event on every call. This is the same test it makes.
    final redactedBecause = event.unsigned?['redacted_because'];
    final redacted = redactedBecause is Map<String, dynamic>;
    final redactorId = redactedBecause is Map<String, dynamic>
        ? redactedBecause['sender']
        : null;
    final key = (
      event.eventId,
      event.type,
      redacted,
      event.status,
      l10n,
      previewLocals.runtimeType,
      previewLocals is DirectChatMatrixLocals
          ? previewLocals.partnerName
          : null,
      _memberName(room, event.senderId),
      _memberName(room, event.stateKey),
      _memberName(room, redactorId is String ? redactorId : null),
    );

    final cached = _cache.remove(key);
    if (cached != null) {
      _cache[key] = cached;
      return cached;
    }
    final body = compute();
    _cache[key] = body;
    if (_cache.length > _maxEntries) _cache.remove(_cache.keys.first);
    return body;
  }
}
