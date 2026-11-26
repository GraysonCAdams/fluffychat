// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages, deprecated_member_use

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A client that is never logged in but looks synced, and keeps account
/// data writes (the merged contacts) locally.
class FakeChatListClient extends Client {
  FakeChatListClient(super.clientName, {required super.database});

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
class FakeChatListRoom extends Room {
  FakeChatListRoom({
    required super.id,
    required super.client,
    super.notificationCount,
  });

  final calls = <String>[];

  @override
  Future<void> setFavourite(bool favourite) async =>
      calls.add('favourite:$favourite');

  @override
  Future<void> addTag(String tag, {double? order}) async =>
      calls.add('tag:$tag:$order');

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

  /// Pins the room as a sync would, with [order] on the favourite tag when
  /// given.
  void pin([double? order]) {
    roomAccountData['m.tag'] = BasicEvent(
      type: 'm.tag',
      content: {
        'tags': {
          'm.favourite': {'order': ?order},
        },
      },
    );
  }
}

/// Stands in for the app's Matrix widget with one client and no bundles.
class FakeMatrix extends MatrixState {
  final Client fakeClient;
  final SharedPreferences prefs;

  FakeMatrix(this.fakeClient, this.prefs);

  @override
  Client get client => fakeClient;

  @override
  SharedPreferences get store => prefs;

  @override
  bool get hasComplexBundles => false;

  @override
  // Keyed by the user ID, as a lone account's bundle is, so the account
  // menu shows no bundle heading.
  Map<String?, List<Client?>> get accountBundles => {
    fakeClient.userID: [fakeClient],
  };

  @override
  List<Client?>? get currentBundle => [fakeClient];
}

/// Settings as the chat list tests expect them, and a fresh fake client
/// named [name] that looks synced, made by [create] when given.
Future<T> setUpFakeChatList<T extends FakeChatListClient>(
  String name, {
  T Function(String name, DatabaseApi database)? create,
}) async {
  SharedPreferences.setMockInitialValues({});
  await AppSettings.init(loadWebConfigFile: false);
  await AppSettings.checkForUpdates.setItem(false);
  await AppSettings.mergedContactSuggestions.setItem(false);
  await AppSettings.mergedContactsPhoneRegion.setItem('US');
  await AppSettings.matrixFeaturesMode.setItem('auto');
  await AppSettings.matrixFeatureOverrides.setItem('{}');
  await AppSettings.store.remove(MatrixFeatures.scanCacheKeyFor(name));
  MatrixFeatures.scanStoredState = false;

  sqfliteFfiInit();
  final database = await MatrixSdkDatabase.init(
    name,
    database: await databaseFactoryFfi.openDatabase(':memory:'),
    sqfliteFactory: databaseFactoryFfi,
  );
  final client =
      create?.call(name, database) ??
      FakeChatListClient(name, database: database) as T;
  // Looks synced to the header, which otherwise shows a spinner.
  client.onSync.add(SyncUpdate(nextBatch: 'synced'));
  return client;
}

/// Stops what the chat list started for [client].
void tearDownFakeChatList(Client client) {
  MergeSuggestionService.disposeFor(client);
  MergedContactsStore.disposeFor(client);
  MatrixFeatures.disposeFor(client);
}

/// A space named [name] holding [children], as a bridge sets one up.
Room addFakeSpace(
  Client client,
  String id,
  String name,
  List<String> children,
) {
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

/// Marks [room] as a portal of a bridge whose bot is [bot], as mautrix
/// bridges do with an `m.bridge` event ([type] picks the older name).
void addFakeBridge(
  Room room, {
  String bot = '@imessagebot:x',
  String network = 'iMessage',
  String type = 'm.bridge',
}) => room.setState(
  StrippedStateEvent(
    type: type,
    content: {
      'bridgebot': bot,
      'protocol': {'id': network.toLowerCase(), 'displayname': network},
    },
    senderId: bot,
    stateKey: 'net/${room.id}',
  ),
);

/// A joined chat named [name]; one-to-one with [partner] when given,
/// else a group.
FakeChatListRoom addFakeChat(
  Client client,
  String id,
  String name, {
  String? partner,
  int notificationCount = 0,
  DateTime? lastMessageTime,
}) {
  final room = FakeChatListRoom(
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
  return room;
}

/// Shows the chat list of [client] at `/rooms`, with a chat route that
/// names the chat it opened. Returns the router to read the location from.
Future<GoRouter> pumpFakeChatList(WidgetTester tester, Client client) async {
  final prefs = await SharedPreferences.getInstance();
  final router = GoRouter(
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
      value: FakeMatrix(client, prefs),
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
  return router;
}

/// Ends a test with nothing pending: the list is taken down and the merge
/// suggestion service, which it starts, is stopped.
Future<void> finishFakeChatList(WidgetTester tester, Client client) async {
  await tester.pumpWidget(const SizedBox());
  MergeSuggestionService.disposeFor(client);
  MatrixFeatures.disposeFor(client);
  await tester.pump(const Duration(seconds: 5));
}
