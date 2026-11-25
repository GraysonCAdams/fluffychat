// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages, deprecated_member_use

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/gestures.dart' show kSecondaryButton;
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../../utils/merged_contacts/fake_rooms.dart' show setMergedContacts;

/// A client that is never logged in but looks synced, and keeps account
/// data writes (the merged contacts) locally.
class _FakeClient extends Client {
  _FakeClient(super.clientName, {required super.database});

  final accountDataWrites = <String>[];

  @override
  String? get userID => '@me:x';

  @override
  String? get prevBatch => 'synced';

  @override
  Future<void> setAccountData(
    String userId,
    String type,
    Map<String, Object?> body,
  ) async {
    accountDataWrites.add(type);
    accountData[type] = BasicEvent(type: type, content: body);
  }
}

/// A room that records the changes asked of it instead of sending them.
class _FakeRoom extends Room {
  _FakeRoom({
    required super.id,
    required super.client,
    super.notificationCount,
  });

  final calls = <String>[];

  @override
  Future<void> setFavourite(bool favourite) async =>
      calls.add('favourite:$favourite');

  @override
  Future<void> setLowPriority(bool lowPriority) async =>
      calls.add('lowPriority:$lowPriority');

  @override
  Future<void> setPushRuleState(PushRuleState newState) async =>
      calls.add('push:${newState.name}');

  @override
  Future<void> markUnread(bool unread) async => calls.add('unread:$unread');

  @override
  Future<void> setReadMarker(
    String? eventId, {
    String? mRead,
    bool? public,
  }) async => calls.add('read');

  @override
  Future<void> leave({bool waitForSync = false}) async => calls.add('leave');
}

/// Stands in for the app's Matrix widget with one client and no bundles.
class _FakeMatrix extends MatrixState {
  final Client fakeClient;
  final SharedPreferences prefs;

  _FakeMatrix(this.fakeClient, this.prefs);

  @override
  Client get client => fakeClient;

  @override
  SharedPreferences get store => prefs;

  @override
  bool get hasComplexBundles => false;

  @override
  Map<String?, List<Client?>> get accountBundles => {
    null: [fakeClient],
  };

  @override
  List<Client?>? get currentBundle => [fakeClient];
}

void main() {
  late _FakeClient client;
  late SharedPreferences prefs;
  late Map<String, _FakeRoom> rooms;

  Room space(String id, String name, List<String> children) {
    final space = Room(id: id, client: client);
    space.setState(
      StrippedStateEvent(
        type: EventTypes.RoomCreate,
        content: {'type': RoomCreationTypes.mSpace},
        senderId: '@bridge:x',
        stateKey: '',
      ),
    );
    space.setState(
      StrippedStateEvent(
        type: EventTypes.RoomName,
        content: {'name': name},
        senderId: '@bridge:x',
        stateKey: '',
      ),
    );
    for (final child in children) {
      space.setState(
        StrippedStateEvent(
          type: EventTypes.SpaceChild,
          content: {
            'via': ['x'],
          },
          senderId: '@bridge:x',
          stateKey: child,
        ),
      );
    }
    client.rooms.add(space);
    return space;
  }

  /// A joined chat named [name]; one-to-one with [partner] when given,
  /// else a group.
  _FakeRoom chat(
    String id,
    String name, {
    String? partner,
    int notificationCount = 0,
    DateTime? lastMessageTime,
  }) {
    final room = _FakeRoom(
      id: id,
      client: client,
      notificationCount: notificationCount,
    );
    final sender = partner ?? '@someone:x';
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomName,
        content: {'name': name},
        senderId: sender,
        stateKey: '',
      ),
    );
    room.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        content: {'membership': 'join', 'displayname': name},
        senderId: sender,
        stateKey: sender,
      ),
    );
    room.lastEvent = Event(
      content: {'msgtype': 'm.text', 'body': 'hello from $name'},
      type: EventTypes.Message,
      eventId: '\$$id-last',
      senderId: sender,
      originServerTs: lastMessageTime ?? DateTime(2026),
      room: room,
    );
    client.rooms.add(room);
    if (partner != null) {
      // Known presence, so the avatar does not read it from the database.
      client.presences[partner] = CachedPresence.neverSeen(partner);
      final direct = Map<String, Object?>.from(
        client.accountData['m.direct']?.content ?? {},
      );
      direct[partner] = [...?(direct[partner] as List?), id];
      client.accountData['m.direct'] = BasicEvent(
        type: 'm.direct',
        content: direct,
      );
    }
    rooms[id] = room;
    return room;
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    prefs = await SharedPreferences.getInstance();
    await AppSettings.checkForUpdates.setItem(false);
    await AppSettings.mergedContactSuggestions.setItem(false);
    await AppSettings.mergedContactsPhoneRegion.setItem('US');

    sqfliteFfiInit();
    client = _FakeClient(
      'chat list selection test',
      database: await MatrixSdkDatabase.init(
        'chat list selection test',
        database: await databaseFactoryFfi.openDatabase(':memory:'),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    // Looks synced to the header, which otherwise shows a spinner.
    client.onSync.add(SyncUpdate(nextBatch: 'synced'));
    rooms = {};
    // Harrison on iMessage and twice on SMS (one number, two chats), and
    // a group of the same name on iMessage and Telegram.
    chat(
      '!imsg:x',
      'Harrison Young',
      partner: '@imessage_tel=3a+14045551234:x',
      lastMessageTime: DateTime(2026, 1, 5),
    );
    chat(
      '!sms:x',
      '(404) 555-1234',
      partner: '@gmessages_1.1:x',
      lastMessageTime: DateTime(2026, 1, 4),
    );
    chat(
      '!sms2:x',
      '+1 404-555-1234',
      partner: '@gmessages_1.2:x',
      lastMessageTime: DateTime(2026, 1, 3),
    );
    chat('!grp-imsg:x', 'Squad Goals', lastMessageTime: DateTime(2026, 1, 2));
    chat('!grp-tg:x', 'Squad Goals TG', lastMessageTime: DateTime(2026, 1, 1));
    space('!imsgspace:x', 'iMessage', ['!imsg:x', '!grp-imsg:x']);
    space('!smsspace:x', 'SMS', ['!sms:x', '!sms2:x']);
    space('!tgspace:x', 'Telegram', ['!grp-tg:x']);
  });

  tearDown(() {
    MergeSuggestionService.disposeFor(client);
    MergedContactsStore.disposeFor(client);
  });

  late GoRouter router;

  Future<void> pumpChatList(WidgetTester tester) async {
    router = GoRouter(
      initialLocation: '/rooms',
      routes: [
        GoRoute(
          path: '/rooms',
          builder: (context, state) => const ChatList(activeChat: null),
          routes: [
            GoRoute(
              path: ':roomid',
              builder: (context, state) =>
                  Text('opened ${state.pathParameters['roomid']}'),
            ),
          ],
        ),
      ],
    );
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrix(client, prefs),
        child: MaterialApp.router(
          theme: ThemeData(
            appBarTheme: const AppBarTheme(
              systemOverlayStyle: SystemUiOverlayStyle.dark,
            ),
          ),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Ends the test with nothing pending: the list is taken down and the
  /// merge suggestion service, which it starts, is stopped.
  Future<void> finish(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    MergeSuggestionService.disposeFor(client);
    await tester.pump(const Duration(seconds: 5));
  }

  Finder selectedMarks() => find.byType(SelectedChatMark);

  Future<void> openMore(WidgetTester tester) async {
    await tester.tap(find.byTooltip('More'));
    await tester.pumpAndSettle();
  }

  Future<void> closeMenu(WidgetTester tester) async {
    await tester.tapAt(const Offset(5, 590));
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester, List<String> names) async {
    await tester.longPress(find.text(names.first));
    await tester.pumpAndSettle();
    for (final name in names.skip(1)) {
      await tester.tap(find.text(name));
      await tester.pumpAndSettle();
    }
  }

  testWidgets('a long press selects and shows the bar with the count', (
    tester,
  ) async {
    await pumpChatList(tester);
    expect(find.byType(ChatListSelectionBar), findsNothing);

    await tester.longPress(find.text('Harrison Young'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatListSelectionBar), findsOneWidget);
    expect(find.byTooltip('Clear selection'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(ChatListSelectionBar),
        matching: find.text('1'),
      ),
      findsOneWidget,
    );
    expect(selectedMarks(), findsOneWidget);
    // The search field is gone while chats are selected.
    expect(find.byType(TextField), findsNothing);
    await finish(tester);
  });

  testWidgets('a tap toggles while selecting and opens a chat otherwise', (
    tester,
  ) async {
    await pumpChatList(tester);
    await tester.longPress(find.text('Harrison Young'));
    await tester.pumpAndSettle();

    await tester.tap(find.text('Squad Goals'));
    await tester.pumpAndSettle();
    expect(selectedMarks(), findsNWidgets(2));
    expect(find.text('2'), findsOneWidget);

    await tester.tap(find.text('Harrison Young'));
    await tester.pumpAndSettle();
    expect(selectedMarks(), findsOneWidget);
    expect(router.state.uri.path, '/rooms');

    // Dropping the last one ends the selection; the next tap opens.
    await tester.tap(find.text('Squad Goals'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatListSelectionBar), findsNothing);
    await tester.tap(find.text('Squad Goals'));
    await tester.pumpAndSettle();
    expect(router.state.uri.path, '/rooms/!grp-imsg:x');
    await finish(tester);
  });

  testWidgets('the close button, back and Escape clear the selection', (
    tester,
  ) async {
    await pumpChatList(tester);

    await select(tester, ['Harrison Young', 'Squad Goals']);
    await tester.tap(find.byTooltip('Clear selection'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatListSelectionBar), findsNothing);
    expect(selectedMarks(), findsNothing);

    await select(tester, ['Harrison Young']);
    await tester.binding.handlePopRoute();
    await tester.pumpAndSettle();
    expect(find.byType(ChatListSelectionBar), findsNothing);
    expect(router.state.uri.path, '/rooms');

    await select(tester, ['Harrison Young']);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
    expect(find.byType(ChatListSelectionBar), findsNothing);
    await finish(tester);
  });

  testWidgets('a right-click selects too', (tester) async {
    await pumpChatList(tester);
    await tester.tap(find.text('Squad Goals'), buttons: kSecondaryButton);
    await tester.pumpAndSettle();
    expect(find.byType(ChatListSelectionBar), findsOneWidget);
    expect(router.state.uri.path, '/rooms');
    await finish(tester);
  });

  testWidgets('pin, mute and read act on every selected room', (tester) async {
    rooms['!grp-imsg:x']!.notificationCount = 1;
    await pumpChatList(tester);
    final picked = [rooms['!imsg:x']!, rooms['!grp-imsg:x']!];
    final other = rooms['!sms:x']!;

    await select(tester, ['Harrison Young', 'Squad Goals']);
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    for (final room in picked) {
      expect(room.calls, ['favourite:true']);
    }
    // The action ends the selection.
    expect(find.byType(ChatListSelectionBar), findsNothing);

    await select(tester, ['Harrison Young', 'Squad Goals']);
    await tester.tap(find.byTooltip('Mute chat'));
    await tester.pumpAndSettle();
    for (final room in picked) {
      expect(room.calls.last, 'push:mentionsOnly');
    }

    // One of the two is unread, so the bar offers to read both: only the
    // unread one has a read marker to move.
    await select(tester, ['Harrison Young', 'Squad Goals']);
    await tester.tap(find.byTooltip('Mark as read'));
    await tester.pumpAndSettle();
    expect(rooms['!grp-imsg:x']!.calls.last, 'read');
    expect(rooms['!imsg:x']!.calls.last, 'push:mentionsOnly');

    rooms['!grp-imsg:x']!.notificationCount = 0;
    await select(tester, ['Harrison Young', 'Squad Goals']);
    await tester.tap(find.byTooltip('Mark as unread'));
    await tester.pumpAndSettle();
    for (final room in picked) {
      expect(room.calls.last, 'unread:true');
    }
    expect(other.calls, isEmpty);
    await finish(tester);
  });

  testWidgets('leave asks once for all selected chats', (tester) async {
    await pumpChatList(tester);
    await select(tester, ['Harrison Young', 'Squad Goals']);
    await tester.tap(find.byTooltip('Leave'));
    await tester.pumpAndSettle();
    expect(find.text('Leave 2 chats?'), findsOneWidget);
    await tester.tap(find.text('Leave').last);
    await tester.pumpAndSettle();
    expect(rooms['!imsg:x']!.calls, ['leave']);
    expect(rooms['!grp-imsg:x']!.calls, ['leave']);
    await finish(tester);
  });

  group('Merge these chats', () {
    Future<bool> offered(WidgetTester tester, List<String> names) async {
      await select(tester, names);
      await openMore(tester);
      final shown = find.text('Merge these chats').evaluate().isNotEmpty;
      await closeMenu(tester);
      await tester.tap(find.byTooltip('Clear selection'));
      await tester.pumpAndSettle();
      return shown;
    }

    testWidgets('is offered only for chats that may be merged', (tester) async {
      await pumpChatList(tester);
      // Same number, iMessage and SMS.
      expect(
        await offered(tester, ['Harrison Young', '(404) 555-1234']),
        isTrue,
      );
      // A one-to-one chat and a group.
      expect(await offered(tester, ['Harrison Young', 'Squad Goals']), isFalse);
      // Same number, both on SMS.
      expect(
        await offered(tester, ['(404) 555-1234', '+1 404-555-1234']),
        isFalse,
      );
      await finish(tester);
    });

    testWidgets('is offered for groups of one name on two networks', (
      tester,
    ) async {
      await pumpChatList(tester);
      // Different names are no match.
      expect(await offered(tester, ['Squad Goals', 'Squad Goals TG']), isFalse);
      // The group on Telegram goes by the iMessage group's name.
      rooms['!grp-tg:x']!.setState(
        StrippedStateEvent(
          type: EventTypes.RoomName,
          content: {'name': 'Squad Goals'},
          senderId: '@someone:x',
          stateKey: '',
        ),
      );
      await tester.longPress(find.text('Squad Goals').first);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Squad Goals').last);
      await tester.pumpAndSettle();
      await openMore(tester);
      expect(find.text('Merge these chats'), findsOneWidget);
      await finish(tester);
    });

    testWidgets('merges the selected chats through the store', (tester) async {
      await pumpChatList(tester);
      await select(tester, ['Harrison Young', '(404) 555-1234']);
      await openMore(tester);
      await tester.tap(find.text('Merge these chats'));
      await tester.pumpAndSettle();

      final contact = MergedContactsStore.forClient(
        client,
      ).contactForRoom('!imsg:x');
      expect(contact?.rooms, ['!imsg:x', '!sms:x']);
      expect(client.accountDataWrites, isNotEmpty);
      expect(find.byType(ChatListSelectionBar), findsNothing);
      await finish(tester);
    });
  });

  testWidgets('one chat\'s menu holds the actions of its old long press', (
    tester,
  ) async {
    await pumpChatList(tester);
    await select(tester, ['Harrison Young']);
    await openMore(tester);
    expect(find.text('Merge with…'), findsOneWidget);
    expect(find.text('Go to space: iMessage'), findsOneWidget);
    expect(find.text('Set low priority'), findsOneWidget);
    expect(find.text('Add tag'), findsOneWidget);
    // Blocking applies to invites only, and merging several to several.
    expect(find.text('Block'), findsNothing);
    expect(find.text('Merge these chats'), findsNothing);
    await closeMenu(tester);
    await finish(tester);
  });

  testWidgets('a merged contact\'s menu offers manage and unmerge', (
    tester,
  ) async {
    setMergedContacts(client, {
      'c_1': {
        'rooms': ['!imsg:x', '!sms:x'],
        'send_via': '!imsg:x',
        'updated': 1,
      },
    });
    await pumpChatList(tester);
    await select(tester, ['Harrison Young']);
    expect(selectedMarks(), findsOneWidget);
    await openMore(tester);
    expect(find.text('Manage linked chats'), findsOneWidget);
    expect(find.text('Unmerge'), findsOneWidget);
    expect(find.text('Merge with…'), findsNothing);
    await closeMenu(tester);

    // Pinning a contact pins each of its rooms.
    await tester.tap(find.byTooltip('Pin'));
    await tester.pumpAndSettle();
    expect(rooms['!imsg:x']!.calls, ['favourite:true']);
    expect(rooms['!sms:x']!.calls, ['favourite:true']);
    await finish(tester);
  });
}
