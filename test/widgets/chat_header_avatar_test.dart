// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_app_bar_title.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/merged_contacts/fake_rooms.dart';

class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

void main() {
  late Client client;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await fakeMergedClient();
  });

  tearDown(() => MergedContactsStore.disposeFor(client));

  /// A group without a picture, with Drew and Harrison in it.
  Room addGroup(String id) {
    final room = Room(id: id, client: client);
    for (final (userId, name) in [
      ('@imessage_drew:x', 'Drew Andersen'),
      ('@imessage_harrison:x', 'Harrison Young'),
    ]) {
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          content: {'membership': 'join', 'displayname': name},
          senderId: userId,
          stateKey: userId,
        ),
      );
    }
    client.rooms.add(room);
    return room;
  }

  testWidgets('a merged group without a picture shows its members', (
    tester,
  ) async {
    final room = addGroup('!a:x');
    addGroup('!b:x');
    setMergedContacts(client, {
      'c_1': {
        'rooms': ['!a:x', '!b:x'],
        'send_via': '!a:x',
        'updated': 1,
      },
    });
    final contact = MergedContact.ofRoom(client, room.id)!;
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrix(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ChatHeaderAvatar(
              room: room,
              contact: contact,
              name: 'Drew Andersen, Harrison Young',
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.byType(GroupAvatar), findsOneWidget);
  });
}
