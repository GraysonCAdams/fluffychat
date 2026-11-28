// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/events/message_reactions.dart';
import 'package:fluffychat/utils/data_detectors/data_detections.dart';
import 'package:fluffychat/utils/data_detectors/data_detector_platform.dart';
import 'package:fluffychat/utils/data_detectors/detection_actions.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';
import '../utils/data_detectors/data_detector_fakes.dart';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

const _phoneText = 'Works. Call me at (404) 555-0123 when you are close';
const _address = '3456 Chelsea Park Lane Apt D, Peachtree Corners GA 30092';

void main() {
  late FakeChatListClient client;
  late FakeDetector detector;
  late FakeLauncher launcher;

  var run = 0;

  setUp(() async {
    client = await setUpFakeChatList('data detectors');
    run++;
    detector = FakeDetector(android: true);
    DataDetectorPlatform.instance = detector;
    launcher = FakeLauncher();
    DetectionActions.launcher = launcher;
    DataDetections.instance.clear();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() {
    DataDetectorPlatform.instance = null;
    DetectionActions.launcher = const DetectionLauncher();
    tearDownFakeChatList(client);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  var batch = 0;

  /// Adds messages to [room] as a sync would: (event id, sender, body).
  Future<void> receive(
    WidgetTester tester,
    Room room,
    List<(String, String, String)> messages, {
    List<(String, String)> reactions = const [],
  }) async {
    final base = DateTime(2026, 11, 27, 9).add(Duration(minutes: batch * 10));
    batch++;
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'b$batch',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [
                    for (final (i, (id, sender, body)) in messages.indexed)
                      MatrixEvent(
                        type: EventTypes.Message,
                        content: {'msgtype': 'm.text', 'body': body},
                        senderId: sender,
                        eventId: id,
                        originServerTs: base.add(Duration(minutes: i)),
                      ),
                    for (final (i, (target, key)) in reactions.indexed)
                      MatrixEvent(
                        type: EventTypes.Reaction,
                        content: {
                          'm.relates_to': {
                            'rel_type': RelationshipTypes.reaction,
                            'event_id': target,
                            'key': key,
                          },
                        },
                        senderId: '@drew:x',
                        eventId: '\$r$batch$i',
                        originServerTs: base.add(const Duration(minutes: 9)),
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
  }

  Future<(ChatController, Room)> open(
    WidgetTester tester,
    List<(String, String, String)> messages,
  ) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    // A room of its own for each test, as the fake keeps every room's
    // messages across tests.
    final room = addFakeChat(client, '!grp$run:x', 'Squad Goals');
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
          theme: ThemeData(brightness: Brightness.dark),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await tester.pumpAndSettle();
    router.push('/chat');
    await settle(tester);
    await receive(tester, room, messages);
    return (tester.state<ChatController>(find.byType(ChatPageWithRoom)), room);
  }

  Finder messageWith(String text) => find.ancestor(
    of: find.byWidgetPredicate(
      (w) => w is RichText && w.text.toPlainText().contains(text),
    ),
    matching: find.byType(Message),
  );

  Finder chipsOf(String text) =>
      find.descendant(of: messageWith(text), matching: find.byType(ActionChip));

  List<String> chipLabels(WidgetTester tester, [Finder? within]) => [
    for (final chip in tester.widgetList<ActionChip>(
      within == null
          ? find.byType(ActionChip)
          : find.descendant(of: within, matching: find.byType(ActionChip)),
    ))
      (chip.label as Text).data!,
  ];

  /// The paragraph showing [piece], and the box around it on screen.
  (RenderParagraph, Rect) locate(WidgetTester tester, String piece) {
    for (final paragraph in tester.renderObjectList<RenderParagraph>(
      find.byType(RichText),
    )) {
      final plain = paragraph.text.toPlainText(includeSemanticsLabels: false);
      final at = plain.indexOf(piece);
      if (at < 0) continue;
      final boxes = paragraph.getBoxesForSelection(
        TextSelection(baseOffset: at, extentOffset: at + piece.length),
      );
      var rect = boxes.first.toRect();
      for (final box in boxes.skip(1)) {
        rect = rect.expandToInclude(box.toRect());
      }
      return (
        paragraph,
        MatrixUtils.transformRect(paragraph.getTransformTo(null), rect),
      );
    }
    throw StateError('No paragraph shows $piece');
  }

  /// The span reading [piece] in the message text, as rendered.
  TextSpan spanOf(WidgetTester tester, String piece) {
    final (paragraph, _) = locate(tester, piece);
    TextSpan? found;
    paragraph.text.visitChildren((span) {
      if (span is TextSpan && span.text == piece) {
        found = span;
        return false;
      }
      return true;
    });
    return found ?? (throw StateError('No span reads $piece'));
  }

  group('spans', () {
    testWidgets('detections are underlined in the bubble\'s text colour', (
      tester,
    ) async {
      await open(tester, [
        (r'$in', '@drew:x', 'Come by whenever. $_address'),
        (r'$own', client.userID!, _phoneText),
      ]);
      for (final piece in [_address, '(404) 555-0123']) {
        final (paragraph, _) = locate(tester, piece);
        final span = spanOf(tester, piece);
        expect(span.style?.decoration, TextDecoration.underline, reason: piece);
        // The paragraph's own colour, not the theme's link colour.
        expect(span.style?.decorationColor, paragraph.text.style?.color);
        expect(span.style?.color, isNull, reason: 'inherits the text colour');
      }
      // The rest of the text is not underlined.
      expect(spanOf(tester, 'Works. Call me at ').style, isNull);
    });

    testWidgets('an address over several lines is underlined line by line', (
      tester,
    ) async {
      await open(tester, [
        (
          r'$a',
          '@drew:x',
          '3456 Chelsea Park Lane Apt D\nPeachtree Corners GA\n30092',
        ),
      ]);
      for (final line in [
        '3456 Chelsea Park Lane Apt D',
        'Peachtree Corners GA',
        '30092',
      ]) {
        expect(
          spanOf(tester, line).style?.decoration,
          TextDecoration.underline,
          reason: line,
        );
      }
    });
  });

  group('chips', () {
    testWidgets('only the newest message with a detection shows chips', (
      tester,
    ) async {
      final (_, room) = await open(tester, [
        (r'$1', '@drew:x', 'My new number is (404) 555-0188'),
        (r'$2', client.userID!, 'Got it'),
        (r'$3', '@drew:x', 'Come by whenever. $_address'),
      ]);
      expect(chipLabels(tester), ['Map']);
      expect(chipsOf(_address), findsOneWidget);
      // The older detection keeps its underline.
      expect(
        spanOf(tester, '(404) 555-0188').style?.decoration,
        TextDecoration.underline,
      );

      // A newer one takes the chip; the older one's folds away.
      await receive(tester, room, [
        (r'$4', client.userID!, 'Leaving now'),
        (r'$5', '@drew:x', 'Or ring (404) 555-0199 at the gate'),
      ]);
      await tester.pumpAndSettle();
      expect(chipLabels(tester), ['Call']);
      expect(chipsOf('(404) 555-0199'), findsOneWidget);
      expect(chipsOf(_address), findsNothing);
    });

    testWidgets('at most two chips, one per detection in reading order', (
      tester,
    ) async {
      await open(tester, [
        (
          r'$3',
          '@drew:x',
          'Come to $_address, ring (404) 555-0123, see you Saturday at 7pm',
        ),
      ]);
      expect(chipLabels(tester), ['Map', 'Call']);
      // The third stays underlined only.
      expect(
        spanOf(tester, 'Saturday at 7pm').style?.decoration,
        TextDecoration.underline,
      );
    });

    testWidgets('on Windows the chip is Seam\'s own action', (tester) async {
      DataDetectorPlatform.instance = detector = FakeDetector(android: false);
      await open(tester, [(r'$own', client.userID!, _phoneText)]);
      expect(chipLabels(tester), ['Call']);
      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();
      expect(launcher.calls, [Uri.parse('tel:+14045550123')]);
    });
  });

  group('taps', () {
    testWidgets('a tap on the chip runs Android\'s first action', (
      tester,
    ) async {
      await open(tester, [(r'$own', client.userID!, _phoneText)]);
      await tester.tap(find.byType(ActionChip));
      await tester.pumpAndSettle();
      expect(detector.ran, [('(404) 555-0123', 0)]);
      expect(find.byType(PopupMenuItem<DetectionAction>), findsNothing);
    });

    testWidgets('a tap on the span opens the anchored menu: Android\'s '
        'actions, a divider, then Seam\'s', (tester) async {
      await open(tester, [(r'$own', client.userID!, _phoneText)]);
      final (_, span) = locate(tester, '(404) 555-0123');
      await tester.tapAt(span.center);
      await tester.pumpAndSettle();
      final items = tester.widgetList<PopupMenuItem<DetectionAction>>(
        find.byType(PopupMenuItem<DetectionAction>),
      );
      expect(
        [for (final item in items) item.value!.title],
        ['Call', 'Add', 'Message', 'Copy'],
      );
      expect(find.byType(PopupMenuDivider), findsOneWidget);
      // Under or over the bubble, never over the span. A span right of the
      // middle of the screen has the menu hang from its right edge.
      final first = tester.getRect(
        find.byType(PopupMenuItem<DetectionAction>).first,
      );
      final last = tester.getRect(
        find.byType(PopupMenuItem<DetectionAction>).last,
      );
      expect(
        first.top >= span.bottom || last.bottom <= span.top,
        isTrue,
        reason: 'menu ${first.top}-${last.bottom}, span $span',
      );
      expect(span.center.dx, greaterThan(300));
      expect(first.right, moreOrLessEquals(span.right, epsilon: 1));

      await tester.tap(find.text('Copy'));
      await tester.pumpAndSettle();
      expect(launcher.calls, ['copy (404) 555-0123']);
      expect(detector.ran, isEmpty);
    });

    testWidgets('a menu item from Android runs that action', (tester) async {
      await open(tester, [(r'$own', client.userID!, _phoneText)]);
      await tester.tapAt(locate(tester, '(404) 555-0123').$2.center);
      await tester.pumpAndSettle();
      await tester.tap(find.text('Message').last);
      await tester.pumpAndSettle();
      expect(detector.ran, [('(404) 555-0123', 2)]);
    });

    testWidgets('a long-press on the span selects the message, as anywhere '
        'else on it', (tester) async {
      final (chat, _) = await open(tester, [
        (r'$own', client.userID!, _phoneText),
      ]);
      await tester.longPressAt(locate(tester, '(404) 555-0123').$2.center);
      await tester.pumpAndSettle();
      expect(find.byType(PopupMenuItem<DetectionAction>), findsNothing);
      expect(detector.ran, isEmpty);
      expect(chat.selectedEvents.map((e) => e.eventId), [r'$own']);
    });
  });

  group('layout', () {
    /// Lays out a bubble of [bubbleWidth] with reaction chips 80 wide and an
    /// assist row 90 wide, and answers where each landed.
    Future<(Rect bubble, Rect reactions, Rect assist)> lay(
      WidgetTester tester, {
      required double bubbleWidth,
      required bool own,
    }) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Align(
            alignment: own ? Alignment.topRight : Alignment.topLeft,
            child: BubbleWithReactions(
              reactionsAtEnd: !own,
              bubble: SizedBox(
                key: const ValueKey('bubble'),
                width: bubbleWidth,
                height: 60,
              ),
              reactions: const SizedBox(
                key: ValueKey('reactions'),
                width: 80,
                height: reactionChipHeight,
              ),
              assist: const SizedBox(
                key: ValueKey('assist'),
                width: 90,
                height: 32,
              ),
            ),
          ),
        ),
      );
      Rect at(String key) => tester.getRect(find.byKey(ValueKey(key)));
      return (at('bubble'), at('reactions'), at('assist'));
    }

    testWidgets('a wide bubble: the chip shares the band under the bubble '
        'with the reactions, on the bubble\'s own side', (tester) async {
      for (final own in [false, true]) {
        final (bubble, reactions, assist) = await lay(
          tester,
          bubbleWidth: 300,
          own: own,
        );
        expect(assist.top, bubble.bottom + 4, reason: 'own: $own');
        if (own) {
          expect(assist.right, bubble.right);
          expect(reactions.left, bubble.left);
        } else {
          expect(assist.left, bubble.left);
          expect(reactions.right, bubble.right);
        }
      }
    });

    testWidgets('a narrow bubble: the chip drops under the reactions', (
      tester,
    ) async {
      final (bubble, reactions, assist) = await lay(
        tester,
        bubbleWidth: 150,
        own: true,
      );
      expect(assist.top, reactions.bottom + 4);
      expect(assist.right, bubble.right);
    });

    testWidgets('in the chat: reactions, then the chip, then the status '
        'line', (tester) async {
      final (_, room) = await open(tester, [
        (r'$q', '@drew:x', 'What time works?'),
        (r'$own', client.userID!, 'Saturday at 7pm'),
      ]);
      await receive(tester, room, [], reactions: [(r'$own', '👍')]);
      await tester.pumpAndSettle();
      final chip = tester.getRect(find.byType(ActionChip));
      final bubble = tester.getRect(
        find
            .ancestor(
              of: find.byWidgetPredicate(
                (w) =>
                    w is RichText &&
                    w.text.toPlainText().contains('Saturday at 7pm'),
              ),
              matching: find.byType(BubbleWithReactions),
            )
            .first,
      );
      expect(chip.bottom, lessThanOrEqualTo(bubble.bottom));
      expect(chip.top, greaterThan(bubble.top));
    });
  });
}
