// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/utils/merged_contacts/model.dart';
import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A client that is never logged in, with rooms and account data set by
/// hand. Enough for code that reads rooms (names, last events, counts) and
/// the merged contacts store, without the network or the encryption library.
Future<Client> fakeMergedClient() async {
  sqfliteFfiInit();
  final client = Client(
    'merged contacts test',
    database: await MatrixSdkDatabase.init(
      'merged contacts test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );
  return client;
}

const ownUserId = '@me:example.org';

/// Adds a joined direct chat with [partner] named [name] to [client].
Room addDirectChat(
  Client client, {
  required String id,
  required String partner,
  required String name,
  int notificationCount = 0,
  int highlightCount = 0,
  bool favourite = false,
  String? lastMessage,
  DateTime? lastMessageTime,
  String? lastSender,
}) {
  final room = Room(
    id: id,
    client: client,
    notificationCount: notificationCount,
    highlightCount: highlightCount,
  );
  room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomName,
      content: {'name': name},
      senderId: partner,
      stateKey: '',
    ),
  );
  // The partner's member event, so nothing looks the sender up remotely.
  room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': name},
      senderId: partner,
      stateKey: partner,
    ),
  );
  if (favourite) {
    room.roomAccountData['m.tag'] = BasicEvent(
      type: 'm.tag',
      content: {
        'tags': {'m.favourite': {}},
      },
    );
  }
  if (lastMessage != null) {
    room.lastEvent = Event(
      content: {'msgtype': 'm.text', 'body': lastMessage},
      type: EventTypes.Message,
      eventId: '\$$id-last',
      senderId: lastSender ?? partner,
      originServerTs: lastMessageTime ?? DateTime(2026),
      room: room,
    );
  }
  client.rooms.add(room);
  final direct = Map<String, Object?>.from(
    client.accountData['m.direct']?.content ?? {},
  );
  direct[partner] = [...?(direct[partner] as List?), id];
  client.accountData['m.direct'] = BasicEvent(
    type: 'm.direct',
    content: direct,
  );
  return room;
}

/// Stores [data] as the account's merged contacts event.
void setMergedContacts(Client client, Map<String, Object?> contacts) {
  client.accountData[MergedContactsData.accountDataType] = BasicEvent(
    type: MergedContactsData.accountDataType,
    content: {'version': 1, 'contacts': contacts},
  );
}
