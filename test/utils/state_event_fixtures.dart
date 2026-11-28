// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// A bridged one-to-one chat on the fake homeserver, as a Google Messages
/// portal looks once the bridge has set it up: the user, the bridge bot and
/// the remote person (Gloria) as members, and the room's `m.bridge` state
/// naming the bot and the network.
class BridgedChatFixture {
  static const bot = '@gmessagesbot:x';
  static const gloria = '@gmessages_15551234:x';

  final Room room;
  var _next = 0;

  BridgedChatFixture(this.room, {bool withNetworkName = true}) {
    _member(own, 'Grayson');
    _member(bot, 'Google Messages bridge bot');
    _member(gloria, 'Gloria');
    room.setState(
      StrippedStateEvent(
        type: 'm.bridge',
        stateKey: 'gmessages',
        senderId: bot,
        content: {
          'bridgebot': bot,
          'protocol': {
            'id': 'gmessages',
            if (withNetworkName) 'displayname': 'Google Messages',
          },
        },
      ),
    );
  }

  String get own => room.client.userID!;

  void _member(String id, String name) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      stateKey: id,
      senderId: id,
      content: {'membership': 'join', 'displayname': name},
    ),
  );

  Event event(
    String type,
    String sender,
    Map<String, Object?> content, {
    String? stateKey,
    Map<String, Object?>? prevContent,
    int minute = 0,
  }) => Event(
    content: content,
    type: type,
    eventId: '\$state${_next++}',
    senderId: sender,
    stateKey: stateKey,
    unsigned: prevContent == null ? null : {'prev_content': prevContent},
    originServerTs: DateTime(2026, 11, 27, 14, minute),
    room: room,
    status: EventStatus.synced,
  );

  /// The user accepting the invitation into the portal.
  Event ownAccepted({int minute = 0}) => event(
    EventTypes.RoomMember,
    own,
    {'membership': 'join', 'displayname': 'Grayson'},
    stateKey: own,
    prevContent: {'membership': 'invite'},
    minute: minute,
  );

  Event botInvitedGloria({int minute = 0}) => event(
    EventTypes.RoomMember,
    bot,
    {'membership': 'invite', 'displayname': 'Gloria'},
    stateKey: gloria,
    minute: minute,
  );

  Event gloriaAccepted({int minute = 0}) => event(
    EventTypes.RoomMember,
    gloria,
    {'membership': 'join', 'displayname': 'Gloria'},
    stateKey: gloria,
    prevContent: {'membership': 'invite'},
    minute: minute,
  );

  Event botRenamed({int minute = 0}) => event(
    EventTypes.RoomName,
    bot,
    {'name': 'Gloria'},
    stateKey: '',
    minute: minute,
  );

  Event botChangedAvatar({int minute = 0}) => event(
    EventTypes.RoomAvatar,
    bot,
    {'url': 'mxc://x/gloria'},
    stateKey: '',
    minute: minute,
  );

  Event gloriaRenamed({int minute = 0}) => event(
    EventTypes.RoomName,
    gloria,
    {'name': 'Dinner'},
    stateKey: '',
    minute: minute,
  );

  /// The bot removing Gloria, which is not housekeeping.
  Event botKickedGloria({int minute = 0}) => event(
    EventTypes.RoomMember,
    bot,
    {'membership': 'leave'},
    stateKey: gloria,
    prevContent: {'membership': 'join'},
    minute: minute,
  );

  Event message(String body, {int minute = 0}) => event(
    EventTypes.Message,
    gloria,
    {'msgtype': 'm.text', 'body': body},
    minute: minute,
  );
}
