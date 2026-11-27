// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: deprecated_member_use

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../utils/merged_contacts/fake_rooms.dart';

/// A client that records the read markers it is asked to set instead of
/// sending them.
class _ReceiptClient extends Client {
  _ReceiptClient(super.clientName, {required super.database});

  /// `room fully_read m.read` for each read marker set.
  final readMarkers = <String>[];

  @override
  Future<void> setReadMarker(
    String roomId, {
    String? mFullyRead,
    String? mRead,
    String? mReadPrivate,
  }) async => readMarkers.add('$roomId $mFullyRead ${mRead ?? mReadPrivate}');
}

Future<_ReceiptClient> _receiptClient() async {
  sqfliteFfiInit();
  return _ReceiptClient(
    'one time code test',
    database: await MatrixSdkDatabase.init(
      'one time code test',
      database: await databaseFactoryFfi.openDatabase(':memory:'),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );
}

/// Stands in for the app's Matrix widget, which widgets only ask for its
/// client.
class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

Widget _app(Client client, Widget child) => Provider<MatrixState>.value(
  value: _FakeMatrix(client),
  child: MaterialApp(
    localizationsDelegates: L10n.localizationsDelegates,
    supportedLocales: L10n.supportedLocales,
    home: Scaffold(body: ListView(children: [child])),
  ),
);

const _otp = 'Your verification code is 282295';

void main() {
  late _ReceiptClient client;
  String? clipboard;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await _receiptClient();
    clipboard = null;
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    MergedContactsStore.disposeFor(client);
  });

  Room chat({
    required String message,
    int unread = 1,
    String id = '!a:x',
    DateTime? time,
  }) {
    // A known presence, so the avatar does not fetch one.
    client.presences['@bank:x'] = CachedPresence.neverSeen('@bank:x');
    return addDirectChat(
      client,
      id: id,
      partner: '@bank:x',
      name: 'Bank',
      notificationCount: unread,
      lastMessage: message,
      lastMessageTime: time,
    );
  }

  group('chatListOneTimeCode', () {
    test('an unread code from someone else is offered', () {
      expect(chatListOneTimeCode(chat(message: _otp))?.code, '282295');
    });

    test('a read chat offers nothing', () {
      expect(chatListOneTimeCode(chat(message: _otp, unread: 0)), isNull);
    });

    test('a message without a code offers nothing', () {
      expect(chatListOneTimeCode(chat(message: 'See you at 1830')), isNull);
    });

    test('an image whose caption has a code offers nothing', () {
      final room = chat(message: _otp);
      room.lastEvent = Event(
        content: {'msgtype': MessageTypes.Image, 'body': _otp},
        type: EventTypes.Message,
        eventId: r'$image',
        senderId: '@bank:x',
        originServerTs: DateTime(2026),
        room: room,
      );
      expect(chatListOneTimeCode(room), isNull);
    });

    test('a code sent with invisible ink offers nothing', () {
      final room = chat(message: _otp);
      room.lastEvent = Event(
        content: {
          'msgtype': MessageTypes.Text,
          'body': _otp,
          messageEffectKey: MessageEffect.invisibleInk.id,
        },
        type: EventTypes.Message,
        eventId: r'$ink',
        senderId: '@bank:x',
        originServerTs: DateTime(2026),
        room: room,
      );
      expect(chatListOneTimeCode(room), isNull);
    });
  });

  testWidgets('the pill copies the code without opening the chat', (
    tester,
  ) async {
    var opened = 0;
    await tester.pumpWidget(
      _app(client, ChatListItem(chat(message: _otp), onTap: () => opened++)),
    );
    await tester.pumpAndSettle();

    final pill = find.text('Copy "282295"');
    expect(pill, findsOneWidget);
    expect(find.byIcon(Icons.copy_outlined), findsOneWidget);
    await tester.tap(pill);
    await tester.pumpAndSettle();
    expect(clipboard, '282295');
    expect(opened, 0);
    // The code was read: the chat is marked read up to that message.
    expect(client.readMarkers, [r'!a:x $!a:x-last $!a:x-last']);

    // The row itself still opens the chat.
    await tester.tap(find.text('Bank'));
    expect(opened, 1);
  });

  testWidgets('the avatar stays level with the name in a taller row', (
    tester,
  ) async {
    await tester.pumpWidget(
      _app(
        client,
        Column(
          children: [
            ChatListItem(
              chat(message: _otp),
              key: const ValueKey('code'),
              onTap: () {},
            ),
            ChatListItem(
              chat(message: 'Your statement is ready', id: '!b:x'),
              key: const ValueKey('plain'),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    Rect avatarIn(String key) => tester.getRect(
      find
          .descendant(
            of: find.byKey(ValueKey(key)),
            matching: find.byType(Avatar),
          )
          .first,
    );
    final codeRow = tester.getRect(find.byKey(const ValueKey('code')));
    final plainRow = tester.getRect(find.byKey(const ValueKey('plain')));
    // 3dp outside the highlight, then 16dp to the avatar in the tall row.
    expect(avatarIn('code').top - codeRow.top, 3 + 16);
    // A two-line row centres its avatar.
    expect(avatarIn('plain').center.dy, plainRow.center.dy);
  });

  testWidgets('the pill adds oneTimeCodeHeight to the row', (tester) async {
    await tester.pumpWidget(
      _app(
        client,
        Column(
          children: [
            ChatListItem(
              chat(message: _otp),
              key: const ValueKey('code'),
              onTap: () {},
            ),
            ChatListItem(
              chat(message: 'Your statement is ready', id: '!b:x'),
              key: const ValueKey('plain'),
              onTap: () {},
            ),
          ],
        ),
      ),
    );
    await tester.pumpAndSettle();
    final withCode = tester.getSize(find.byKey(const ValueKey('code'))).height;
    final without = tester.getSize(find.byKey(const ValueKey('plain'))).height;
    expect(withCode - without, ChatListItem.oneTimeCodeHeight);
  });

  testWidgets('in a merged contact the pill marks the room the code came '
      'in, not the others', (tester) async {
    final email = chat(
      message: 'Your statement is ready',
      id: '!email:x',
      time: DateTime(2026, 1, 1),
    );
    chat(message: _otp, id: '!sms:x', time: DateTime(2026, 1, 2));
    setMergedContacts(client, {
      'c_bank': {
        'rooms': ['!email:x', '!sms:x'],
        'send_via': '!email:x',
        'updated': 1,
      },
    });
    final contact = MergedContact.ofRoom(client, '!sms:x')!;
    await tester.pumpWidget(
      _app(client, ChatListItem(email, contact: contact, onTap: () {})),
    );
    await tester.pumpAndSettle();

    await tester.tap(find.text('Copy "282295"'));
    await tester.pumpAndSettle();
    expect(clipboard, '282295');
    expect(client.readMarkers, [r'!sms:x $!sms:x-last $!sms:x-last']);
  });
}
