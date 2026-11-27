// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_details_network_sheet.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/merged_contacts/fake_rooms.dart';

/// Stands in for the app's Matrix widget, which widgets only ask for its
/// client.
class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

/// The chat screen: keeps state that going to details and back must not
/// lose, and opens the details of [room] (merged when [contact] is set).
class _Chat extends StatefulWidget {
  final Room room;
  final MergedContact? contact;

  const _Chat({required this.room, this.contact, super.key});

  @override
  State<_Chat> createState() => _ChatState();
}

class _ChatState extends State<_Chat> {
  int columnToggles = 0;

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: TextButton(
        onPressed: () => openChatDetails(
          context,
          room: widget.room,
          mergedContact: widget.contact,
          toggleDetailsColumn: () => setState(() => columnToggles++),
        ),
        child: const Text('title'),
      ),
    ),
  );
}

void main() {
  late Client client;
  late Room imessage;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await fakeMergedClient();
    imessage = addDirectChat(
      client,
      id: '!imsg:x',
      partner: '@imessage_tel=3a+14045551234:x',
      name: 'Harrison Young',
    );
    addDirectChat(
      client,
      id: '!sms:x',
      partner: '@gmessages_1.2:x',
      name: 'Harrison',
    );
    addDirectChat(
      client,
      id: '!tg:x',
      partner: '@telegram_42:x',
      name: 'Harry Y',
    );
    setMergedContacts(client, {
      'c_1': {
        'rooms': ['!imsg:x', '!sms:x', '!tg:x'],
        'send_via': '!imsg:x',
        'updated': 1,
      },
    });
  });

  tearDown(() => MergedContactsStore.disposeFor(client));

  Future<GoRouter> pumpChat(WidgetTester tester, Widget chat) async {
    final router = GoRouter(
      routes: [
        GoRoute(path: '/', builder: (context, state) => chat),
        GoRoute(
          path: '/rooms/:roomid/details',
          builder: (context, state) => Scaffold(
            body: Text('details of ${state.pathParameters['roomid']}'),
          ),
        ),
      ],
    );
    addTearDown(router.dispose);
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrix(client),
        child: MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    // Localizations load asynchronously before the first real frame.
    await tester.pumpAndSettle();
    return router;
  }

  testWidgets('a merged chat asks which network, then offers linked chats', (
    tester,
  ) async {
    final contact = MergedContact.ofRoom(client, '!imsg:x')!;
    await pumpChat(tester, _Chat(room: imessage, contact: contact));

    await tester.tap(find.text('title'));
    await tester.pumpAndSettle();

    expect(find.text('Chat details'), findsOneWidget);
    expect(find.text('Choose a network'), findsOneWidget);
    final sheet = find.byType(ChatDetailsNetworkSheet);
    // One row per network, named after the network, plus Linked chats.
    for (final network in ['Imessage', 'Gmessages', 'Telegram']) {
      expect(
        find.descendant(of: sheet, matching: find.text(network)),
        findsOneWidget,
      );
    }
    expect(find.byIcon(Icons.chevron_right), findsNWidgets(4));
    // The iMessage ghost carries the number, shown in place of the name.
    expect(find.text('+1 404 555 1234'), findsOneWidget);
    expect(find.text('Harry Y'), findsOneWidget);
    expect(find.text('Linked chats'), findsOneWidget);
    expect(find.text('Add, remove or unlink'), findsOneWidget);
    expect(find.byIcon(Icons.link), findsOneWidget);
  });

  group('threads on one network', () {
    /// A second iMessage thread with the same person, newer than the first.
    Room addSecondThread() => addDirectChat(
      client,
      id: '!imsg2:x',
      partner: '@imessage_tel=3a+14045551234:x',
      name: 'Harrison Young',
      lastMessage: 'newer',
      lastMessageTime: DateTime(2026, 11, 26),
    );

    Future<void> openSheet(WidgetTester tester, List<String> rooms) async {
      setMergedContacts(client, {
        'c_2': {'rooms': rooms, 'send_via': '!imsg2:x', 'updated': 2},
      });
      MergedContactsStore.disposeFor(client);
      final contact = MergedContact.ofRoom(client, '!imsg2:x')!;
      await pumpChat(tester, _Chat(room: imessage, contact: contact));
      await tester.tap(find.text('title'));
      await tester.pumpAndSettle();
    }

    final sheet = find.byType(ChatDetailsNetworkSheet);
    Finder inSheet(String text) =>
        find.descendant(of: sheet, matching: find.text(text));

    testWidgets('are one row, opening the thread messages go to', (
      tester,
    ) async {
      addSecondThread();
      await openSheet(tester, ['!imsg:x', '!imsg2:x']);
      expect(inSheet('Imessage'), findsOneWidget);
      expect(inSheet('2 threads combined'), findsOneWidget);
      await tester.tap(inSheet('Imessage'));
      await tester.pumpAndSettle();
      expect(find.text('details of !imsg2:x'), findsOneWidget);
    });

    testWidgets('beside another network keep a row per network', (
      tester,
    ) async {
      addSecondThread();
      await openSheet(tester, ['!imsg:x', '!imsg2:x', '!sms:x']);
      expect(inSheet('Imessage'), findsOneWidget);
      expect(inSheet('Gmessages'), findsOneWidget);
      expect(find.byIcon(Icons.chevron_right), findsNWidgets(3));
    });
  });

  testWidgets('a single chat goes straight to its details', (tester) async {
    final router = await pumpChat(tester, _Chat(room: imessage));

    await tester.tap(find.text('title'));
    await tester.pumpAndSettle();

    expect(find.byType(ChatDetailsNetworkSheet), findsNothing);
    expect(find.text('Choose a network'), findsNothing);
    expect(find.text('details of !imsg:x'), findsOneWidget);
    expect(
      router.routerDelegate.currentConfiguration.uri.path,
      '/rooms/!imsg:x/details',
    );
  });

  testWidgets(
    'picking a network opens its details over the merged chat and keeps '
    'the send-via network',
    (tester) async {
      final contact = MergedContact.ofRoom(client, '!imsg:x')!;
      final router = await pumpChat(
        tester,
        _Chat(key: const Key('chat'), room: imessage, contact: contact),
      );
      final chatState = tester.state<_ChatState>(find.byKey(const Key('chat')));

      await tester.tap(find.text('title'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Telegram'));
      await tester.pumpAndSettle();

      expect(find.text('details of !tg:x'), findsOneWidget);
      expect(
        MergedContactsStore.forClient(client).contactById('c_1')!.sendVia,
        '!imsg:x',
      );

      // Back lands on the same merged chat, not a rebuilt single chat.
      expect(router.canPop(), isTrue);
      router.pop();
      await tester.pumpAndSettle();
      expect(find.text('title'), findsOneWidget);
      expect(
        tester.state<_ChatState>(find.byKey(const Key('chat'))),
        same(chatState),
      );
      expect(router.routerDelegate.currentConfiguration.uri.path, '/');
      expect(
        MergedContactsStore.forClient(client).contactById('c_1')!.sendVia,
        '!imsg:x',
      );
    },
  );
}
