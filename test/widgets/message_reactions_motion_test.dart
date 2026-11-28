// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:math';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/events/message_reactions.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/message_search/search_test_client.dart';

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
    // Showing a sender looks them up in the database. Doing it here, outside
    // the tests' fake clock, keeps that lookup's lock timer out of them.
    for (final id in [
      '@alice:example.org',
      '@bob:example.org',
      '@carol:example.org',
    ]) {
      await room.requestUser(id, ignoreErrors: true);
    }
  });

  final sentAt = DateTime(2026, 11, 20, 10, 58);

  Event textEvent(String eventId, String body, {String? senderId}) => Event(
    content: {'msgtype': 'm.text', 'body': body},
    type: EventTypes.Message,
    eventId: eventId,
    senderId: senderId ?? client.userID!,
    originServerTs: sentAt,
    room: room,
  );

  Event reaction(
    String eventId,
    String key, {
    String sender = '@alice:example.org',
  }) => Event(
    content: {
      'm.relates_to': {
        'rel_type': RelationshipTypes.reaction,
        'event_id': '\$msg',
        'key': key,
      },
    },
    type: EventTypes.Reaction,
    eventId: eventId,
    senderId: sender,
    originServerTs: sentAt,
    room: room,
  );

  /// Shows the message `$msg` and returns a function that rebuilds it the
  /// way the chat screen does when the timeline reports a change, and one
  /// that selects or unselects it.
  Future<
    ({
      Timeline timeline,
      void Function() rebuild,
      void Function(bool selected) select,
    })
  >
  pumpMessage(
    WidgetTester tester, {
    bool own = false,
    List<Event> reactions = const [],
    bool disableAnimations = false,
    bool selected = false,
    bool settle = true,
  }) async {
    final message = textEvent(
      '\$msg',
      'Hello there',
      senderId: own ? null : '@alice:example.org',
    );
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(events: [message, ...reactions]),
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    final changes = ValueNotifier(0);
    addTearDown(changes.dispose);
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrix(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: disableAnimations),
            child: child!,
          ),
          home: Scaffold(
            body: ValueListenableBuilder(
              valueListenable: changes,
              builder: (context, _, _) => ListView(
                controller: scrollController,
                children: [
                  Message(
                    message,
                    bigEmojis: const {},
                    onSelect: (_) {},
                    selected: selected,
                    longPressSelect: false,
                    onInfoTab: (_) {},
                    scrollToEventId: (_) {},
                    onSwipe: () {},
                    onMention: () {},
                    onEdit: () {},
                    enterThread: null,
                    singleSelected: false,
                    hideReactionPicker: true,
                    timeline: timeline,
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
    if (settle) {
      await tester.pumpAndSettle();
    } else {
      // Frames a millisecond apart, until the localizations have loaded
      // and the message is built.
      for (var i = 0; i < 10 && find.byType(Message).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
    }
    return (
      timeline: timeline,
      rebuild: () => changes.value++,
      select: (bool value) {
        selected = value;
        changes.value++;
      },
    );
  }

  double rowHeight(WidgetTester tester) =>
      tester.getSize(find.byType(BubbleWithReactions)).height;

  double opacityOf(WidgetTester tester, Finder finder) {
    var opacity = 1.0;
    for (final fade in tester.widgetList<FadeTransition>(
      find.ancestor(of: finder, matching: find.byType(FadeTransition)),
    )) {
      opacity *= fade.opacity.value;
    }
    return opacity;
  }

  /// How far [finder] is scaled by the transitions above it, 1 at full
  /// size.
  double scaleOf(WidgetTester tester, Finder finder) {
    var scale = 1.0;
    for (final transition in tester.widgetList<ScaleTransition>(
      find.ancestor(of: finder, matching: find.byType(ScaleTransition)),
    )) {
      scale *= transition.scale.value;
    }
    return scale;
  }

  const partway = Duration(milliseconds: 100);

  testWidgets('the first reaction keeps the bubble mounted', (tester) async {
    final shown = await pumpMessage(tester);
    final before = tester.element(find.text('Hello there', findRichText: true));

    shown.timeline.addAggregatedEvent(reaction('\$r1', '❤️'));
    shown.rebuild();
    await tester.pumpAndSettle();

    expect(
      tester.element(find.text('Hello there', findRichText: true)),
      same(before),
    );
  });

  for (final own in [false, true]) {
    testWidgets('the first reaction opens the row on '
        '${own ? 'an own' : 'another sender\'s'} message', (tester) async {
      final shown = await pumpMessage(tester, own: own);
      final closed = rowHeight(tester);

      shown.timeline.addAggregatedEvent(reaction('\$r1', '❤️'));
      shown.rebuild();
      await tester.pump();
      await tester.pump(partway);
      final midway = rowHeight(tester);
      expect(opacityOf(tester, find.text('❤️')), lessThan(1));
      // The chip grows in with the row, as a chip added to an open row does.
      final scale = scaleOf(tester, find.text('❤️'));
      expect(scale, greaterThan(0));
      expect(scale, lessThan(1));
      await tester.pumpAndSettle();
      final open = rowHeight(tester);

      expect(open, closed + reactionChipHeight - reactionChipOverlap);
      expect(midway, greaterThan(closed));
      expect(midway, lessThan(open));
      expect(opacityOf(tester, find.text('❤️')), 1);
      expect(scaleOf(tester, find.text('❤️')), 1);
    });
  }

  testWidgets('a second reaction grows in beside the first', (tester) async {
    final shown = await pumpMessage(
      tester,
      reactions: [reaction('\$r1', '❤️')],
    );
    final oneWide = tester.getSize(find.byType(MessageReactions)).width;

    shown.timeline.addAggregatedEvent(reaction('\$r2', '👍'));
    shown.rebuild();
    await tester.pump();
    await tester.pump(partway);
    final midway = tester.getSize(find.byType(MessageReactions)).width;
    expect(opacityOf(tester, find.text('👍')), lessThan(1));
    await tester.pumpAndSettle();
    final twoWide = tester.getSize(find.byType(MessageReactions)).width;

    expect(midway, greaterThan(oneWide));
    expect(midway, lessThan(twoWide));
    expect(opacityOf(tester, find.text('👍')), 1);
    expect(opacityOf(tester, find.text('❤️')), 1);
  });

  testWidgets('a count change cross-fades the number', (tester) async {
    final shown = await pumpMessage(
      tester,
      reactions: [
        reaction('\$r1', '👍'),
        reaction('\$r2', '👍', sender: '@bob:example.org'),
      ],
    );
    expect(find.text('2'), findsOneWidget);

    shown.timeline.addAggregatedEvent(
      reaction('\$r3', '👍', sender: '@carol:example.org'),
    );
    shown.rebuild();
    await tester.pump();
    await tester.pump(partway);
    expect(find.text('2'), findsOneWidget);
    expect(find.text('3'), findsOneWidget);
    expect(opacityOf(tester, find.text('3')), lessThan(1));

    await tester.pumpAndSettle();
    expect(find.text('2'), findsNothing);
    expect(opacityOf(tester, find.text('3')), 1);
  });

  testWidgets('a removed reaction shrinks out of the row', (tester) async {
    final heart = reaction('\$r1', '❤️');
    final shown = await pumpMessage(
      tester,
      reactions: [heart, reaction('\$r2', '👍')],
    );
    final twoWide = tester.getSize(find.byType(MessageReactions)).width;

    shown.timeline.removeAggregatedEvent(heart);
    shown.rebuild();
    await tester.pump();
    await tester.pump(partway);
    expect(find.text('❤️'), findsOneWidget);
    final midway = tester.getSize(find.byType(MessageReactions)).width;
    await tester.pumpAndSettle();
    final oneWide = tester.getSize(find.byType(MessageReactions)).width;

    expect(find.text('❤️'), findsNothing);
    expect(midway, lessThan(twoWide));
    expect(midway, greaterThan(oneWide));
  });

  testWidgets('removing the last reaction collapses the row', (tester) async {
    final heart = reaction('\$r1', '❤️');
    final shown = await pumpMessage(tester, reactions: [heart]);
    final open = rowHeight(tester);

    shown.timeline.removeAggregatedEvent(heart);
    shown.rebuild();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midway = rowHeight(tester);
    expect(scaleOf(tester, find.text('❤️')), lessThan(1));
    await tester.pumpAndSettle();
    final closed = rowHeight(tester);

    expect(closed, open - reactionChipHeight + reactionChipOverlap);
    expect(midway, lessThan(open));
    expect(midway, greaterThan(closed));
    expect(find.text('❤️'), findsNothing);
  });

  testWidgets('a message built with reactions shows them at once', (
    tester,
  ) async {
    await pumpMessage(tester, reactions: [reaction('\$r1', '❤️')]);
    expect(opacityOf(tester, find.text('❤️')), 1);
    expect(scaleOf(tester, find.text('❤️')), 1);
    expect(
      tester.getSize(find.byType(MessageReactions)).height,
      reactionChipHeight,
    );
  });

  testWidgets('reduced motion shows a new reaction without animating', (
    tester,
  ) async {
    final shown = await pumpMessage(tester, disableAnimations: true);
    final closed = rowHeight(tester);

    shown.timeline.addAggregatedEvent(reaction('\$r1', '❤️'));
    shown.rebuild();
    await tester.pump();

    expect(
      rowHeight(tester),
      closed + reactionChipHeight - reactionChipOverlap,
    );
    expect(opacityOf(tester, find.text('❤️')), 1);
    expect(scaleOf(tester, find.text('❤️')), 1);
  });

  group('selecting a message', () {
    /// The detailed time a selected message shows under its bubble.
    final time = find.textContaining('2026,');

    double messageHeight(WidgetTester tester) =>
        tester.getSize(find.byType(Message)).height;

    /// The alpha of the row's selection tint, 0 when there is none.
    double tintOf(WidgetTester tester) {
      final theme = Theme.of(tester.element(find.byType(Message)));
      return tester
          .widgetList<Material>(
            find.descendant(
              of: find.byType(Message),
              matching: find.byType(Material),
            ),
          )
          .map((material) => material.color)
          .where(
            (color) =>
                color != null &&
                color.withAlpha(255) ==
                    theme.colorScheme.secondaryContainer.withAlpha(255),
          )
          .map((color) => color!.a)
          .fold(0.0, max);
    }

    testWidgets('opens the time line and fades the tint in, then out', (
      tester,
    ) async {
      final shown = await pumpMessage(tester);
      final closed = messageHeight(tester);
      expect(time, findsNothing);
      expect(tintOf(tester), 0);

      shown.select(true);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final opening = messageHeight(tester);
      final tintMidway = tintOf(tester);
      expect(opacityOf(tester, time), lessThan(1));
      await tester.pumpAndSettle();
      final open = messageHeight(tester);
      final tint = tintOf(tester);

      expect(open, greaterThan(closed));
      expect(opening, greaterThan(closed));
      expect(opening, lessThan(open));
      expect(tintMidway, greaterThan(0));
      expect(tintMidway, lessThan(tint));
      expect(opacityOf(tester, time), 1);

      shown.select(false);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 80));
      final closing = messageHeight(tester);
      expect(time, findsOneWidget);
      expect(tintOf(tester), lessThan(tint));
      expect(tintOf(tester), greaterThan(0));
      await tester.pumpAndSettle();

      expect(closing, lessThan(open));
      expect(closing, greaterThan(closed));
      expect(messageHeight(tester), closed);
      expect(time, findsNothing);
      expect(tintOf(tester), 0);
    });

    testWidgets('a message built selected shows its time and tint at once', (
      tester,
    ) async {
      await pumpMessage(tester, selected: true, settle: false);
      expect(opacityOf(tester, time), 1);
      final height = messageHeight(tester);
      expect(tintOf(tester), closeTo(128 / 255, 0.01));
      await tester.pumpAndSettle();
      expect(messageHeight(tester), height);
      expect(tintOf(tester), closeTo(128 / 255, 0.01));
    });

    testWidgets('reduced motion selects without animating', (tester) async {
      final shown = await pumpMessage(tester, disableAnimations: true);
      shown.select(true);
      await tester.pump();
      final open = messageHeight(tester);
      final tint = tintOf(tester);
      await tester.pumpAndSettle();
      expect(messageHeight(tester), open);
      expect(tintOf(tester), tint);
      expect(opacityOf(tester, time), 1);
    });
  });
}
