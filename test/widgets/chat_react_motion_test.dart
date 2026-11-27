// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/events/message_reactions.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

/// A client whose server takes every event sent, as the remote echo of a
/// reaction would come back.
class _SendingClient extends FakeChatListClient {
  _SendingClient(super.clientName, {required super.database});

  @override
  Future<String> sendMessage(
    String roomId,
    String eventType,
    String txnId,
    Map<String, Object?> body,
  ) async => '\$sent-$txnId';
}

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

/// Right-clicking a message on the desktop and reacting from its menu, in
/// the real chat screen: the message's time line opens and closes smoothly,
/// and the first reaction grows in under the bubble.
void main() {
  late _SendingClient client;
  late FakeChatListRoom room;

  setUp(() async {
    client = await setUpFakeChatList(
      'chat react motion',
      create: (name, database) => _SendingClient(name, database: database),
    );
    room = addFakeChat(client, '!gray:x', 'Gray Adams', partner: '@gray:x');
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

  /// Opens the chat on a wide window with two of the user's messages, the
  /// older one carrying the transaction ID it was sent with.
  Future<void> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1600, 1000);
    tester.view.devicePixelRatio = 1;
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
                      content: {'msgtype': 'm.text', 'body': 'This is a test'},
                      senderId: '@me:x',
                      eventId: r'$test',
                      originServerTs: DateTime.now().subtract(
                        const Duration(hours: 3),
                      ),
                      unsigned: {'transaction_id': 'txn1'},
                    ),
                    MatrixEvent(
                      type: EventTypes.Message,
                      content: {'msgtype': 'm.text', 'body': 'Test'},
                      senderId: '@me:x',
                      eventId: r'$newest',
                      originServerTs: DateTime.now(),
                    ),
                  ],
                ),
              ),
            },
          ),
        ),
      ),
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
  }

  final message = find.ancestor(
    of: find.text('This is a test'),
    matching: find.byType(Message),
  );
  final chip = find.descendant(
    of: find.byType(MessageReactions),
    matching: find.text('👍'),
  );

  double messageHeight(WidgetTester tester) => tester.getSize(message).height;

  double scaleOf(WidgetTester tester, Finder finder) {
    var scale = 1.0;
    for (final transition in tester.widgetList<ScaleTransition>(
      find.ancestor(of: finder, matching: find.byType(ScaleTransition)),
    )) {
      scale *= transition.scale.value;
    }
    return scale;
  }

  testWidgets('reacting from the right-click menu animates the message', (
    tester,
  ) async {
    // The test font draws the menu's emoji wider than a real one, so its
    // reaction row overflows here; that is not what this test is about.
    final onError = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      onError?.call(details);
    };
    await open(tester);
    final closed = messageHeight(tester);
    final bubble = tester.state(
      find.ancestor(
        of: find.text('This is a test'),
        matching: find.byType(BubbleWithReactions),
      ),
    );

    // The right click selects the message, which opens the line with its
    // time over several frames instead of pushing the timeline up at once.
    await tester.tap(
      find.text('This is a test'),
      buttons: kSecondaryMouseButton,
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 80));
    final opening = messageHeight(tester);
    await tester.pumpAndSettle();
    final selected = messageHeight(tester);
    expect(selected, greaterThan(closed));
    expect(opening, greaterThan(closed));
    expect(opening, lessThan(selected));

    // Picking the reaction clears the selection and sends it; the time line
    // closes and the chip grows in under the bubble.
    await tester.tap(find.text('👍').last);
    final heights = <double>[];
    final scales = <double>[];
    for (var i = 0; i < 40; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 16));
      heights.add(messageHeight(tester));
      if (chip.evaluate().isNotEmpty) scales.add(scaleOf(tester, chip));
    }
    await settle(tester);

    expect(chip, findsOneWidget);
    expect(scaleOf(tester, chip), 1);
    expect(scales.where((scale) => scale > 0 && scale < 1), isNotEmpty);
    // No frame jumps by the time line's full height.
    for (var i = 1; i < heights.length; i++) {
      expect((heights[i] - heights[i - 1]).abs(), lessThan(selected - closed));
    }
    // The bubble stayed mounted throughout.
    expect(
      tester.state(
        find.ancestor(
          of: find.text('This is a test'),
          matching: find.byType(BubbleWithReactions),
        ),
      ),
      same(bubble),
    );
    FlutterError.onError = onError;
  }, variant: TargetPlatformVariant.only(TargetPlatform.windows));
}
