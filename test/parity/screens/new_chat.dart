// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

/// The new chat fixtures (`new-chat`, `new-chat-results`): the app's real
/// NewPrivateChat page, with the fixture's results as existing chats.
library;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../harness.dart';
import 'chat.dart' show setMergedContacts;

/// Sources as on the reference phone: no bridge contact lists, and the
/// phone's contacts not yet allowed, so the page offers them.
class _ParityDelivery extends NewChatDelivery {
  final bool offerContacts;

  const _ParityDelivery({required this.offerContacts});

  @override
  Future<void> loadSources(Client client, NewChatSources sources) async {
    sources.offerPhoneContacts = offerContacts;
    sources.onChanged();
  }
}

Future<void> pumpNewChatScreen(
  WidgetTester tester,
  ParityFixture fixture,
) async {
  setUpParityView(tester, fixture);
  final screen = fixture.screenData;
  final prefs = await setUpParitySettings(fixture);
  await AppSettings.suggestContactsFromChats.setItem(true);
  final client = (await tester.runAsync(
    () => ParityClient.create('parity ${fixture.screen}'),
  ))!;
  final query = screen['query'] as String? ?? '';

  // Each result is an existing chat; one on several networks is a merged
  // contact with a room per network, as the app lists them.
  final results = (screen['results'] as List? ?? []).cast<Map>();
  final spaces = <String, List<String>>{};
  final contacts = <String, Object?>{};
  final start = DateTime.now().subtract(const Duration(days: 2));
  for (final (i, result) in results.indexed) {
    final name = result['name'] as String;
    final networks = (result['networks'] as List).cast<String>();
    final roomIds = <String>[];
    for (final network in networks) {
      // A result whose name does not hold the query was found by its
      // bridge user ID, so that ID holds it.
      final idPart = name.toLowerCase().contains(query.toLowerCase())
          ? slug(name)
          : '${slug(name)}.$query';
      final partner = '@${network}_$idPart:$homeserver';
      final id = '!$network-${slug(name)}:$homeserver';
      final room = ParityRoom(id: id, client: client);
      setRoomState(
        room,
        EventTypes.RoomMember,
        {'membership': 'join', 'displayname': name},
        stateKey: partner,
        sender: partner,
      );
      setRoomState(room, EventTypes.RoomName, {'name': name}, sender: partner);
      if (result['picture'] == true) {
        setRoomState(room, EventTypes.RoomAvatar, {
          'url': '$flatPicture',
        }, sender: partner);
      }
      room.lastEvent = Event(
        content: {'msgtype': MessageTypes.Text, 'body': 'See you then'},
        type: EventTypes.Message,
        eventId: '\$last-$id',
        senderId: partner,
        originServerTs: start.subtract(Duration(minutes: i)),
        room: room,
      );
      markRead(room);
      client.rooms.add(room);
      markDirect(client, partner, id);
      (spaces[network] ??= []).add(id);
      roomIds.add(id);
    }
    if (roomIds.length > 1) {
      contacts['c$i'] = {
        'rooms': roomIds,
        'send_via': roomIds.first,
        'updated': 1,
      };
    }
  }
  for (final MapEntry(key: network, value: children) in spaces.entries) {
    final space = addNetworkSpace(
      client,
      network,
      fixture.networkNames[network]!,
      children,
    );
    setRoomState(space, EventTypes.RoomAvatar, {'url': '$flatPicture'});
  }
  if (contacts.isNotEmpty) setMergedContacts(client, contacts);

  addTearDown(() {
    MergeSuggestionService.disposeFor(client);
    MergedContactsStore.disposeFor(client);
  });

  final delivery = _ParityDelivery(
    offerContacts: screen['contactsPrompt'] == true,
  );
  await pumpParityApp(
    tester,
    client: client,
    prefs: prefs,
    initialLocation: '/rooms/newprivatechat',
    routes: [
      GoRoute(
        path: '/rooms',
        builder: (context, state) => const SizedBox.shrink(),
        routes: [
          GoRoute(
            path: 'newprivatechat',
            builder: (context, state) =>
                NewPrivateChat(deeplink: null, delivery: delivery),
          ),
        ],
      ),
    ],
  );
  await settleParity(tester);
  if (query.isNotEmpty) {
    await tester.enterText(find.byType(TextField), query);
    await tester.pump(const Duration(seconds: 1));
    // The phone showed no cursor: the keyboard was down.
    FocusManager.instance.primaryFocus?.unfocus();
    await settleParity(tester);
  }
  await expectParityGolden(tester, fixture);
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 5));
}
