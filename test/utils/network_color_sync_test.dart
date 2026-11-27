// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:ui';

import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../pages/chat_list/chat_list_fakes.dart';

/// Network colour picks follow the account: every device reads and writes
/// them in the account's data.
void main() {
  late FakeChatListClient client;
  const phoneBlue = Color(0xFF2196F3);
  const desktopBlue = Color(0xFF03A9F4);
  const type = NetworkColorSync.accountDataType;

  setUp(() async {
    client = await setUpFakeChatList('network color sync');
  });

  tearDown(() async {
    await NetworkColors.pick('imessage', null);
    await NetworkColors.pick('gmessages', null);
    tearDownFakeChatList(client);
  });

  Future<void> sync({Map<String, Object?>? colors}) async {
    if (colors != null) {
      client.accountData[type] = BasicEvent(
        type: type,
        content: {'colors': colors},
      );
    }
    client.onSync.add(
      SyncUpdate(
        nextBatch: 'next',
        accountData: [
          if (colors != null)
            BasicEvent(type: type, content: {'colors': colors}),
        ],
      ),
    );
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  test('a pick goes to the account', () async {
    await NetworkColors.pick('imessage', phoneBlue, client: client);
    expect(client.accountDataWrites, [type]);
    expect(NetworkColorSync.picksIn(client.accountData[type]?.content), {
      'imessage': phoneBlue.toARGB32(),
    });
  });

  test(
    'the account\'s picks replace this device\'s on the first sync',
    () async {
      await NetworkColors.pick('imessage', desktopBlue);
      final syncer = NetworkColorSync.attach(client);
      addTearDown(syncer.dispose);
      client.accountData[type] = BasicEvent(
        type: type,
        content: {
          'colors': {'imessage': phoneBlue.toARGB32()},
        },
      );
      await sync();
      expect(NetworkColors.colorFor('imessage'), phoneBlue);
      expect(client.accountDataWrites, isEmpty);
    },
  );

  test('a device with picks hands them to an account without any', () async {
    await NetworkColors.pick('gmessages', desktopBlue);
    final syncer = NetworkColorSync.attach(client);
    addTearDown(syncer.dispose);
    await sync();
    expect(NetworkColorSync.picksIn(client.accountData[type]?.content), {
      'gmessages': desktopBlue.toARGB32(),
    });
  });

  test('a pick made on another device arrives with a sync', () async {
    final syncer = NetworkColorSync.attach(client);
    addTearDown(syncer.dispose);
    await sync();
    await sync(colors: {'imessage': phoneBlue.toARGB32()});
    expect(NetworkColors.colorFor('imessage'), phoneBlue);
  });
}
