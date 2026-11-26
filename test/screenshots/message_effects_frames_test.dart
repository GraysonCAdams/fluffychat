// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Renders every message effect at several moments to PNG files under
// build/effects_frames, to look at an effect without running the app:
//
//   flutter test test/screenshots/message_effects_frames_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_bubble.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_picker.dart';
import 'package:fluffychat/pages/chat/effects/screen_effect_host.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _size = Size(360, 720);
final _out = Directory('build/effects_frames');
final _green = NetworkColors.defaults['imessage']!;

ThemeData _theme(Brightness brightness) => ThemeData(
  colorScheme: ColorScheme.fromSeed(
    seedColor: const Color(0xFF6750A4),
    brightness: brightness,
  ),
  fontFamily: 'GoogleSansFlex',
);

Widget _bubble(BuildContext context, String text, {required bool own}) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 3),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: own ? _green : scheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(20),
    ),
    child: Text(
      text,
      style: TextStyle(
        fontSize: 16,
        color: own ? Colors.white : scheme.onSurface,
      ),
    ),
  );
}

/// A short conversation whose last message arrives with [effect].
Widget _conversation(MessageEffect effect, Brightness brightness) =>
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: _theme(brightness),
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: ScreenEffectHost(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 96),
              child: Column(
                mainAxisAlignment: MainAxisAlignment.end,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  for (final (text, own) in const [
                    ('Are you still coming tonight?', false),
                    ('Leaving in ten', true),
                    ('Bring the cake', false),
                    ('And the candles', false),
                  ])
                    Align(
                      alignment: own
                          ? Alignment.centerRight
                          : Alignment.centerLeft,
                      child: _bubble(context, text, own: own),
                    ),
                  Align(
                    alignment: Alignment.centerRight,
                    child: EffectBubble(
                      effect: effect,
                      ownMessage: true,
                      autoPlay: true,
                      bubbleColor: _green,
                      onBubbleColor: Colors.white,
                      borderRadius: BorderRadius.circular(20),
                      text: 'Happy birthday!',
                      child: _bubble(context, 'Happy birthday!', own: true),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );

Future<void> _capture(WidgetTester tester, String name) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(
    find.byType(RepaintBoundary).first,
  );
  await tester.runAsync(() async {
    final image = await boundary.toImage(pixelRatio: 1.5);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File(
      '${_out.path}/$name.png',
    ).writeAsBytesSync(bytes!.buffer.asUint8List());
    image.dispose();
  });
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

  setUpAll(() async {
    _out.createSync(recursive: true);
    final loader = FontLoader('GoogleSansFlex');
    for (final weight in ['Regular', 'Medium']) {
      final file = File(
        'assets/fonts/google_sans_flex/GoogleSansFlex-$weight.ttf',
      );
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
    await loader.load();
    // The icon font ships with the Flutter SDK, beside the test engine.
    final icons = File(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
      '/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await iconLoader.load();
    }
  });

  /// The moments of each effect worth a frame, in milliseconds.
  const moments = <MessageEffect, List<int>>{
    MessageEffect.slam: [60, 180, 290, 360, 520],
    MessageEffect.loud: [120, 320, 700, 1100, 1600],
    MessageEffect.gentle: [100, 500, 1100, 1700, 2300],
    MessageEffect.invisibleInk: [100, 600],
    MessageEffect.echo: [300, 900, 1600, 2400, 3400],
    MessageEffect.spotlight: [300, 700, 1200, 2400, 3500],
    MessageEffect.balloons: [500, 1100, 1700, 2400, 3200],
    MessageEffect.confetti: [300, 800, 1400, 2200, 3200],
    MessageEffect.love: [300, 800, 1300, 2200, 3100],
    MessageEffect.lasers: [200, 800, 1600, 2800, 4000],
    MessageEffect.fireworks: [300, 600, 1300, 2700, 4600],
    MessageEffect.celebration: [300, 900, 1800, 3000, 4300],
    MessageEffect.shootingStar: [500, 1100, 1700, 2000, 2600],
  };

  for (final brightness in Brightness.values) {
    for (final effect in MessageEffect.values) {
      testWidgets('${effect.name} ${brightness.name}', (tester) async {
        tester.view.physicalSize = _size;
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(
          RepaintBoundary(child: _conversation(effect, brightness)),
        );
        await pumpUntilBuilt(tester);
        // The frame on which the effect starts its clock.
        await tester.pump();
        var elapsed = 0;
        for (final at in moments[effect]!) {
          await tester.pump(Duration(milliseconds: at - elapsed));
          elapsed = at;
          await _capture(
            tester,
            '${effect.name}_${brightness.name}_${at.toString().padLeft(4, '0')}',
          );
        }
        if (effect == MessageEffect.invisibleInk) {
          final gesture = await tester.startGesture(
            tester.getCenter(find.text('Happy birthday!')),
          );
          await tester.pump();
          await tester.pump(const Duration(milliseconds: 180));
          await _capture(tester, 'invisibleInk_${brightness.name}_reveal_0180');
          await tester.pump(const Duration(milliseconds: 500));
          await _capture(tester, 'invisibleInk_${brightness.name}_reveal_0680');
          await gesture.up();
        }
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 8));
      });
    }

    testWidgets('picker ${brightness.name}', (tester) async {
      tester.view.physicalSize = _size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
        RepaintBoundary(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: _theme(brightness),
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: FilledButton(
                    onPressed: () => showMessageEffectPicker(
                      context,
                      text: 'Happy birthday!',
                      bubbleColor: _green,
                      onBubbleColor: Colors.white,
                      onSchedule: () {},
                    ),
                    child: const Text('Open'),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await pumpUntilBuilt(tester);
      await tester.tap(find.text('Open'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 600));
      await tester.tap(find.byKey(const ValueKey('effect_loud')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 700));
      await _capture(tester, 'picker_${brightness.name}_bubble');
      await tester.tap(find.text('Screen'));
      await tester.pump();
      await tester.tap(find.byKey(const ValueKey('effect_confetti')));
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 1400));
      await _capture(tester, 'picker_${brightness.name}_screen');
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 8));
    });
  }
}
