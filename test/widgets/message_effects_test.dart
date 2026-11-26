// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/invisible_ink.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_bubble.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_picker.dart';
import 'package:fluffychat/pages/chat/effects/played_message_effects.dart';
import 'package:fluffychat/pages/chat/effects/screen_effect_host.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/merged_contacts/fake_rooms.dart';
import '../utils/message_search/search_test_client.dart';

/// Stands in for the app's Matrix widget, which widgets only ask for its
/// client.
class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

/// Pumps until the app's localizations have loaded and its first page is
/// built, a millisecond at a time.
Future<void> pumpUntilBuilt(WidgetTester tester) async {
  for (var i = 0; i < 50 && find.byType(Scaffold).evaluate().isEmpty; i++) {
    await tester.pump(const Duration(milliseconds: 1));
  }
  expect(find.byType(Scaffold), findsWidgets);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late Room room;
  late Room iMessage;
  late Room whatsApp;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    MatrixFeatures.scanStoredState = false;
    client = await createSearchTestClient();
    room = client.rooms.firstWhere((room) => !room.isSpace);
    final bridged = await fakeMergedClient();
    iMessage = addDirectChat(
      bridged,
      id: '!imessage:example.org',
      partner: '@imessage_15551234567:example.org',
      name: 'Ada',
    );
    whatsApp = addDirectChat(
      bridged,
      id: '!whatsapp:example.org',
      partner: '@whatsapp_15551234567:example.org',
      name: 'Ada',
    );
  });

  setUp(() async {
    await AppSettings.playedMessageEffects.setItem('[]');
    PlayedMessageEffects.resetForTest();
  });

  Event effectEvent(
    MessageEffect effect, {
    String id = '\$effect',
    String body = 'Happy new year',
  }) => Event(
    content: withEffect({'msgtype': 'm.text', 'body': body}, effect),
    type: EventTypes.Message,
    eventId: id,
    senderId: '@alice:example.org',
    originServerTs: DateTime.now(),
    status: EventStatus.synced,
    room: room,
  );

  /// Shows [event] as the chat does: a message in a list under the area
  /// screen effects play over. [rebuild] gets a function that rebuilds
  /// the message.
  Future<void> pumpMessage(
    WidgetTester tester,
    Event event, {
    bool reducedMotion = false,
    void Function(VoidCallback rebuild)? rebuild,
  }) async {
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(events: [event]),
    );
    final scrollController = ScrollController();
    addTearDown(scrollController.dispose);
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrix(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(disableAnimations: reducedMotion),
            child: child!,
          ),
          home: Scaffold(
            body: ScreenEffectHost(
              child: StatefulBuilder(
                builder: (context, setState) {
                  rebuild?.call(() => setState(() {}));
                  return ListView(
                    controller: scrollController,
                    children: [
                      Message(
                        event,
                        bigEmojis: const {},
                        onSelect: (_) {},
                        selected: false,
                        longPressSelect: false,
                        timeRevealed: false,
                        onToggleTime: (_) {},
                        onInfoTab: (_) {},
                        scrollToEventId: (_) {},
                        onSwipe: () {},
                        onMention: () {},
                        onEdit: () {},
                        enterThread: null,
                        singleSelected: false,
                        hideReactionPicker: true,
                        timeline: timeline,
                        scrollController: scrollController,
                        colors: const [Colors.blue, Colors.blue],
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
    await pumpUntilBuilt(tester);
    // The frame on which an effect that plays by itself starts its clock.
    await tester.pump();
  }

  ScreenEffectHostState host(WidgetTester tester) =>
      tester.state<ScreenEffectHostState>(find.byType(ScreenEffectHost));

  group('a received screen effect', () {
    testWidgets('plays once and not again on rebuild', (tester) async {
      final event = effectEvent(MessageEffect.fireworks);
      late VoidCallback rebuild;
      await pumpMessage(tester, event, rebuild: (r) => rebuild = r);
      await tester.pump();
      expect(host(tester).plays, 1);
      expect(host(tester).playing, MessageEffect.fireworks);
      expect(find.byKey(const ValueKey('screen_effect_scene')), findsOneWidget);

      rebuild();
      await tester.pump(const Duration(milliseconds: 500));
      rebuild();
      await tester.pump(const Duration(milliseconds: 500));
      expect(host(tester).plays, 1);

      // The scene ends by itself and leaves nothing over the chat.
      await tester.pump(const Duration(seconds: 7));
      await tester.pump();
      expect(host(tester).playing, isNull);
      expect(find.byKey(const ValueKey('screen_effect_scene')), findsNothing);
      expect(find.text('Happy new year', findRichText: true), findsOneWidget);
    });

    testWidgets('does not play again when the message comes back on screen', (
      tester,
    ) async {
      final event = effectEvent(MessageEffect.balloons);
      await pumpMessage(tester, event);
      await tester.pump();
      expect(host(tester).plays, 1);
      await tester.pump(const Duration(seconds: 6));

      // Leaving the chat and coming back builds everything anew.
      await tester.pumpWidget(const SizedBox());
      await pumpMessage(tester, event);
      await tester.pump();
      expect(host(tester).plays, 0);
    });

    testWidgets('plays again when the menu asks for a replay', (tester) async {
      final event = effectEvent(MessageEffect.confetti);
      await pumpMessage(tester, event);
      await tester.pump();
      await tester.pump(const Duration(seconds: 6));
      expect(host(tester).plays, 1);

      replayMessageEffect(event);
      await tester.pump();
      expect(host(tester).plays, 2);
      expect(host(tester).playing, MessageEffect.confetti);
      // A replay asked for another message is not this one's.
      replayMessageEffect(effectEvent(MessageEffect.confetti, id: '\$other'));
      await tester.pump();
      expect(host(tester).plays, 2);
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a message without an effect plays nothing', (tester) async {
      await pumpMessage(
        tester,
        Event(
          content: {'msgtype': 'm.text', 'body': 'Plain'},
          type: EventTypes.Message,
          eventId: '\$plain',
          senderId: '@alice:example.org',
          originServerTs: DateTime.now(),
          status: EventStatus.synced,
          room: room,
        ),
      );
      await tester.pump();
      expect(host(tester).plays, 0);
      expect(find.byType(EffectBubble), findsNothing);
    });
  });

  group('reduced motion', () {
    testWidgets('shows a static badge instead of the effect', (tester) async {
      await pumpMessage(
        tester,
        effectEvent(MessageEffect.fireworks),
        reducedMotion: true,
      );
      await tester.pump();
      expect(host(tester).plays, 0);
      expect(find.text('Sent with Fireworks'), findsOneWidget);
    });

    testWidgets('with motion there is no badge', (tester) async {
      await pumpMessage(tester, effectEvent(MessageEffect.fireworks));
      await tester.pump();
      expect(find.text('Sent with Fireworks'), findsNothing);
      await tester.pump(const Duration(seconds: 7));
    });

    testWidgets('a bubble effect holds still', (tester) async {
      await pumpMessage(
        tester,
        effectEvent(MessageEffect.slam),
        reducedMotion: true,
      );
      await tester.pump();
      expect(find.text('Sent with Slam'), findsOneWidget);
      expect(
        tester.state<EffectBubbleState>(find.byType(EffectBubble)).plays,
        0,
      );
      expect(tester.hasRunningAnimations, isFalse);
    });
  });

  group('bubble effects', () {
    for (final effect in [
      MessageEffect.slam,
      MessageEffect.loud,
      MessageEffect.gentle,
    ]) {
      testWidgets('${effect.name} moves the bubble and puts it back', (
        tester,
      ) async {
        await pumpMessage(tester, effectEvent(effect, body: 'Hey'));
        final text = find.text('Hey', findRichText: true);
        await tester.pump(const Duration(milliseconds: 150));
        final moving = tester.getRect(text);
        await tester.pump(const Duration(seconds: 3));
        // Slam's ring over the conversation starts as the bubble lands.
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        final resting = tester.getRect(text);
        expect(moving, isNot(resting));
        expect(
          tester.state<EffectBubbleState>(find.byType(EffectBubble)).plays,
          1,
        );
        expect(tester.hasRunningAnimations, isFalse);
      });
    }

    testWidgets('slam knocks the conversation when it lands', (tester) async {
      await pumpMessage(tester, effectEvent(MessageEffect.slam));
      await tester.pump(const Duration(milliseconds: 100));
      expect(host(tester).plays, 0);
      await tester.pump(const Duration(milliseconds: 250));
      expect(host(tester).playing, MessageEffect.slam);
      await tester.pump(const Duration(seconds: 2));
    });
  });

  group('invisible ink', () {
    InvisibleInkState ink(WidgetTester tester) =>
        tester.state<InvisibleInkState>(find.byType(InvisibleInk));

    testWidgets('hides the text until it is touched, then hides it again', (
      tester,
    ) async {
      final handle = tester.ensureSemantics();
      await pumpMessage(
        tester,
        effectEvent(MessageEffect.invisibleInk, body: 'The password'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(ink(tester).isHidden, isTrue);
      expect(host(tester).plays, 0);
      // Hidden from a screen reader too.
      expect(
        find.bySemanticsLabel('Hidden with Invisible Ink. Touch to reveal.'),
        findsOneWidget,
      );
      expect(find.bySemanticsLabel(RegExp('The password')), findsNothing);
      final blur = find.descendant(
        of: find.byType(InvisibleInk),
        matching: find.byType(ImageFiltered),
      );
      expect(tester.widget<ImageFiltered>(blur).enabled, isTrue);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InvisibleInk)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(ink(tester).isRevealed, isTrue);
      expect(tester.widget<ImageFiltered>(blur).enabled, isFalse);
      expect(find.bySemanticsLabel(RegExp('The password')), findsOneWidget);

      await gesture.up();
      await tester.pump(InvisibleInk.concealAfter - const Duration(seconds: 1));
      expect(ink(tester).isRevealed, isTrue);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(ink(tester).isHidden, isTrue);
      expect(tester.widget<ImageFiltered>(blur).enabled, isTrue);
      handle.dispose();
    });
  });

  group('the send button', () {
    Future<List<Object>> pumpSendButton(WidgetTester tester, Room room) async {
      final log = <Object>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => IconButton(
                icon: const Icon(Icons.send_outlined),
                onPressed: () {},
                onLongPress: () => onSendLongPress(
                  context,
                  effectsAvailable: canSendMessageEffects(room),
                  text: 'Happy birthday',
                  bubbleColor: Colors.green,
                  onBubbleColor: Colors.white,
                  send: log.add,
                  fallback: () => log.add('options'),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpUntilBuilt(tester);
      await tester.longPress(find.byType(IconButton));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      return log;
    }

    testWidgets('a long press opens the picker in an iMessage chat', (
      tester,
    ) async {
      final log = await pumpSendButton(tester, iMessage);
      expect(find.byType(MessageEffectPicker), findsOneWidget);
      expect(find.text('Send with effect'), findsOneWidget);
      // The message is previewed with the first effect.
      expect(find.text('Happy birthday'), findsOneWidget);
      expect(find.byType(EffectBubble), findsOneWidget);
      expect(log, isEmpty);
      // Let the preview's effect run out.
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('a long press elsewhere does what it did before', (
      tester,
    ) async {
      final log = await pumpSendButton(tester, whatsApp);
      expect(find.byType(MessageEffectPicker), findsNothing);
      expect(log, ['options']);
    });

    testWidgets('each option sends the message with its effect', (
      tester,
    ) async {
      final log = await pumpSendButton(tester, iMessage);
      await tester.pump(const Duration(seconds: 3));
      await tester.tap(find.text('Screen'));
      await tester.pump();
      for (final effect in MessageEffect.ofKind(MessageEffectKind.screen)) {
        await tester.scrollUntilVisible(
          find.byKey(ValueKey('send_effect_${effect.name}')),
          60,
          scrollable: find.descendant(
            of: find.byType(MessageEffectPicker),
            matching: find.byType(Scrollable),
          ),
        );
      }
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byKey(const ValueKey('effect_lasers')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      await tester.tap(find.byKey(const ValueKey('send_effect_lasers')));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(log, [MessageEffect.lasers]);
      expect(find.byType(MessageEffectPicker), findsNothing);
    });
  });
}
