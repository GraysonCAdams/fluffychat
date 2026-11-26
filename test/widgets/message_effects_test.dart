// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/invisible_ink.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_bubble.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_picker.dart';
import 'package:fluffychat/pages/chat/effects/played_message_effects.dart';
import 'package:fluffychat/pages/chat/effects/screen_effect_host.dart';
import 'package:fluffychat/pages/chat/effects/screen_effect_scenes.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/utils/effect_haptics.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
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

/// A canvas that draws nothing and keeps the names of the calls made on
/// it, with the arguments of the last `drawAtlas`.
class _RecordingCanvas implements Canvas {
  final calls = <String>[];
  List<Object?>? atlas;

  @override
  dynamic noSuchMethod(Invocation invocation) {
    final name = invocation.memberName.toString().split('"')[1];
    calls.add(name);
    if (name == 'drawAtlas') atlas = invocation.positionalArguments;
    return null;
  }
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
      // Nothing of the content is painted, blurred or otherwise: it is
      // clipped away whole, and the specks lie over the bare bubble.
      final clip = find.byKey(const ValueKey('invisible_ink_content'));
      final size = tester.getSize(clip);
      Rect shown() =>
          tester.widget<ClipPath>(clip).clipper!.getClip(size).getBounds();
      expect(shown().isEmpty, isTrue);
      for (final type in [ImageFiltered, ShaderMask, BackdropFilter]) {
        expect(
          find.descendant(
            of: find.byType(InvisibleInk),
            matching: find.byType(type),
          ),
          findsNothing,
        );
      }
      final particles = find.byKey(const ValueKey('invisible_ink_particles'));
      expect(particles, findsOneWidget);

      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InvisibleInk)),
      );
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      await tester.pump();
      expect(ink(tester).isRevealed, isTrue);
      expect(shown(), Offset.zero & size);
      expect(particles, findsNothing);
      expect(find.bySemanticsLabel(RegExp('The password')), findsOneWidget);

      await gesture.up();
      await tester.pump(InvisibleInk.concealAfter - const Duration(seconds: 1));
      expect(ink(tester).isRevealed, isTrue);
      await tester.pump(const Duration(seconds: 1));
      await tester.pump(const Duration(seconds: 2));
      await tester.pump();
      expect(ink(tester).isHidden, isTrue);
      expect(shown().isEmpty, isTrue);
      expect(particles, findsOneWidget);
      handle.dispose();
    });

    testWidgets('the reveal opens from the finger', (tester) async {
      await pumpMessage(
        tester,
        effectEvent(MessageEffect.invisibleInk, body: 'The password'),
      );
      final clip = find.byKey(const ValueKey('invisible_ink_content'));
      final size = tester.getSize(clip);
      final gesture = await tester.startGesture(
        tester.getTopLeft(find.byType(InvisibleInk)) + const Offset(20, 12),
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 40));
      final shown = tester
          .widget<ClipPath>(clip)
          .clipper!
          .getClip(size)
          .getBounds();
      expect(shown.center.dx, moreOrLessEquals(20, epsilon: 0.01));
      expect(shown.center.dy, moreOrLessEquals(12, epsilon: 0.01));
      expect(shown.width, greaterThan(0));
      expect(shown.width, lessThan(size.width));
      await gesture.up();
      await tester.pump(const Duration(seconds: 8));
    });

    const bubble = Size(180, 44);
    const white = Color(0xFFFFFFFF);

    test('the specks are many, small and sharp', () {
      final particles = InkParticles(math.Random(3));
      for (final dpr in [1.0, 2.0, 2.625]) {
        final n = particles.layout(bubble, 1.3, white, devicePixelRatio: dpr);
        // Many hundreds over a one line bubble.
        expect(n, InkParticles.countFor(bubble));
        expect(n, greaterThan(1200));
        for (var i = 0; i < n; i++) {
          final [left, top, right, _, _, bottom, ...] = particles.positions
              .sublist(i * 8, i * 8 + 8);
          // Square, a pixel or a pixel and a half across.
          expect(right - left, closeTo(bottom - top, 1e-4));
          expect(right - left, inInclusiveRange(1 - 1e-4, 1.5 + 0.5 / dpr));
          // Every edge on a physical pixel.
          for (final edge in [left, top, right, bottom]) {
            expect(edge * dpr, closeTo((edge * dpr).roundToDouble(), 1e-3));
          }
        }
      }
    });

    test('the specks twinkle and drift slowly', () {
      final particles = InkParticles(math.Random(3));
      int alphaOf(int i) => particles.colors[i * 4] >>> 24;
      final n = particles.layout(bubble, 2, white);
      final before = [for (var i = 0; i < n; i++) alphaOf(i)];
      final home = Float32List.fromList(particles.positions);
      // No two frames alike: within a quarter second most specks have
      // changed brightness, and some are near dark while others are full.
      particles.layout(bubble, 2.25, white);
      final after = [for (var i = 0; i < n; i++) alphaOf(i)];
      var changed = 0;
      for (var i = 0; i < n; i++) {
        if ((after[i] - before[i]).abs() > 8) changed++;
      }
      expect(changed, greaterThan(n ~/ 2));
      expect(after.reduce(math.min), lessThan(70));
      expect(after.reduce(math.max), greaterThan(240));
      // A whole second moves a speck a few pixels at most.
      particles.layout(bubble, 3, white);
      var moved = 0;
      for (var i = 0; i < n; i++) {
        final dx = particles.positions[i * 8] - home[i * 8];
        final dy = particles.positions[i * 8 + 1] - home[i * 8 + 1];
        expect(dx.abs() + dy.abs(), lessThanOrEqualTo(10));
        if (dx != 0 || dy != 0) moved++;
      }
      expect(moved, greaterThan(n ~/ 4));
    });

    test('a frame of ink is one draw call and builds no image', () {
      final particles = InkParticles(math.Random(3));
      for (final time in [0.0, 0.5, 7.25]) {
        final canvas = _RecordingCanvas();
        particles.paint(canvas, bubble, time, white, devicePixelRatio: 2.625);
        expect(canvas.calls, ['drawVertices']);
      }
    });

    test('an opening reveal clears the specks inside it', () {
      final particles = InkParticles(math.Random(3));
      const center = Offset(60, 22);
      final all = particles.layout(bubble, 1, white);
      final left = particles.layout(
        bubble,
        1,
        white,
        clearCenter: center,
        clearRadius: 30,
      );
      expect(left, lessThan(all - 200));
      for (var i = 0; i < left; i++) {
        final at = Offset(
          particles.positions[i * 8] + 0.5,
          particles.positions[i * 8 + 1] + 0.5,
        );
        expect((at - center).distance, greaterThan(29));
      }
    });
  });

  group('haptics', () {
    /// Every call that sent something to the vibrator.
    late List<MethodCall> played;

    /// What the stand-in vibrator says it can do.
    late HapticCapabilities vibrator;

    setUp(() {
      played = [];
      vibrator = HapticCapabilities.pixel;
      EffectHaptics.instance = EffectHaptics();
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(EffectHaptics.channel, (call) async {
            if (call.method == 'capabilities') {
              return {
                'primitives': {
                  for (final MapEntry(:key, :value)
                      in vibrator.primitives.entries)
                    key.name: value.inMilliseconds,
                },
                'amplitudeControl': vibrator.amplitudeControl,
              };
            }
            played.add(call);
            return true;
          });
    });

    tearDown(
      () => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(EffectHaptics.channel, null),
    );

    /// A `compose` call as the vibrator plays it: each primitive with the
    /// millisecond it starts on, one after the other.
    List<(String, int)> composed(MethodCall call) {
      expect(call.method, 'compose');
      final beats = <(String, int)>[];
      var cursor = 0;
      for (final step in call.arguments as List) {
        final [name as String, _, delay as int] = step as List;
        cursor += delay;
        beats.add((name, cursor));
        cursor += vibrator
            .primitives[HapticPrimitive.values.byName(name)]!
            .inMilliseconds;
      }
      return beats;
    }

    List<double> scalesOf(MethodCall call) => [
      for (final step in call.arguments as List) (step as List)[1] as double,
    ];

    /// The strength of a `waveform` call [ms] in.
    int amplitudeAt(MethodCall call, int ms) {
      final timings = ((call.arguments as Map)['timings'] as List).cast<int>();
      final amplitudes = ((call.arguments as Map)['amplitudes'] as List)
          .cast<int>();
      var cursor = 0;
      for (var i = 0; i < timings.length; i++) {
        cursor += timings[i];
        if (ms < cursor) return amplitudes[i];
      }
      return 0;
    }

    /// The scene the host plays first for [effect] in these tests.
    T sceneOf<T extends EffectScene>(MessageEffect effect) =>
        EffectScene.of(
              effect,
              EffectPalette.of(ThemeData()),
              const EffectOrigin(),
            )!
            as T;

    List<(String, int)> beats(String primitive, List<int> ms) => [
      for (final at in ms) (primitive, at),
    ];

    // Each effect's beats as a Pixel plays them, worked out by hand from
    // the timings its animation is written with.
    final expected = <MessageEffect, List<(String, int)>>{
      // The scene starts on the frame the bubble lands.
      MessageEffect.slam: beats('thud', [0]),
      // Grown at 180 ms: the 150 ms rise ends there and the thud starts.
      // Then a tick on each shake to the right (11 a second) from the
      // first after the thud's 300 ms until the bubble shrinks at 900 ms.
      MessageEffect.loud: [
        ('quickRise', 30),
        ('thud', 180),
        ...beats('tick', [568, 659, 750, 840]),
      ],
      // The lamp strikes at 700 ms, where the 500 ms rise ends; the
      // pool opens out at 3700 ms, where the 150 ms rise ends.
      MessageEffect.spotlight: [
        ('slowRise', 200),
        ('click', 700),
        ('quickRise', 3550),
        ('click', 3700),
      ],
      // The star lands 350 + 1450 ms in.
      MessageEffect.shootingStar: [('slowRise', 1300), ('click', 1800)],
      // Two heartbeats, then the heart lets go.
      MessageEffect.love: [
        ...beats('thud', [100, 420, 860, 1180]),
        ('lowTick', 1550),
      ],
      // The glow gathers until the beams come on at 800 ms, then 22
      // pulses 150 ms apart, a click on every fourth, and a click as the
      // beams go off at 4100 ms.
      MessageEffect.lasers: [
        ('slowRise', 300),
        for (var i = 0; i < 22; i++)
          (i % 4 == 0 ? 'click' : 'tick', 800 + i * 150),
        ('click', 4100),
      ],
      // A low tick as each shell leaves the ground, 450 ms before the
      // thud of its burst.
      MessageEffect.fireworks: [
        for (final burst in [500, 1300, 2100, 2900, 3800, 4600]) ...[
          ('lowTick', burst - 450),
          ('thud', burst),
        ],
      ],
    };

    for (final MapEntry(key: effect, value: pattern) in expected.entries) {
      testWidgets('${effect.name} is felt on its beats when it plays', (
        tester,
      ) async {
        await pumpMessage(tester, effectEvent(effect));
        // Slam is felt as it lands, a moment into the play.
        if (effect == MessageEffect.slam) {
          await tester.pump(const Duration(milliseconds: 200));
          expect(played, isEmpty);
          await tester.pump(const Duration(milliseconds: 150));
        } else {
          await tester.pump();
        }
        expect(played, hasLength(1));
        expect(composed(played.single), pattern);
        await tester.pump(const Duration(seconds: 7));
        await tester.pump();
        expect(played, hasLength(1));
      });
    }

    testWidgets('echo ticks once for every copy, as it comes up', (
      tester,
    ) async {
      await pumpMessage(tester, effectEvent(MessageEffect.echo));
      await tester.pump();
      final scene = sceneOf<EchoScene>(MessageEffect.echo);
      final ticks = composed(played.single);
      expect(ticks, hasLength(scene.copyCount));
      expect(ticks.length, greaterThan(20));
      expect(ticks.every((tick) => tick.$1 == 'tick'), isTrue);
      expect(ticks, hasLength(48));
      // Spread over the 1150 ms the copies come up in, never two at once.
      expect(ticks.first.$2, lessThan(30));
      expect(ticks.last.$2, inInclusiveRange(1100, 1150));
      for (var i = 1; i < ticks.length; i++) {
        expect(ticks[i].$2 - ticks[i - 1].$2, greaterThanOrEqualTo(10));
      }
      // Every one strong enough to be felt, the large copies firmer.
      final scales = scalesOf(played.single);
      expect(scales.reduce(math.min), greaterThanOrEqualTo(0.3));
      expect(scales.reduce(math.max), greaterThan(0.6));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a copy of echo is on screen from the frame of its tick', (
      tester,
    ) async {
      final scene = sceneOf<EchoScene>(MessageEffect.echo);
      final first = scene.haptics.beats
          .map((beat) => beat.at.inMicroseconds / 1e6)
          .reduce(math.min);
      // Nothing a moment before the tick; a frame after it one copy,
      // already more than half there.
      final before = _RecordingCanvas();
      scene.paint(before, const Size(360, 720), first - 0.005);
      expect(before.calls, isNot(contains('drawAtlas')));
      final after = _RecordingCanvas();
      scene.paint(after, const Size(360, 720), first + 0.017);
      expect(after.calls.where((call) => call == 'drawAtlas'), hasLength(1));
      final [_, transforms as List, _, colors as List, ...] = after.atlas!;
      expect(transforms, hasLength(1));
      expect((colors.single as Color).a, greaterThan(0.5));
      scene.dispose();
    });

    testWidgets('balloons are felt once each, as each is let go', (
      tester,
    ) async {
      await pumpMessage(tester, effectEvent(MessageEffect.balloons));
      await tester.pump();
      final scene = sceneOf<BalloonsScene>(MessageEffect.balloons);
      final felt = composed(played.single);
      expect(felt, hasLength(scene.balloonCount));
      expect(felt, hasLength(10));
      // The near one is a click, the rest ticks.
      expect(felt.where((beat) => beat.$1 == 'click'), hasLength(1));
      expect(felt.where((beat) => beat.$1 == 'tick'), hasLength(9));
      expect(felt.last.$2, inInclusiveRange(1000, 1400));
      // No two let go together.
      for (var i = 1; i < felt.length; i++) {
        expect(felt[i].$2 - felt[i - 1].$2, greaterThanOrEqualTo(30));
      }
      // The balloons differ in size, so the ticks differ in strength.
      expect(scalesOf(played.single).toSet().length, greaterThan(7));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('a balloon comes over the edge on the frame of its tick', (
      tester,
    ) async {
      final scene = sceneOf<BalloonsScene>(MessageEffect.balloons);
      final first = scene.haptics.beats
          .map((beat) => beat.at.inMicroseconds / 1e6)
          .reduce(math.min);
      int drawnAt(double t) {
        final canvas = _RecordingCanvas();
        scene.paint(canvas, const Size(360, 720), t);
        // Each balloon has one highlight, an oval.
        return canvas.calls.where((call) => call == 'drawOval').length;
      }

      expect(drawnAt(first - 0.005), 0);
      expect(drawnAt(first + 0.017), 1);
    });

    testWidgets('confetti rumbles for as long as it falls', (tester) async {
      await pumpMessage(tester, effectEvent(MessageEffect.confetti));
      await tester.pump();
      final rumble = composed(played.single);
      expect(rumble.length, greaterThan(45));
      expect(rumble.first.$2, lessThan(400));
      expect(rumble.last.$2, greaterThan(3600));
      expect(rumble.last.$2 - rumble.first.$2, greaterThan(3300));
      for (var i = 1; i < rumble.length; i++) {
        expect(rumble[i].$2 - rumble[i - 1].$2, lessThanOrEqualTo(90));
      }
      // Textured: sharp and low ticks in turn, at many strengths, weak
      // while the first pieces fall, strongest while the air is fullest
      // around two seconds in, and weak again at the end.
      expect(rumble.map((beat) => beat.$1).toSet(), {'tick', 'lowTick'});
      final scales = scalesOf(played.single);
      expect(scales.toSet().length, greaterThan(20));
      final strongest = scales.indexOf(scales.reduce(math.max));
      expect(rumble[strongest].$2, inInclusiveRange(1400, 2600));
      expect(scales.first, lessThan(scales[strongest] - 0.3));
      expect(scales.last, lessThan(scales[strongest] - 0.3));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('confetti is a grainy hum where there are no primitives', (
      tester,
    ) async {
      vibrator = const HapticCapabilities(amplitudeControl: true);
      await pumpMessage(tester, effectEvent(MessageEffect.confetti));
      await tester.pump();
      final hum = played.single;
      expect(hum.method, 'waveform');
      final timings = ((hum.arguments as Map)['timings'] as List).cast<int>();
      expect(timings.reduce((a, b) => a + b), greaterThan(3600));
      // Every other 20 ms step is half as strong as the one before it.
      // (Sampled between the ticks, which are pulses on top of the hum.)
      expect(amplitudeAt(hum, 2050), greaterThan(60));
      expect(amplitudeAt(hum, 2070), closeTo(amplitudeAt(hum, 2050) / 2, 4));
      await tester.pump(const Duration(seconds: 6));
    });

    testWidgets('celebration crackles while the sparkler burns', (
      tester,
    ) async {
      await pumpMessage(tester, effectEvent(MessageEffect.celebration));
      await tester.pump();
      final crackle = composed(played.single);
      expect(crackle.first, ('click', 200));
      expect(crackle.length, greaterThan(30));
      expect(crackle.last.$2, inInclusiveRange(3300, 3500));
      await tester.pump(const Duration(seconds: 6));
    });

    group('gentle swells as the bubble grows', () {
      // The bubble starts to grow at 288 ms, grows fastest at 1344 ms and
      // is full size at 2400 ms.
      testWidgets('as a rising and falling strength where it can vary', (
        tester,
      ) async {
        await pumpMessage(tester, effectEvent(MessageEffect.gentle));
        await tester.pump();
        final swell = played.single;
        expect(swell.method, 'waveform');
        expect(amplitudeAt(swell, 200), 0);
        final levels = [
          for (var ms = 300; ms <= 2380; ms += 40) amplitudeAt(swell, ms),
        ];
        final peak = levels.indexOf(levels.reduce(math.max));
        expect(300 + peak * 40, closeTo(1344, 60));
        expect(levels[peak], closeTo(EffectBubble.gentleSwell * 255, 2));
        for (var i = 1; i < levels.length; i++) {
          if (i <= peak) {
            expect(levels[i], greaterThanOrEqualTo(levels[i - 1]));
          } else {
            expect(levels[i], lessThanOrEqualTo(levels[i - 1]));
          }
        }
        expect(levels.first, lessThan(5));
        expect(levels.last, lessThan(5));
        expect(amplitudeAt(swell, 2420), 0);
        await tester.pump(const Duration(seconds: 3));
      });

      testWidgets('as a rise and a fall with primitives only', (tester) async {
        vibrator = HapticCapabilities(
          primitives: HapticCapabilities.pixel.primitives,
        );
        await pumpMessage(tester, effectEvent(MessageEffect.gentle));
        await tester.pump();
        expect(composed(played.single), [
          ('slowRise', 844),
          ('quickFall', 1344),
        ]);
        await tester.pump(const Duration(seconds: 3));
      });

      testWidgets('as one tick at its height on a plain vibrator', (
        tester,
      ) async {
        vibrator = const HapticCapabilities();
        await pumpMessage(tester, effectEvent(MessageEffect.gentle));
        await tester.pump();
        expect(played.single.method, 'waveform');
        expect(played.single.arguments, {
          'timings': [1344, 10],
        });
        await tester.pump(const Duration(seconds: 3));
      });
    });

    testWidgets('lasers leave the bubble out of the dark and the beams', (
      tester,
    ) async {
      const size = Size(360, 720);
      const bubble = Rect.fromLTWH(200, 560, 148, 44);
      final scene = LasersScene(
        EffectPalette.of(ThemeData()),
        const EffectOrigin(rect: bubble),
        7,
      );
      // The pulses are the moments the beams are brightest.
      for (final t in [0.5, ...scene.pulseTimes, 4.15]) {
        final recorder = ui.PictureRecorder();
        scene.paint(Canvas(recorder), size, t + 0.02);
        final image = recorder.endRecording().toImageSync(360, 720);
        final pixels = (await tester.runAsync(
          () => image.toByteData(format: ui.ImageByteFormat.rawRgba),
        ))!;
        int alphaAt(Offset at) =>
            pixels.getUint8((at.dy.toInt() * 360 + at.dx.toInt()) * 4 + 3);
        // Nothing at all is painted over the bubble, corner to corner
        // inside its rounded outline.
        for (final at in [
          bubble.center,
          bubble.centerLeft + const Offset(4, 0),
          bubble.centerRight - const Offset(4, 0),
          bubble.topCenter + const Offset(0, 3),
          bubble.bottomCenter - const Offset(0, 3),
          bubble.topLeft + const Offset(10, 10),
          bubble.bottomRight - const Offset(10, 10),
        ]) {
          expect(alphaAt(at), 0, reason: 'painted over the bubble at $at');
        }
        // The room around it is dark and lit.
        expect(
          alphaAt(bubble.topCenter - const Offset(0, 6)),
          greaterThan(150),
        );
        expect(alphaAt(const Offset(40, 80)), greaterThan(150));
        image.dispose();
      }
    });

    testWidgets('nothing more is felt when the message rebuilds', (
      tester,
    ) async {
      late VoidCallback rebuild;
      await pumpMessage(
        tester,
        effectEvent(MessageEffect.fireworks),
        rebuild: (r) => rebuild = r,
      );
      await tester.pump();
      expect(played, hasLength(1));
      await tester.pump(const Duration(seconds: 7));
      rebuild();
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(played, hasLength(1));
    });

    testWidgets('a replay is felt again', (tester) async {
      final event = effectEvent(MessageEffect.love);
      await pumpMessage(tester, event);
      await tester.pump();
      await tester.pump(const Duration(seconds: 5));
      expect(played, hasLength(1));
      replayMessageEffect(event);
      await tester.pump();
      expect(played.map(composed), [
        expected[MessageEffect.love],
        expected[MessageEffect.love],
      ]);
      await tester.pump(const Duration(seconds: 5));
    });

    for (final effect in [
      MessageEffect.fireworks,
      MessageEffect.slam,
      MessageEffect.gentle,
    ]) {
      testWidgets('reduced motion is not felt (${effect.name})', (
        tester,
      ) async {
        await pumpMessage(tester, effectEvent(effect), reducedMotion: true);
        await tester.pump(const Duration(seconds: 1));
        replayMessageEffect(effectEvent(effect));
        await tester.pump(const Duration(seconds: 1));
        expect(played, isEmpty);
      });
    }

    testWidgets('nothing is felt on desktop', (tester) async {
      await pumpMessage(tester, effectEvent(MessageEffect.fireworks));
      await tester.pump();
      expect(host(tester).plays, 1);
      await tester.pump(const Duration(seconds: 7));
      expect(played, isEmpty);
    }, variant: TargetPlatformVariant.desktop());

    testWidgets('invisible ink ticks while a swipe reveals it', (tester) async {
      await pumpMessage(
        tester,
        effectEvent(MessageEffect.invisibleInk, body: 'The password'),
      );
      await tester.pump(const Duration(milliseconds: 100));
      expect(played, isEmpty);
      final start = tester.getCenter(find.byType(InvisibleInk));
      final gesture = await tester.startGesture(start - const Offset(40, 0));
      await tester.pump();
      expect(played.map(composed), [
        beats('tick', [0]),
      ]);
      // Shorter than a tick's distance: nothing.
      await gesture.moveBy(const Offset(6, 0));
      await tester.pump();
      expect(played, hasLength(1));
      for (var i = 0; i < 4; i++) {
        await gesture.moveBy(const Offset(InvisibleInk.tickDistance, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(played, hasLength(5));
      // Once the ink has cleared, swiping over it is not felt.
      await tester.pump(const Duration(seconds: 1));
      expect(
        tester.state<InvisibleInkState>(find.byType(InvisibleInk)).isRevealed,
        isTrue,
      );
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(-InvisibleInk.tickDistance, 0));
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(played, hasLength(5));
      await gesture.up();
      await tester.pump(const Duration(seconds: 8));
    });

    testWidgets('invisible ink does not tick under reduced motion', (
      tester,
    ) async {
      await pumpMessage(
        tester,
        effectEvent(MessageEffect.invisibleInk, body: 'The password'),
        reducedMotion: true,
      );
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(InvisibleInk)),
      );
      await gesture.moveBy(const Offset(30, 0));
      await gesture.up();
      await tester.pump(const Duration(seconds: 6));
      expect(played, isEmpty);
    });

    testWidgets('previews in the picker are felt', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: const Scaffold(
            body: MessageEffectPicker(
              text: 'Happy birthday',
              bubbleColor: Colors.green,
              onBubbleColor: Colors.white,
            ),
          ),
        ),
      );
      await pumpUntilBuilt(tester);
      // The frame on which the preview starts its clock, then its landing.
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // Slam, the first effect, previews by itself.
      expect(played.map(composed), [expected[MessageEffect.slam]]);
      await tester.tap(find.byKey(const ValueKey('effect_loud')));
      await tester.pump();
      await tester.pump();
      await tester.pump();
      expect(composed(played.last), expected[MessageEffect.loud]);
      await tester.pump(const Duration(seconds: 3));
      expect(played, hasLength(2));
    });
  });

  group('spotlight', () {
    const size = Size(360, 720);
    const bubble = Rect.fromLTWH(200, 560, 148, 44);

    SpotlightScene sceneFor({EffectOrigin? origin, int? dust}) {
      final palette = EffectPalette.of(ThemeData.dark());
      origin ??= const EffectOrigin(rect: bubble);
      return dust == null
          ? SpotlightScene(palette, origin, 7)
          : SpotlightScene(palette, origin, 7, dust: dust);
    }

    /// [scene] painted [t] seconds in over nothing: the light it adds is
    /// in the colour channels, and what it darkens in the alpha.
    Future<ByteData> frame(WidgetTester tester, EffectScene scene, double t) {
      final recorder = ui.PictureRecorder();
      scene.paint(Canvas(recorder), size, t);
      final image = recorder.endRecording().toImageSync(
        size.width.toInt(),
        size.height.toInt(),
      );
      return tester
          .runAsync(() => image.toByteData(format: ui.ImageByteFormat.rawRgba))
          .then((pixels) {
            image.dispose();
            return pixels!;
          });
    }

    int channel(ByteData pixels, int x, int y, int c) =>
        pixels.getUint8((y * size.width.toInt() + x) * 4 + c);
    int lightAt(ByteData pixels, Offset at) =>
        channel(pixels, at.dx.round(), at.dy.round(), 0);
    int darkAt(ByteData pixels, Offset at) =>
        channel(pixels, at.dx.round(), at.dy.round(), 3);

    test('the pool swings onto the bubble, runs past it and settles', () {
      final scene = sceneFor();
      final rest = scene.restRadius(size);
      // The lamp strikes with the pool short of the bubble, on the side
      // of the middle of the screen.
      final struck = scene.poolAt(size, 0.72);
      expect(bubble.center.dx - struck.dx, greaterThan(0.3 * rest));
      // It runs past the bubble before it comes back.
      final past = [
        for (var t = 0.85; t < 1.3; t += 0.02)
          scene.poolAt(size, t).dx - bubble.center.dx,
      ].reduce(math.max);
      expect(past, greaterThan(0.03 * rest));
      expect(past, lessThan(0.15 * rest));
      // Settled, the pool stays on the bubble with all of it inside.
      for (var t = 1.5; t <= 3.4; t += 0.05) {
        final at = scene.poolAt(size, t);
        expect(
          (at - bubble.center).distance,
          lessThan(0.07 * rest),
          reason: 'off the bubble at $t s',
        );
        for (final corner in [
          bubble.topLeft,
          bubble.topRight,
          bubble.bottomLeft,
          bubble.bottomRight,
        ]) {
          expect(
            (corner - at).distance,
            lessThan(scene.radiusAt(size, t) * 0.86),
            reason: 'bubble not wholly in the pool at $t s',
          );
        }
      }
    });

    test('the pool and the lamp are held by a hand, never still', () {
      final scene = sceneFor();
      final rest = scene.restRadius(size);
      for (final at in [scene.poolAt, scene.lampAt]) {
        final places = [for (var t = 1.6; t <= 3.4; t += 0.1) at(size, t)];
        for (var i = 1; i < places.length; i++) {
          final moved = (places[i] - places[i - 1]).distance;
          // Always moving, and never fast.
          expect(moved, greaterThan(0.02), reason: 'still at step $i');
          expect(moved, lessThan(0.04 * rest), reason: 'jumped at step $i');
        }
        final xs = [for (final place in places) place.dx];
        expect(
          xs.reduce(math.max) - xs.reduce(math.min),
          greaterThan(0.02 * rest),
        );
      }
    });

    testWidgets('the light is one soft shape with no edge or step in it', (
      tester,
    ) async {
      final scene = sceneFor(dust: 0);
      final around = bubble.inflate(2);
      // The strike, the swing, the hold, the drawing in and the opening.
      for (final t in [0.74, 0.8, 1.0, 2.0, 3.0, 3.6, 3.75, 3.85]) {
        final pixels = await frame(tester, scene, t);
        var lightStep = 0, darkStep = 0;
        for (var y = 0; y < size.height - 1; y++) {
          for (var x = 0; x < size.width - 1; x++) {
            if (around.contains(Offset(x.toDouble(), y.toDouble())) ||
                around.contains(Offset(x + 1, y + 1))) {
              continue;
            }
            for (final (dx, dy) in const [(1, 0), (0, 1)]) {
              lightStep = math.max(
                lightStep,
                (channel(pixels, x, y, 0) - channel(pixels, x + dx, y + dy, 0))
                    .abs(),
              );
              darkStep = math.max(
                darkStep,
                (channel(pixels, x, y, 3) - channel(pixels, x + dx, y + dy, 3))
                    .abs(),
              );
            }
          }
        }
        // A hard edge of the beam or a line across the pool is a jump of
        // tens of levels from one pixel to the next.
        expect(lightStep, lessThan(9), reason: 'an edge in the light at $t s');
        expect(darkStep, lessThan(26), reason: 'an edge in the dark at $t s');
        // Nothing is painted over the bubble.
        for (final at in [
          bubble.center,
          bubble.centerLeft + const Offset(4, 0),
          bubble.centerRight - const Offset(4, 0),
          bubble.topLeft + const Offset(10, 10),
        ]) {
          expect(darkAt(pixels, at), 0, reason: 'over the bubble at $t s');
        }
      }
    });

    testWidgets('the beam gathers to the pool and fades out to its sides', (
      tester,
    ) async {
      final scene = sceneFor(dust: 0);
      const t = 2.5;
      final pixels = await frame(tester, scene, t);
      final pool = scene.poolAt(size, t);
      final lamp = scene.lampAt(size, t);
      final axis = pool - lamp;
      final across = Offset(-axis.dy, axis.dx) / axis.distance;
      final radius = scene.radiusAt(size, t);
      final inPool = lightAt(
        pixels,
        pool - axis / axis.distance * radius * 0.5,
      );
      final nearPool = lightAt(pixels, lamp + axis * 0.7);
      final midBeam = lightAt(pixels, lamp + axis * 0.4);
      final midSide = lightAt(
        pixels,
        lamp + axis * 0.4 + across * radius * 0.3,
      );
      expect(inPool, greaterThan(nearPool));
      expect(nearPool, greaterThan(midBeam));
      expect(midBeam, greaterThan(midSide));
      expect(midSide, greaterThan(0));
      // Away from the beam there is no light, and the dark is near
      // black, deepest at the edge of the screen.
      const corner = Offset(6, 714), inward = Offset(120, 380);
      // The dark has a trace of the theme's colour in it: no light is
      // that and nothing more.
      final tint = scene.palette.scrim.r;
      for (final at in [corner, inward]) {
        expect(lightAt(pixels, at), closeTo(darkAt(pixels, at) * tint, 1.5));
      }
      expect(midSide, greaterThan(lightAt(pixels, inward) + 3));
      expect(darkAt(pixels, inward), greaterThan(205));
      expect(darkAt(pixels, corner), greaterThan(darkAt(pixels, inward)));
    });

    testWidgets('dust shows in the beam only, and glints', (tester) async {
      final dusty = sceneFor();
      final clean = sceneFor(dust: 0);
      Future<Map<int, int>> dustAt(double t) async {
        final withDust = await frame(tester, dusty, t);
        final without = await frame(tester, clean, t);
        final pool = clean.poolAt(size, t);
        final lamp = clean.lampAt(size, t);
        final axis = pool - lamp;
        final half = SpotlightScene.beamHalfAngle(
          clean.radiusAt(size, t),
          axis.distance,
        );
        final specks = <int, int>{};
        for (var y = 0; y < size.height; y++) {
          for (var x = 0; x < size.width; x++) {
            final more = channel(withDust, x, y, 0) - channel(without, x, y, 0);
            if (more < 4) continue;
            specks[y * size.width.toInt() + x] = more;
            final from = Offset(x + 0.5, y + 0.5) - lamp;
            var off = (from.direction - axis.direction).abs();
            if (off > math.pi) off = 2 * math.pi - off;
            // A speck's own size is a few pixels, a hair of angle.
            expect(off, lessThan(half + 0.03), reason: 'dust at $x,$y');
            expect(from.distance, lessThan(axis.distance * 1.1 + 4));
          }
        }
        return specks;
      }

      final first = await dustAt(2.0);
      final later = await dustAt(2.5);
      expect(first.length, greaterThan(40));
      // Half a second on, specks have brightened and dimmed in place.
      final changed = first.entries.where(
        (speck) => ((later[speck.key] ?? 0) - speck.value).abs() > 6,
      );
      expect(changed.length, greaterThan(10));
    });

    testWidgets('the light follows the bubble as the conversation scrolls', (
      tester,
    ) async {
      var place = bubble;
      final scene = sceneFor(
        origin: EffectOrigin(rect: bubble, track: () => place),
        dust: 0,
      );
      final before = scene.poolAt(size, 2.0);
      place = bubble.shift(const Offset(0, -180));
      expect(
        (scene.poolAt(size, 2.0) - before - const Offset(0, -180)).distance,
        lessThan(0.001),
      );
      final pixels = await frame(tester, scene, 2.0);
      expect(darkAt(pixels, place.center), 0);
      expect(
        lightAt(pixels, place.topCenter - const Offset(0, 12)),
        isPositive,
      );
      // Where the bubble was is lit or dark like the rest.
      expect(darkAt(pixels, bubble.center), isPositive);
    });

    testWidgets('the host asks where the bubble is on every frame', (
      tester,
    ) async {
      Rect? place = const Rect.fromLTWH(40, 300, 120, 44);
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(body: ScreenEffectHost(child: SizedBox.expand())),
        ),
      );
      final effects = host(tester);
      effects.play(
        MessageEffect.spotlight,
        globalRect: place,
        globalRectOf: () => place,
      );
      await tester.pump();
      final origin = effects.scene!.origin;
      expect(origin.now, place);
      place = place.shift(const Offset(0, -90));
      expect(origin.now, place);
      // A bubble scrolled out of the list keeps the light where it was.
      final last = place;
      place = null;
      expect(origin.now, last);
      for (var i = 0; i < 280; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(tester.takeException(), isNull);
      expect(effects.playing, isNull);
    });
  });

  group('the schedule button', () {
    Future<List<String>> pumpPicker(
      WidgetTester tester, {
      Future<bool>? canSchedule,
    }) async {
      final log = <String>[];
      await tester.pumpWidget(
        MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Builder(
              builder: (context) => TextButton(
                onPressed: () async {
                  final effect = await showMessageEffectPicker(
                    context,
                    text: 'Happy birthday',
                    bubbleColor: Colors.green,
                    onBubbleColor: Colors.white,
                    onSchedule: () => log.add('schedule'),
                    canSchedule: canSchedule,
                  );
                  log.add('closed with $effect');
                },
                child: const Text('Open'),
              ),
            ),
          ),
        ),
      );
      await pumpUntilBuilt(tester);
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 2));
      return log;
    }

    final button = find.byKey(const ValueKey('schedule_message'));

    Color backgroundOf(WidgetTester tester) => tester
        .widget<Material>(
          find.descendant(of: button, matching: find.byType(Material)).first,
        )
        .color!;

    testWidgets('is a labelled button of its own, apart from the effects', (
      tester,
    ) async {
      await pumpPicker(tester, canSchedule: Future.value(true));
      expect(button, findsOneWidget);
      expect(
        find.descendant(of: button, matching: find.text('Schedule')),
        findsOneWidget,
      );
      expect(
        find.descendant(
          of: button,
          matching: find.byIcon(Icons.schedule_outlined),
        ),
        findsOneWidget,
      );
      // Not one of the effect list's rows, and nowhere near the title:
      // under the list, past a divider.
      final list = find.descendant(
        of: find.byType(MessageEffectPicker),
        matching: find.byType(ListView),
      );
      expect(find.descendant(of: list, matching: button), findsNothing);
      final divider = find.descendant(
        of: find.byType(MessageEffectPicker),
        matching: find.byType(Divider),
      );
      expect(
        tester.getTopLeft(divider).dy,
        greaterThanOrEqualTo(tester.getBottomLeft(list).dy),
      );
      expect(
        tester.getTopLeft(button).dy,
        greaterThan(tester.getTopLeft(divider).dy),
      );
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('schedules where the homeserver can', (tester) async {
      final log = await pumpPicker(tester, canSchedule: Future.value(true));
      final scheme = Theme.of(tester.element(button)).colorScheme;
      expect(backgroundOf(tester), scheme.secondaryContainer);
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(log, ['schedule', 'closed with null']);
      expect(find.byType(MessageEffectPicker), findsNothing);
      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('is switched off and explains itself where it cannot', (
      tester,
    ) async {
      final log = await pumpPicker(tester, canSchedule: Future.value(false));
      final scheme = Theme.of(tester.element(button)).colorScheme;
      expect(backgroundOf(tester), scheme.onSurface.withValues(alpha: 0.12));
      await tester.tap(button);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // A dialog says why, and nothing is scheduled.
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(find.text('Scheduling is not available'), findsOneWidget);
      expect(
        find.text('Your homeserver does not support scheduled messages'),
        findsOneWidget,
      );
      expect(log, isEmpty);
      await tester.tap(find.text('Ok'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      // The sheet is still there to pick an effect from.
      expect(find.byType(AlertDialog), findsNothing);
      expect(find.byType(MessageEffectPicker), findsOneWidget);
      expect(log, isEmpty);
      await tester.pump(const Duration(seconds: 3));
    });

    testWidgets('asks the homeserver before it schedules', (tester) async {
      // Tapped while the answer is still on its way.
      final answer = Completer<bool>();
      final log = await pumpPicker(tester, canSchedule: answer.future);
      await tester.tap(button);
      await tester.pump();
      expect(log, isEmpty);
      answer.complete(false);
      await tester.pump();
      await tester.pump(const Duration(seconds: 1));
      expect(find.byType(AlertDialog), findsOneWidget);
      expect(log, isEmpty);
      await tester.pump(const Duration(seconds: 3));
    });
  });

  group('the send button', () {
    Future<List<Object>> pumpSendButton(WidgetTester tester, Room room) async {
      final log = <Object>[];
      // A phone's screen, so the sheet has a phone's room.
      tester.view.physicalSize = const Size(412, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
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
      await tester.scrollUntilVisible(
        find.byKey(const ValueKey('effect_lasers')),
        -60,
        scrollable: find.descendant(
          of: find.byType(MessageEffectPicker),
          matching: find.byType(Scrollable),
        ),
      );
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
