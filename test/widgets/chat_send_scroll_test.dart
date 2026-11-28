// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:cross_file/cross_file.dart';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

/// Sending from this device brings the chat down to the new message;
/// a message from someone else, or a reaction, edit or deletion from this
/// device, leaves the reading position alone.
void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;
  var serial = 0;

  setUp(() async {
    client = await setUpFakeChatList('chat send scroll');
    room = addFakeChat(client, '!gray:x', 'Gray Adams', partner: '@gray:x');
    // The chat page keeps the screen on while it is open.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() => tearDownFakeChatList(client));

  /// Lets the database and the timeline catch up.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// [count] messages from [sender] arriving in a sync.
  Future<void> receive(
    WidgetTester tester, {
    int count = 1,
    String sender = '@gray:x',
  }) async {
    final events = [
      for (var i = 0; i < count; i++)
        MatrixEvent(
          type: EventTypes.Message,
          content: {
            'msgtype': MessageTypes.Text,
            'body': 'Message ${serial++}\nwith a second line',
          },
          senderId: sender,
          eventId: '\$m$serial',
          originServerTs: DateTime.now(),
        ),
    ];
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'b$serial',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                timeline: TimelineUpdate(events: events),
              ),
            },
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<ChatController> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          builder: (_, _) => ChatPage(roomId: room.id),
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
    await settle(tester);
    await receive(tester, count: 40);
    final chat = tester.state<ChatController>(find.byType(ChatPageWithRoom));
    // Up in the history, reading.
    chat.scrollController.jumpTo(1500);
    await tester.pump();
    expect(chat.showScrollDownButton, isTrue);
    return chat;
  }

  testWidgets('sending text brings the chat down to it', (tester) async {
    final chat = await open(tester);
    chat.sendController.text = 'On my way';
    await tester.runAsync(chat.send);
    await settle(tester);
    expect(chat.scrollController.position.pixels, 0);
    expect(find.text('On my way'), findsOneWidget);
  });

  testWidgets('sending a file brings the chat down to it', (tester) async {
    final chat = await open(tester);
    // The upload goes nowhere here; the local echo is what counts.
    await tester.runAsync(() async {
      room
          .sendFileEvent(MatrixFile(bytes: Uint8List(16), name: 'Lease.pdf'))
          .ignore();
      await Future<void>.delayed(const Duration(milliseconds: 200));
    });
    await settle(tester);
    expect(chat.scrollController.position.pixels, 0);
    expect(find.textContaining('Lease.pdf'), findsWidgets);
  });

  testWidgets('sending from far back in history loads the newest messages', (
    tester,
  ) async {
    final chat = await open(tester);
    chat.timeline!.allowNewEvent = false;
    chat.sendController.text = 'Back to now';
    await tester.runAsync(chat.send);
    await settle(tester);
    expect(chat.timeline!.allowNewEvent, isTrue);
    expect(chat.scrollController.position.pixels, 0);
  });

  testWidgets('a message from someone else keeps the reading position', (
    tester,
  ) async {
    final chat = await open(tester);
    await receive(tester);
    expect(chat.scrollController.position.pixels, greaterThan(0));
    expect(chat.showScrollDownButton, isTrue);
  });

  // Reacting to, editing or deleting an older message sends an event too,
  // but no new message, so the view stays where the user is reading.
  final actions = <String, Future<void> Function(Room room, String eventId)>{
    'reacting to': (room, id) => room.sendReaction(id, '👍'),
    'editing': (room, id) =>
        room.sendTextEvent('Message, edited', editEventId: id),
    'deleting': (room, id) => room.redactEvent(id),
  };
  for (final MapEntry(key: name, value: action) in actions.entries) {
    testWidgets('$name an older message keeps the reading position', (
      tester,
    ) async {
      final chat = await open(tester);
      final before = chat.scrollController.position.pixels;
      final target = chat.timeline!.events
          .firstWhere((e) => e.type == EventTypes.Message)
          .eventId;
      await tester.runAsync(() async {
        // The request goes nowhere here; the local echo is what counts.
        action(room, target).ignore();
        await Future<void>.delayed(const Duration(milliseconds: 200));
      });
      await settle(tester);
      expect(chat.scrollController.position.pixels, before);
      expect(chat.showScrollDownButton, isTrue);
    });
  }

  group('the jump-to-bottom button', () {
    /// The button's bottom edge against the top of the area the composer
    /// takes, which carries the composer's own margin above it.
    void expectAboveComposer(WidgetTester tester, ChatController chat) {
      final button = tester.getRect(find.byType(FloatingActionButton));
      final composer = tester.getRect(find.byKey(chat.inputBarKey));
      expect(button.bottom, closeTo(composer.top, 0.5));
    }

    Future<void> grow(WidgetTester tester) async {
      // The composer reports its new height after a frame, and the button
      // moves up over the animation after that.
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 200));
      }
    }

    testWidgets('sits above the composer', (tester) async {
      final chat = await open(tester);
      await grow(tester);
      expectAboveComposer(tester, chat);
    });

    testWidgets('moves up with a reply bar', (tester) async {
      final chat = await open(tester);
      chat.replyAction(replyTo: chat.timeline!.events.first);
      await grow(tester);
      expectAboveComposer(tester, chat);
    });

    testWidgets('moves up with several lines of text', (tester) async {
      final chat = await open(tester);
      chat.sendController.text = 'One\nTwo\nThree\nFour';
      await grow(tester);
      expectAboveComposer(tester, chat);
    });

    testWidgets('moves up with a staged attachment', (tester) async {
      final chat = await open(tester);
      chat.addPendingAttachments([
        XFile.fromData(Uint8List(16), name: 'Lease.pdf'),
      ]);
      await grow(tester);
      expectAboveComposer(tester, chat);
    });
  });
}
