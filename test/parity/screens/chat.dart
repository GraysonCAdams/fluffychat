// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

/// The conversation fixtures (`chat-dm`, `chat-dm-linked`): the app's real
/// ChatPage over a direct chat, or over a merged contact whose rooms are
/// on several networks.
library;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/merged_contacts/model.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../harness.dart';

Future<void> pumpChatScreen(WidgetTester tester, ParityFixture fixture) async {
  setUpParityView(tester, fixture);
  final screen = fixture.screenData;
  final prefs = await setUpParitySettings(fixture);
  final composer = screen['composer'] as Map? ?? {};
  await AppSettings.voiceMessages.setItem(composer['mic'] as bool? ?? true);
  final client = (await tester.runAsync(
    () => ParityClient.create('parity ${fixture.screen}'),
  ))!;

  final partnerData = screen['with'] as Map;
  final name = partnerData['name'] as String;
  final picture = partnerData['picture'] == true;
  final networks = (screen['networks'] as List).cast<String>();
  final linked = screen['linked'] == true;
  final sendVia = screen['sendVia'] as String? ?? networks.first;

  // One direct chat per network, each in its bridge's space.
  final rooms = <String, ParityRoom>{};
  final partners = <String, String>{};
  for (final network in networks) {
    final id = '!$network-${slug(name)}:$homeserver';
    final partner = '@${network}_${slug(name)}:$homeserver';
    partners[network] = partner;
    final room = rooms[network] = ParityRoom(id: id, client: client);
    final member = {
      'membership': 'join',
      'displayname': name,
      if (picture) 'avatar_url': '$flatPicture',
    };
    setRoomState(
      room,
      EventTypes.RoomMember,
      member,
      stateKey: partner,
      sender: partner,
    );
    setRoomState(room, EventTypes.RoomMember, {
      'membership': 'join',
      'displayname': 'Robin',
    }, stateKey: ownUserId);
    setRoomState(room, EventTypes.RoomName, {'name': name}, sender: partner);
    if (picture) {
      setRoomState(room, EventTypes.RoomAvatar, {
        'url': '$flatPicture',
      }, sender: partner);
    }
    client.rooms.add(room);
    markDirect(client, partner, id);
    // The bridge's space carries the network's logo as its picture, which
    // shows here as a flat disc like every picture.
    final space = addNetworkSpace(
      client,
      network,
      fixture.networkNames[network]!,
      [id],
    );
    setRoomState(space, EventTypes.RoomAvatar, {'url': '$flatPicture'});
  }

  // The timeline, a minute apart so no date separator splits it.
  final items = (screen['items'] as List).cast<Map>();
  var time = DateTime.now().subtract(Duration(minutes: items.length + 5));
  var n = 0;
  Event add(
    String network,
    String type,
    Map<String, Object?> content, {
    required String sender,
    String? stateKey,
    Map<String, Object?>? unsigned,
  }) {
    final room = rooms[network]!;
    time = time.add(const Duration(minutes: 1));
    final event = Event(
      content: content,
      type: type,
      eventId: '\$e${n++}-${room.id.hashCode}',
      senderId: sender,
      originServerTs: time,
      stateKey: stateKey,
      unsigned: unsigned,
      room: room,
    );
    room.events.add(event);
    room.lastEvent = event;
    return event;
  }

  for (final item in items) {
    final network = item['via'] as String? ?? sendVia;
    final partner = partners[network]!;
    final out = item['kind'] == 'out' || item['dir'] == 'out';
    final sender = out ? ownUserId : partner;
    switch (item['kind']) {
      case 'in' || 'out':
        add(network, EventTypes.Message, {
          'msgtype': MessageTypes.Text,
          'body': item['text'],
        }, sender: sender);
      case 'image':
        // The photo is a flat picture of the size the fixture gives.
        final w = (item['w'] as num).round();
        final h = (item['h'] as num).round();
        final content = {
          'msgtype': MessageTypes.Image,
          'body': 'photo.jpg',
          'url': 'mxc://$homeserver/flat-${w}x$h',
          'info': {'w': w, 'h': h, 'mimetype': 'image/png'},
        };
        final image = add(network, EventTypes.Message, content, sender: sender);
        if (item['edited'] == true) {
          add(network, EventTypes.Message, {
            ...content,
            'body': ' * photo.jpg',
            'm.new_content': content,
            'm.relates_to': {
              'rel_type': RelationshipTypes.edit,
              'event_id': image.eventId,
            },
          }, sender: sender);
        }
      case 'state':
        // An avatar change, with a second one folded under "More events"
        // when the fixture shows that link.
        final changes = item['more'] == true ? 2 : 1;
        for (var i = 0; i < changes; i++) {
          add(
            network,
            EventTypes.RoomMember,
            {
              'membership': 'join',
              'displayname': name,
              'avatar_url': 'mxc://$homeserver/avatar$i',
            },
            sender: partner,
            stateKey: partner,
            unsigned: {
              'prev_content': {
                'membership': 'join',
                'displayname': name,
                'avatar_url': 'mxc://$homeserver/avatar${i + 1}',
              },
            },
          );
        }
      default:
        throw ArgumentError('Unknown chat item ${item['kind']}');
    }
  }

  for (final room in rooms.values) {
    markRead(room);
  }

  String location;
  if (linked) {
    setMergedContacts(client, {
      'parity': {
        'rooms': [for (final room in rooms.values) room.id],
        'send_via': rooms[sendVia]!.id,
        'updated': 1,
      },
    });
    location = '/rooms/contact/parity';
  } else {
    location = '/rooms/${rooms[sendVia]!.id}';
  }

  addTearDown(() {
    MergeSuggestionService.disposeFor(client);
    MergedContactsStore.disposeFor(client);
  });

  await pumpParityApp(
    tester,
    client: client,
    prefs: prefs,
    initialLocation: location,
    routes: [
      GoRoute(
        path: '/rooms',
        builder: (context, state) => const SizedBox.shrink(),
        routes: [
          GoRoute(
            path: 'contact/:contactid',
            builder: (context, state) => ChatPage(
              roomId: '',
              contactId: state.pathParameters['contactid'],
            ),
          ),
          GoRoute(
            path: ':roomid',
            builder: (context, state) =>
                ChatPage(roomId: state.pathParameters['roomid']!),
          ),
        ],
      ),
    ],
  );
  await settleParity(tester);
  await expectParityGolden(tester, fixture);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}

/// Stores [contacts] as the account's merged contacts event.
void setMergedContacts(Client client, Map<String, Object?> contacts) {
  client.accountData[MergedContactsData.accountDataType] = BasicEvent(
    type: MergedContactsData.accountDataType,
    content: {'version': 1, 'contacts': contacts},
  );
}
