// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/events/message_reactions.dart';
import 'package:fluffychat/pages/chat/status_mark.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/message_search/search_test_client.dart';
import 'render_pixels.dart';

/// Stands in for the app's Matrix widget, which widgets only ask for its
/// client.
class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late Room room;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await createSearchTestClient();
    room = client.rooms.firstWhere((room) => !room.isSpace);
  });

  final sentAt = DateTime(2026, 11, 20, 10, 58);

  Event textEvent(
    String eventId,
    String body, {
    String? senderId,
    EventStatus status = EventStatus.synced,
  }) => Event(
    content: {'msgtype': 'm.text', 'body': body},
    type: EventTypes.Message,
    eventId: eventId,
    senderId: senderId ?? client.userID!,
    originServerTs: sentAt,
    status: status,
    room: room,
  );

  Event reaction(String eventId, String target, String key) => Event(
    content: {
      'm.relates_to': {
        'rel_type': RelationshipTypes.reaction,
        'event_id': target,
        'key': key,
      },
    },
    type: EventTypes.Reaction,
    eventId: eventId,
    senderId: '@alice:example.org',
    originServerTs: sentAt,
    room: room,
  );

  /// Shows [event] with [below] (the newer message) under it, and keeps
  /// the tapped and selected messages the way the chat screen does.
  Future<void> pumpMessage(
    WidgetTester tester,
    Event event, {
    List<Event> others = const [],
    Event? below,
    bool deliveryStatus = false,
    Brightness brightness = Brightness.light,
  }) async {
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(events: [?below, event, ...others]),
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    String? revealed;
    final selected = <String>{};
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrix(client),
        child: MaterialApp(
          theme: ThemeData(brightness: brightness),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                Widget message(Event e, {Event? next, Event? previous}) =>
                    Message(
                      e,
                      nextEvent: next,
                      previousEvent: previous,
                      bigEmojis: const {},
                      onSelect: (e) => setState(
                        () => selected.remove(e.eventId)
                            ? null
                            : selected.add(e.eventId),
                      ),
                      selected: selected.contains(e.eventId),
                      longPressSelect: selected.isNotEmpty,
                      timeRevealed: revealed == e.eventId,
                      onToggleTime: (e) => setState(
                        () =>
                            revealed = revealed == e.eventId ? null : e.eventId,
                      ),
                      showDeliveryStatus: deliveryStatus && e == event,
                      onInfoTab: (_) {},
                      scrollToEventId: (_) {},
                      onSwipe: () {},
                      onMention: () {},
                      onEdit: () {},
                      enterThread: null,
                      singleSelected: false,
                      hideReactionPicker: true,
                      timeline: timeline,
                    );
                return ListView(
                  controller: scrollController,
                  children: [
                    message(event, previous: below),
                    if (below != null) message(below, next: event),
                  ],
                );
              },
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The decorated box that paints the bubble holding [text].
  Rect bubbleRect(WidgetTester tester, String text) => tester.getRect(
    find
        .ancestor(
          of: find.text(text, findRichText: true),
          matching: find.byWidgetPredicate(
            (w) =>
                w is Container &&
                w.decoration is BoxDecoration &&
                (w.decoration! as BoxDecoration).borderRadius is BorderRadius &&
                w.clipBehavior == Clip.antiAlias,
          ),
        )
        .first,
  );

  group('bubble colour', () {
    for (final brightness in Brightness.values) {
      testWidgets('an own bubble in a plain Matrix room is the theme\'s '
          'bubble colour throughout, ${brightness.name}', (tester) async {
        await pumpMessage(
          tester,
          textEvent('\$own', 'A message of my own, long enough'),
          brightness: brightness,
        );
        final theme = Theme.of(tester.element(find.byType(Message)));
        final colors = await bubbleEdgeColors(
          tester,
          find.text('A message of my own, long enough', findRichText: true),
        );
        expect(colors, isNotEmpty);
        expect(colors.toSet(), {theme.bubbleColor});
        // Reading the pixels runs real time, in which the bubble may ask for
        // its sender; let that request's timer run out.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(minutes: 1));
      });
    }
  });

  group('reactions', () {
    for (final own in [false, true]) {
      testWidgets(
        'the chip overlaps the ${own ? 'own' : 'other'} bubble corner',
        (tester) async {
          final message = textEvent(
            '\$msg',
            'Hello there',
            senderId: own ? null : '@alice:example.org',
          );
          await pumpMessage(
            tester,
            message,
            others: [reaction('\$r1', '\$msg', '❤️')],
          );

          final bubble = bubbleRect(tester, 'Hello there');
          final chip = tester.getRect(
            find
                .ancestor(of: find.text('❤️'), matching: find.byType(Material))
                .first,
          );
          expect(chip.height, reactionChipHeight);
          expect(chip.top, bubble.bottom - reactionChipOverlap);
          if (own) {
            expect(chip.left, bubble.left);
          } else {
            expect(chip.right, bubble.right);
          }
        },
      );
    }

    testWidgets('the chip does not cover the next message', (tester) async {
      final message = textEvent(
        '\$msg',
        'First',
        senderId: '@alice:example.org',
      );
      final below = textEvent(
        '\$next',
        'Second',
        senderId: '@alice:example.org',
      );
      await pumpMessage(
        tester,
        message,
        below: below,
        others: [reaction('\$r1', '\$msg', '❤️')],
      );

      final chip = tester.getRect(
        find
            .ancestor(of: find.text('❤️'), matching: find.byType(Material))
            .first,
      );
      expect(
        bubbleRect(tester, 'Second').top,
        greaterThanOrEqualTo(chip.bottom),
      );
    });

    testWidgets('a message without reactions adds no space', (tester) async {
      final message = textEvent('\$msg', 'Plain');
      await pumpMessage(tester, message);
      expect(find.byType(MessageReactions), findsNothing);
    });

    testWidgets('a count shows inside the chip', (tester) async {
      final message = textEvent('\$msg', 'Hi', senderId: '@alice:example.org');
      await pumpMessage(
        tester,
        message,
        others: [
          reaction('\$r1', '\$msg', '👍'),
          Event(
            content: {
              'm.relates_to': {
                'rel_type': RelationshipTypes.reaction,
                'event_id': '\$msg',
                'key': '👍',
              },
            },
            type: EventTypes.Reaction,
            eventId: '\$r2',
            senderId: '@bob:example.org',
            originServerTs: sentAt,
            room: room,
          ),
        ],
      );
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('tap to show the time', () {
    Finder time() => find.textContaining('10:58');

    testWidgets('a tap shows the time and a second tap hides it', (
      tester,
    ) async {
      await pumpMessage(
        tester,
        textEvent('\$msg', 'Tap me', senderId: '@alice:example.org'),
      );
      expect(time(), findsNothing);

      await tester.tap(find.text('Tap me', findRichText: true));
      await tester.pumpAndSettle();
      expect(time(), findsOneWidget);

      await tester.tap(find.text('Tap me', findRichText: true));
      await tester.pumpAndSettle();
      expect(time(), findsNothing);
    });

    testWidgets('a long press still selects the message', (tester) async {
      await pumpMessage(tester, textEvent('\$msg', 'Hold me'));

      await tester.longPress(find.text('Hold me', findRichText: true));
      await tester.pumpAndSettle();
      // Selection mode shows the select toggle beside the message.
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(time(), findsOneWidget);

      // In selection mode a tap on the bubble does not toggle the time.
      await tester.tap(find.text('Hold me', findRichText: true));
      await tester.pumpAndSettle();
      expect(find.byIcon(Icons.check_circle), findsOneWidget);
      expect(time(), findsOneWidget);
    });
  });

  group('delivery status', () {
    Finder sentMark() => find.byWidgetPredicate(
      (widget) => widget is StatusMark && widget.state == StatusMarkState.sent,
    );

    testWidgets('the newest own message shows it was sent', (tester) async {
      await pumpMessage(
        tester,
        textEvent('\$msg', 'Mine', status: EventStatus.synced),
        deliveryStatus: true,
      );
      expect(sentMark(), findsOneWidget);
      expect(find.byTooltip('Sent'), findsOneWidget);
    });

    testWidgets('other own messages show no mark', (tester) async {
      await pumpMessage(tester, textEvent('\$msg', 'Older'));
      expect(sentMark(), findsNothing);
    });

    testWidgets('a message from someone else shows no mark', (tester) async {
      await pumpMessage(
        tester,
        textEvent('\$msg', 'Theirs', senderId: '@alice:example.org'),
        deliveryStatus: true,
      );
      expect(sentMark(), findsNothing);
    });

    testWidgets('a failed message says so instead', (tester) async {
      await pumpMessage(
        tester,
        textEvent('\$msg', 'Failed', status: EventStatus.error),
        deliveryStatus: true,
      );
      expect(sentMark(), findsNothing);
      expect(find.text('Could not be sent'), findsOneWidget);
      expect(find.byIcon(Icons.error_outlined), findsOneWidget);
      expect(
        tester.widget<StatusMark>(find.byType(StatusMark)).state,
        StatusMarkState.failed,
      );
    });
  });
}
