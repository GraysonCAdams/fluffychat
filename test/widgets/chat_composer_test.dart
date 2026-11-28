// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/utils/native_emoji_picker.dart';
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

/// The composer keeps its attach button whatever is typed or replied to,
/// spaces its buttons evenly, and sends a staged file as part of the reply.
void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;

  setUp(() async {
    client = await setUpFakeChatList('chat composer');
    room = addFakeChat(client, '!grp:x', 'Squad Goals');
    room.recordFiles = true;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Opens the group with one message from Drew in it, in a window
  /// [width] wide.
  Future<ChatController> open(
    WidgetTester tester, {
    double width = 1000,
  }) async {
    tester.view.physicalSize = Size(width, 800);
    tester.view.devicePixelRatio = 1;
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
              builder: (_, _) => ChatPage(roomId: room.id),
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
    await settle(tester);
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
                      content: {'msgtype': 'm.text', 'body': 'Eat their bones'},
                      senderId: '@drew:x',
                      eventId: r'$bones',
                      originServerTs: DateTime(2026, 11, 27, 9),
                    ),
                  ],
                ),
              ),
            },
          ),
        ),
      ),
    );
    await settle(tester);
    return tester.state<ChatController>(find.byType(ChatPageWithRoom));
  }

  Event drewsMessage(ChatController chat) =>
      chat.timeline!.events.firstWhere((event) => event.eventId == r'$bones');

  final attach = find.byKey(const ValueKey('composer-attach'));
  final emoji = find.byKey(const ValueKey('composer-emoji'));

  Rect iconOf(WidgetTester tester, Finder button) =>
      tester.getRect(find.descendant(of: button, matching: find.byType(Icon)));

  /// The composer's pill, and where its text starts.
  Rect pill(WidgetTester tester) => tester.getRect(
    find
        .descendant(
          of: find.byType(ChatComposer),
          matching: find.byType(Material),
        )
        .first,
  );

  double textStart(WidgetTester tester) => tester
      .getRect(
        find.descendant(
          of: find.byType(ChatComposer),
          matching: find.byType(EditableText),
        ),
      )
      .left;

  testWidgets('the attach button stays while typing and replying', (
    tester,
  ) async {
    final chat = await open(tester);
    expect(attach.hitTestable(), findsOneWidget);

    // As typing leaves it; typing itself would tell the server.
    chat.sendController.text = 'Waffle House?';
    chat.inputTextIsEmpty.value = false;
    await settle(tester);
    expect(attach.hitTestable(), findsOneWidget, reason: 'typing');

    chat.replyAction(replyTo: drewsMessage(chat));
    await settle(tester);
    expect(attach.hitTestable(), findsOneWidget, reason: 'replying');
  });

  for (final width in [1000.0, 400.0]) {
    testWidgets('the buttons and the text are spaced evenly, '
        '${width.toInt()} wide', (tester) async {
      final chat = await open(tester, width: width);
      void expectSpacing(String state) {
        final edge = pill(tester).left;
        final plus = iconOf(tester, attach);
        // 12 from the pill's edge to the first icon, as a text field with a
        // leading icon pads it, then 24 between icons and 24 to the text,
        // the space a 48 target leaves either side of a 24 icon.
        expect(plus.left - edge, 12, reason: state);
        if (emoji.evaluate().isNotEmpty) {
          final smiley = iconOf(tester, emoji);
          expect(smiley.left - plus.right, 24, reason: state);
          expect(textStart(tester) - smiley.right, 24, reason: state);
        } else {
          expect(textStart(tester) - plus.right, 24, reason: state);
        }
      }

      expectSpacing('empty');
      chat.sendController.text = 'Waffle House?';
      chat.inputTextIsEmpty.value = false;
      await settle(tester);
      expectSpacing('typing');
    });
  }

  testWidgets('a file staged in a reply is sent as the reply', (tester) async {
    final chat = await open(tester);
    chat.replyAction(replyTo: drewsMessage(chat));
    chat.addPendingAttachments([
      XFile.fromData(
        utf8.encode('menu'),
        name: 'menu.txt',
        mimeType: 'text/plain',
      ),
    ]);
    await settle(tester);

    await tester.runAsync(chat.send);
    await settle(tester);
    expect(room.sentFiles, hasLength(1));
    expect(room.sentFiles.single.inReplyTo, r'$bones');
    expect(chat.replyEvent, isNull);
    expect(chat.pendingAttachments, isEmpty);
  });

  testWidgets('a file staged with text in a reply carries both', (
    tester,
  ) async {
    final chat = await open(tester);
    chat.replyAction(replyTo: drewsMessage(chat));
    chat.sendController.text = 'Their menu';
    chat.addPendingAttachments([
      XFile.fromData(
        utf8.encode('menu'),
        name: 'menu.txt',
        mimeType: 'text/plain',
      ),
    ]);
    await settle(tester);

    await tester.runAsync(chat.send);
    await settle(tester);
    expect(room.sentFiles.single.inReplyTo, r'$bones');
    expect(room.sentFiles.single.extra?['body'], 'Their menu');
    expect(chat.replyEvent, isNull);
    expect(chat.sendController.text, isEmpty);
  });
  for (final native in [true, false]) {
    testWidgets('the emoji button shows only with a system emoji picker, '
        '${native ? 'which there is' : 'which there is not'}', (tester) async {
      NativeEmojiPicker.debugSupported = native;
      addTearDown(() => NativeEmojiPicker.debugSupported = null);
      await open(tester);
      // The group offers no stickers, which would need the app's picker.
      expect(emoji, native ? findsOneWidget : findsNothing);
      expect(attach, findsOneWidget);
      if (!native) {
        // The text then starts 24 after the attach icon.
        expect(textStart(tester) - iconOf(tester, attach).right, 24);
      }
    });
  }
}
