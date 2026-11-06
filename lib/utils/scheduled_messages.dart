// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// A message the homeserver holds and sends later (MSC4140 delayed events).
class ScheduledMessage {
  final String delayId;
  final String roomId;
  final String text;
  final DateTime sendAt;

  const ScheduledMessage({
    required this.delayId,
    required this.roomId,
    required this.text,
    required this.sendAt,
  });

  Map<String, Object> toJson() => {
    'room_id': roomId,
    'text': text,
    'send_at': sendAt.millisecondsSinceEpoch,
  };

  factory ScheduledMessage.fromJson(
    String delayId,
    Map<String, Object?> json,
  ) => ScheduledMessage(
    delayId: delayId,
    roomId: json['room_id'] as String,
    text: json['text'] as String,
    sendAt: DateTime.fromMillisecondsSinceEpoch(json['send_at'] as int),
  );
}

extension ScheduledMessagesExtension on Client {
  /// Encrypted rooms hand the homeserver ciphertext, so the text of each
  /// scheduled message is kept locally to list it again.
  String get _scheduledMessagesKey => 'chat.fluffy.scheduled_messages.$userID';

  /// Whether the homeserver advertises delayed events. A homeserver without
  /// them ignores the delay parameter and sends right away, so scheduling is
  /// only offered when this is true.
  Future<bool> get canScheduleMessages async {
    try {
      final versions = await getVersions();
      return versions.unstableFeatures?['org.matrix.msc4140'] == true;
    } catch (e, s) {
      Logs().w('Unable to check for delayed event support', e, s);
      return false;
    }
  }

  /// The scheduled messages the homeserver still holds, with their text.
  Future<List<ScheduledMessage>> scheduledMessages(
    SharedPreferences store, {
    String? roomId,
  }) async {
    final saved = _savedScheduledMessages(store);
    final pending = await getScheduledDelayedEvents();
    final pendingIds = pending.scheduledEvents.map((e) => e.delayId).toSet();

    // Drop the local text of messages that were sent or cancelled elsewhere.
    saved.removeWhere((delayId, _) => !pendingIds.contains(delayId));
    await store.setString(_scheduledMessagesKey, jsonEncode(saved));

    return [
        for (final MapEntry(:key, :value) in saved.entries)
          ScheduledMessage.fromJson(key, value as Map<String, Object?>),
      ].where((m) => roomId == null || m.roomId == roomId).toList()
      ..sort((a, b) => a.sendAt.compareTo(b.sendAt));
  }

  Future<void> cancelScheduledMessage(
    SharedPreferences store,
    String delayId,
  ) async {
    await manageDelayedEvent(delayId, DelayedEventAction.cancel);
    await _forgetScheduledMessage(store, delayId);
  }

  Future<void> sendScheduledMessageNow(
    SharedPreferences store,
    String delayId,
  ) async {
    await manageDelayedEvent(delayId, DelayedEventAction.send);
    await _forgetScheduledMessage(store, delayId);
  }

  Map<String, Object?> _savedScheduledMessages(SharedPreferences store) {
    final raw = store.getString(_scheduledMessagesKey);
    if (raw == null) return {};
    return Map<String, Object?>.from(jsonDecode(raw) as Map);
  }

  Future<void> _forgetScheduledMessage(
    SharedPreferences store,
    String delayId,
  ) async {
    final saved = _savedScheduledMessages(store)..remove(delayId);
    await store.setString(_scheduledMessagesKey, jsonEncode(saved));
  }
}

extension ScheduleRoomMessageExtension on Room {
  /// Hands [text] to the homeserver to send into this room at [sendAt], and
  /// returns the scheduled message.
  ///
  /// Throws if the homeserver replies without a delay ID, which means it sent
  /// the message right away instead of holding it.
  Future<ScheduledMessage> scheduleTextMessage(
    SharedPreferences store,
    String text,
    DateTime sendAt,
  ) async {
    final delay = sendAt.difference(DateTime.now()).inMilliseconds;
    if (delay <= 0) {
      throw ArgumentError.value(sendAt, 'sendAt', 'must be in the future');
    }

    final content = {'msgtype': MessageTypes.Text, 'body': text};
    final payload = encrypted && client.encryptionEnabled
        ? await client.encryption!.encryptGroupMessagePayload(
            id,
            content,
            type: EventTypes.Message,
          )
        : content;
    final type = payload.containsKey('ciphertext')
        ? EventTypes.Encrypted
        : EventTypes.Message;

    final requestUri = Uri(
      path:
          '_matrix/client/v3/rooms/${Uri.encodeComponent(id)}/send/'
          '${Uri.encodeComponent(type)}/'
          '${Uri.encodeComponent(client.generateUniqueTransactionId())}',
      queryParameters: {'org.matrix.msc4140.delay': delay.toString()},
    );
    final request = http.Request('PUT', client.baseUri!.resolveUri(requestUri))
      ..headers['authorization'] = 'Bearer ${client.bearerToken!}'
      ..headers['content-type'] = 'application/json'
      ..bodyBytes = utf8.encode(jsonEncode(payload));
    final response = await client.httpClient.send(request);
    final responseBody = await response.stream.toBytes();
    if (response.statusCode != 200) {
      client.unexpectedResponse(response, responseBody);
    }
    final delayId = jsonDecode(utf8.decode(responseBody))['delay_id'];
    if (delayId is! String) {
      throw Exception('The homeserver sent the message instead of holding it');
    }

    final message = ScheduledMessage(
      delayId: delayId,
      roomId: id,
      text: text,
      sendAt: sendAt,
    );
    final saved = client._savedScheduledMessages(store)
      ..[delayId] = message.toJson();
    await store.setString(client._scheduledMessagesKey, jsonEncode(saved));
    return message;
  }
}
