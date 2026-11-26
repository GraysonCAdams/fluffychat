// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/fallback_avatar_image.dart';
import 'package:fluffychat/utils/group_collage_image.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/conversation.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/notification_avatar_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

/// Messages per conversation the car gets, as the Android Auto docs advise.
const carMessagesPerConversation = 5;

/// One car conversation: a room, or a merged contact's rooms.
@immutable
class CarConversationRooms {
  /// The Android conversation ID, the same as its shortcut's.
  final String id;

  /// Its rooms, newest activity first.
  final List<String> roomIds;

  const CarConversationRooms(this.id, this.roomIds);
}

/// Groups rooms, given newest first with their conversation IDs, into at
/// most [limit] conversations, keeping the order of each conversation's
/// newest room.
List<CarConversationRooms> groupCarConversations(
  Iterable<(String roomId, String conversationId)> rooms,
  int limit,
) {
  final byId = <String, List<String>>{};
  for (final (roomId, conversationId) in rooms) {
    final roomIds = byId[conversationId];
    if (roomIds != null) {
      roomIds.add(roomId);
    } else if (byId.length < limit) {
      byId[conversationId] = [roomId];
    }
  }
  return [for (final e in byId.entries) CarConversationRooms(e.key, e.value)];
}

/// The room a reply from the car goes to: the room of the newest message
/// the other side sent, as a notification reply goes to the room it came
/// from. [lastIncoming] maps each room to the time of its newest message
/// from someone else. Falls back to [sendVia], then to the first room.
String carReplyRoom(
  List<String> roomIds,
  Map<String, DateTime?> lastIncoming, {
  String? sendVia,
}) {
  String? best;
  DateTime? bestTime;
  for (final roomId in roomIds) {
    final time = lastIncoming[roomId];
    if (time == null) continue;
    if (bestTime == null || time.isAfter(bestTime)) {
      best = roomId;
      bestTime = time;
    }
  }
  return best ?? sendVia ?? roomIds.first;
}

/// One message of a car conversation: [event] as stored (its sender and
/// timestamp), the [body] to show, and whether it counts as [read].
typedef CarMessage = ({Event event, String body, bool read});

/// The newest messages of [room] for the car, oldest first.
///
/// A bridge sends a placeholder ("Waiting for attachment ...") and then
/// edits it into the real message, so the newest edit by the sender
/// replaces each message's content before its body is rendered. The
/// message keeps its original timestamp. The room's newest messages from
/// others, as many as it counts unread, are the unread ones.
Future<List<CarMessage>> carRoomMessages(
  Client client,
  Room room,
  MatrixLocals locals,
) async {
  final all = await client.database.getEventList(room, limit: 20);
  final senders = {for (final e in all) e.eventId: e.senderId};
  final edits = <String, Event>{};
  for (final e in all) {
    final target = e.relationshipEventId;
    // Only the author can edit a message.
    if (e.relationshipType != RelationshipTypes.edit ||
        target == null ||
        senders[target] != e.senderId) {
      continue;
    }
    final known = edits[target];
    if (known == null || e.originServerTs.isAfter(known.originServerTs)) {
      edits[target] = e;
    }
  }
  final events = all.where(
    (e) =>
        {
          EventTypes.Message,
          EventTypes.Encrypted,
          EventTypes.Sticker,
        }.contains(e.type) &&
        e.redacted == false &&
        e.relationshipType != RelationshipTypes.edit,
  );
  var unread = room.notificationCount;
  final messages = <CarMessage>[];
  for (final event in events) {
    final edit = edits[event.eventId];
    final newContent = edit?.content['m.new_content'];
    final shown = newContent is Map<String, Object?>
        ? Event.fromJson({...event.toJson(), 'content': newContent}, room)
        : event;
    final own = event.senderId == client.userID;
    messages.add((
      event: event,
      body: shown.calcLocalizedBody(
        locals,
        plaintextBody: true,
        hideReply: true,
        hideEdit: true,
        removeMarkdown: true,
      ),
      read: own || unread <= 0,
    ));
    if (!own) unread--;
  }
  return messages;
}

/// Serves the Android Auto conversation list (SeamCarAppService.kt) from
/// the app's Matrix clients over the `chat.fluffy.fluffychat/car` channel.
///
/// Calls from the car:
/// - `conversations {limit}`: the latest conversations with their last
///   messages, or `signedIn: false` when no account is logged in.
/// - `reply {client, id, text}`: sends [text] to [carReplyRoom].
/// - `markRead {client, id}`: sets the read marker in each unread room of
///   the conversation.
/// - `start` / `stop`: a car screen opened or closed. While one is open the
///   clients sync even when the app runs headless, and every sync with new
///   timeline events calls `changed` on the car side.
class CarAppBridge {
  static const _channel = MethodChannel('chat.fluffy.fluffychat/car');

  static List<Client> _clients = [];
  static int _sessions = 0;
  static final Set<Client> _syncStartedHere = {};
  static final List<StreamSubscription> _syncSubscriptions = [];
  static Timer? _changedDebounce;
  static final Map<String, Uint8List?> _iconCache = {};

  /// Starts answering the car. Called once the clients are loaded, whether
  /// the app shows its window or runs headless for a push.
  static void attach(List<Client> clients) {
    if (!PlatformInfos.isAndroid) return;
    _clients = clients;
    _channel.setMethodCallHandler(_handle);
    _channel.invokeMethod('ready').catchError((_) {});
  }

  static Future<Object?> _handle(MethodCall call) async {
    final args = (call.arguments as Map?)?.cast<String, Object?>() ?? {};
    switch (call.method) {
      case 'conversations':
        return _conversations((args['limit'] as int?) ?? 10);
      case 'reply':
        await _reply(
          args['client'] as String,
          args['id'] as String,
          args['text'] as String,
        );
        return null;
      case 'markRead':
        await _markRead(args['client'] as String, args['id'] as String);
        return null;
      case 'start':
        _start();
        return null;
      case 'stop':
        _stop();
        return null;
    }
    throw MissingPluginException(call.method);
  }

  static Iterable<Client> get _loggedIn => _clients.where((c) => c.isLogged());

  static Client? _client(String clientName) =>
      _loggedIn.firstWhereOrNull((c) => c.clientName == clientName);

  static Future<Map<String, Object?>> _conversations(int limit) async {
    final clients = _loggedIn.toList();
    if (clients.isEmpty) return {'signedIn': false};
    final l10n = await lookupL10n(PlatformDispatcher.instance.locale);
    final locals = MatrixLocals(l10n);

    final rooms = <(Client, Room)>[];
    for (final client in clients) {
      await client.roomsLoading;
      await MergedContactsStore.forClient(client).loaded;
      rooms.addAll(
        client.rooms
            .where(
              (r) =>
                  r.membership == Membership.join &&
                  !r.isSpace &&
                  r.lastEvent != null,
            )
            .map((r) => (client, r)),
      );
    }
    rooms.sort(
      (a, b) =>
          b.$2.latestEventReceivedTime.compareTo(a.$2.latestEventReceivedTime),
    );

    // Conversation IDs are per account, so the key carries the client too.
    // A room's last event can be a reaction or a state change, so more
    // conversations than shown are read and then ordered by their newest
    // message.
    final groups = groupCarConversations(
      rooms.map(
        (e) => (
          '${e.$1.clientName}\n${e.$2.id}',
          '${e.$1.clientName}\n${notificationConversation(e.$1, e.$2.id)}',
        ),
      ),
      limit * 3,
    );

    final conversations = <Map<String, Object?>>[];
    for (final group in groups) {
      final clientName = group.id.split('\n').first;
      final client = clients.firstWhere((c) => c.clientName == clientName);
      final conversationId = group.id.split('\n').last;
      final groupRooms = group.roomIds
          .map((key) => client.getRoomById(key.split('\n').last))
          .nonNulls
          .toList();
      if (groupRooms.isEmpty) continue;
      conversations.add(
        await _conversation(client, conversationId, groupRooms, locals),
      );
    }
    int newest(Map<String, Object?> c) =>
        ((c['messages'] as List).lastOrNull as Map?)?['ts'] as int? ?? 0;
    conversations.sort((a, b) => newest(b).compareTo(newest(a)));
    final shown = conversations.take(limit).toList();
    await Future.wait(shown.map(_finish));
    return {'signedIn': true, 'conversations': shown};
  }

  static Future<Map<String, Object?>> _conversation(
    Client client,
    String conversationId,
    List<Room> rooms,
    MatrixLocals locals,
  ) async {
    final newest = rooms.first;
    final title =
        notificationConversationName(client, newest.id, locals) ??
        newest.getLocalizedDisplayname(locals);

    final messages = <CarMessage>[];
    for (final room in rooms) {
      messages.addAll(await carRoomMessages(client, room, locals));
    }
    messages.sort(
      (a, b) => b.event.originServerTs.compareTo(a.event.originServerTs),
    );
    final shown = messages.take(carMessagesPerConversation).toList().reversed;

    return {
      'id': conversationId,
      'client': client.clientName,
      'title': title,
      'group': !newest.isDirectChat,
      // Pictures and names are looked up in [_finish] once the
      // conversation makes the list.
      'icon': (
        client,
        newest.avatar,
        GroupAvatar.shows(newest) ? newest : null,
      ),
      'self': {'name': newest, 'key': client.userID},
      'messages': [
        for (final CarMessage(:event, :body, :read) in shown)
          {
            'key': event.senderId,
            'name': event,
            'body': body,
            'ts': event.originServerTs.millisecondsSinceEpoch,
            'read': read,
          },
      ],
    };
  }

  /// Replaces the placeholders [_conversation] leaves: the picture, and
  /// the senders' and own names. A headless start has no members in memory
  /// yet, so names come from the database (or the server) instead of
  /// showing bare user IDs.
  static Future<void> _finish(Map<String, Object?> conversation) async {
    final (client, avatar, collageRoom) =
        conversation['icon'] as (Client, Uri?, Room?);
    conversation['icon'] = await _icon(
      client,
      avatar,
      conversation['title'] as String,
      collageRoom,
    );
    final self = conversation['self'] as Map<String, Object?>;
    final room = self['name'] as Room;
    self['name'] =
        (await _user(room, client.userID!) ??
                room.unsafeGetUserFromMemoryOrFallback(client.userID!))
            .calcDisplayname();
    for (final message in conversation['messages'] as List) {
      final map = message as Map<String, Object?>;
      final event = map['name'] as Event;
      map['name'] =
          (await _user(event.room, event.senderId) ??
                  event.senderFromMemoryOrFallback)
              .calcDisplayname();
    }
  }

  static Future<User?> _user(Room room, String userId) => room
      .requestUser(userId, ignoreErrors: true, requestProfile: false)
      .timeout(const Duration(seconds: 2), onTimeout: () => null);

  /// The conversation's picture: its avatar, else for a group without one
  /// (given as [collageRoom]) a collage of its members as the app shows,
  /// else its initials.
  static Future<Uint8List?> _icon(
    Client client,
    Uri? avatar,
    String title,
    Room? collageRoom,
  ) async {
    if (avatar == null && collageRoom != null) {
      final collage = await _collage(client, collageRoom);
      if (collage != null) return collage;
    }
    final key = avatar?.toString() ?? 'initials:$title';
    if (_iconCache.containsKey(key)) return _iconCache[key];
    final bytes = await (avatar == null
        ? renderFallbackAvatar(title, size: notificationAvatarDimension)
        : client.tryDownloadNotificationAvatar(avatar));
    return _iconCache[key] = bytes;
  }

  /// The member collage of [room], or null when fewer than two members can
  /// be loaded.
  static Future<Uint8List?> _collage(Client client, Room room) async {
    await GroupAvatar.loadMembers(
      room,
    ).timeout(const Duration(seconds: 4), onTimeout: () {});
    final users = (await Future.wait(
      GroupAvatar.memberIds(room, max: 4).map((id) => _user(room, id)),
    )).nonNulls.toList();
    if (users.length < 2) return null;
    final key =
        'collage:${room.id}:${users.map((u) => '${u.id}${u.avatarUrl}').join()}';
    if (_iconCache.containsKey(key)) return _iconCache[key];
    final members = await Future.wait(
      users.map(
        (user) async => (
          name: user.calcDisplayname(),
          image: await client.tryDownloadNotificationAvatar(user.avatarUrl),
        ),
      ),
    );
    return _iconCache[key] = await renderGroupCollage(
      members,
      size: notificationAvatarDimension,
    );
  }

  /// The rooms of [conversationId] in [client]: a merged contact's rooms, or
  /// the one room.
  static List<Room> _rooms(Client client, String conversationId) {
    final contactId = contactIdOfConversation(conversationId);
    final roomIds = contactId == null
        ? [conversationId]
        : MergedContactsStore.forClient(client).contactById(contactId)?.rooms ??
              const <String>[];
    return roomIds.map(client.getRoomById).nonNulls.toList();
  }

  static Future<void> _reply(
    String clientName,
    String conversationId,
    String text,
  ) async {
    final client = _client(clientName);
    if (client == null || text.trim().isEmpty) return;
    final rooms = _rooms(client, conversationId);
    if (rooms.isEmpty) return;
    final contactId = contactIdOfConversation(conversationId);
    final contact = contactId == null
        ? null
        : MergedContactsStore.forClient(client).contactById(contactId);
    final targetId = carReplyRoom(rooms.map((r) => r.id).toList(), {
      for (final room in rooms)
        room.id: room.lastEvent?.senderId == client.userID
            ? null
            : room.lastEvent?.originServerTs,
    }, sendVia: contact?.sendViaIn(rooms.map((r) => r.id).toList()));
    final target = client.getRoomById(targetId) ?? rooms.first;
    await target.sendTextEvent(
      text,
      parseCommands: false,
      displayPendingEvent: false,
    );
  }

  static Future<void> _markRead(
    String clientName,
    String conversationId,
  ) async {
    final client = _client(clientName);
    if (client == null) return;
    for (final room in _rooms(client, conversationId)) {
      final eventId = room.lastEvent?.eventId;
      if (!room.isUnread || eventId == null) continue;
      await room.setReadMarker(
        eventId,
        mRead: eventId,
        public: AppSettings.sendPublicReadReceipts.value,
      );
    }
  }

  /// Whether the app runs without its window, as it does for a push.
  static bool get _isHeadless {
    final lifecycle = WidgetsBinding.instance.lifecycleState;
    return lifecycle == null || lifecycle == AppLifecycleState.detached;
  }

  static void _start() {
    _sessions++;
    if (_sessions > 1) return;
    // Headless, the app syncs only for pushes (see main.dart).
    final headless = _isHeadless;
    for (final client in _loggedIn) {
      if (headless) {
        _syncStartedHere.add(client);
        client.backgroundSync = true;
      }
      _syncSubscriptions.add(
        client.onSync.stream.listen((update) {
          final changed =
              update.rooms?.join?.values.any(
                (room) => room.timeline?.events?.isNotEmpty ?? false,
              ) ??
              false;
          if (!changed) return;
          _changedDebounce?.cancel();
          _changedDebounce = Timer(const Duration(milliseconds: 500), () {
            _channel.invokeMethod('changed').catchError((_) {});
          });
        }),
      );
    }
  }

  static void _stop() {
    if (_sessions == 0) return;
    _sessions--;
    if (_sessions > 0) return;
    for (final sub in _syncSubscriptions) {
      sub.cancel();
    }
    _syncSubscriptions.clear();
    _changedDebounce?.cancel();
    // A headless app goes back to syncing only for pushes; once the window
    // opened, the app keeps syncing on its own.
    if (_isHeadless) {
      for (final client in _syncStartedHere) {
        client.backgroundSync = false;
      }
    }
    _syncStartedHere.clear();
  }
}
