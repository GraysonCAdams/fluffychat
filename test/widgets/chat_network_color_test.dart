// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';
import '../utils/merged_contacts/fake_rooms.dart' show setMergedContacts;

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

/// A bridged chat that is not part of a merged contact takes the colour
/// picked for its network, as a merged contact's chat does: the user's own
/// bubbles and the send button. A plain Matrix chat keeps the theme's.
void main() {
  late FakeChatListClient client;

  /// The iMessage blue picked on the phone in the report.
  const picked = Color(0xFF2196F3);

  setUp(() async {
    client = await setUpFakeChatList('chat network color');
    await NetworkColors.pick('imessage', picked);
    // The chat page keeps the screen on while it is open.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() async {
    await NetworkColors.pick('imessage', null);
    tearDownFakeChatList(client);
  });

  /// Opens [room] with one message of the user's own in it, and returns
  /// the colours of that message's bubble and of the send button.
  Future<({Color? bubble, Color? send, ThemeData theme})> open(
    WidgetTester tester,
    Room room, {
    String? contactId,
  }) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('chat list')),
          routes: [
            GoRoute(
              path: 'chat',
              builder: (_, _) =>
                  ChatPage(roomId: room.id, contactId: contactId),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _Matrix(client, prefs),
        child: MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/chat');
    Future<void> settle() async {
      for (var i = 0; i < 5; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    await settle();
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'b1',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [
                    MatrixEvent(
                      type: EventTypes.Message,
                      content: {'msgtype': 'm.text', 'body': 'Waffle House?'},
                      senderId: client.userID!,
                      eventId: '\$waffle',
                      originServerTs: DateTime(2026, 11, 27, 10),
                    ),
                  ],
                ),
              ),
            },
          ),
        ),
      ),
    );
    await settle();

    final message = tester.widget<Message>(
      find.ancestor(
        of: find.text('Waffle House?'),
        matching: find.byType(Message),
      ),
    );
    final send = tester.widget<IconButton>(
      find.byKey(const Key('send_button')),
    );
    return (
      bubble: message.networkColor,
      send: send.style?.backgroundColor?.resolve({}),
      theme: Theme.of(tester.element(find.byType(Message))),
    );
  }

  testWidgets('an iMessage group that is not merged takes the iMessage '
      'colour', (tester) async {
    final group = addFakeChat(
      client,
      '!grp:x',
      'Drew Andersen, Harrison Young',
    );
    addFakeBridge(group);

    final colors = await open(tester, group);
    expect(colors.bubble, picked);
    expect(colors.send, picked);
  });

  testWidgets('a one-to-one iMessage chat that is not merged takes the '
      'iMessage colour', (tester) async {
    final chat = addFakeChat(
      client,
      '!parla:x',
      'Parla Hoelter',
      partner: '@imessage_tel=3a+15555550123:x',
    );
    addFakeBridge(chat);

    final colors = await open(tester, chat);
    expect(colors.bubble, picked);
    expect(colors.send, picked);
  });

  testWidgets('a plain Matrix room keeps the theme colour', (tester) async {
    final group = addFakeChat(client, '!plain:x', 'Book club');

    final colors = await open(tester, group);
    expect(colors.bubble, isNull);
    expect(colors.send, colors.theme.bubbleColor);
  });

  group('a group merged across iMessage and Google Messages', () {
    late Room imessage;
    late Room gmessages;

    setUp(() {
      imessage = addFakeChat(
        client,
        '!grp-im:x',
        'Drew Andersen, Harrison Young',
      );
      gmessages = addFakeChat(
        client,
        '!grp-gm:x',
        'Drew Andersen, Harrison Young',
      );
      addFakeBridge(imessage);
      addFakeBridge(
        gmessages,
        bot: '@gmessagesbot:x',
        network: 'Google Messages',
      );
      setMergedContacts(client, {
        'c_grp': {
          'rooms': [imessage.id, gmessages.id],
          'send_via': imessage.id,
          'updated': 1,
        },
      });
    });

    testWidgets('a message on iMessage and the send button take the '
        'iMessage colour', (tester) async {
      final colors = await open(tester, imessage, contactId: 'c_grp');
      expect(colors.bubble, picked);
      expect(colors.send, picked);
    });

    testWidgets('sending via Google Messages turns the send button its '
        'colour', (tester) async {
      await open(tester, imessage, contactId: 'c_grp');
      final chat = tester.state<ChatController>(find.byType(ChatPageWithRoom));
      await tester.runAsync(() => chat.setMergedSendVia(gmessages.id));
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      final send = tester.widget<IconButton>(
        find.byKey(const Key('send_button')),
      );
      expect(
        send.style?.backgroundColor?.resolve({}),
        NetworkColors.defaults['gmessages'],
      );
    });

    test('its badge in the chat list rings in both networks\' colours', () {
      final contact = MergedContact.ofRoom(client, imessage.id)!;
      expect(
        MergedBadge(
          contact: contact,
          size: 24,
          outlineColor: Colors.black,
        ).ringColors,
        [picked, NetworkColors.defaults['gmessages']],
      );
    });
  });
}
