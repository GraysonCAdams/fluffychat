// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Renders every message effect frame by frame, sixty frames to the second,
// to PNG files under build/effects_video/<effect>/, and beside them
// <effect>.haptics.txt: what a Pixel's vibrator is sent for the effect and
// when, to set against the frames. Encode a folder with ffmpeg:
//
//   flutter test test/screenshots/message_effects_video_test.dart
//   ffmpeg -framerate 60 -i build/effects_video/echo/f_%04d.png \
//     -c:v libx264 -pix_fmt yuv420p echo.mp4

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/invisible_ink.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_bubble.dart';
import 'package:fluffychat/pages/chat/effects/screen_effect_host.dart';
import 'package:fluffychat/utils/effect_haptics.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _size = Size(360, 720);
const _frame = Duration(microseconds: 16667);
final _out = Directory('build/effects_video');
final _bubbleColor = NetworkColors.defaults['imessage']!;

Widget _bubble(BuildContext context, String text, {required bool own}) {
  final scheme = Theme.of(context).colorScheme;
  return Container(
    margin: const EdgeInsets.symmetric(vertical: 3),
    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
    decoration: BoxDecoration(
      color: own ? _bubbleColor : scheme.surfaceContainerHigh,
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
Widget _conversation(MessageEffect effect) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: ThemeData(
    colorScheme: ColorScheme.fromSeed(
      seedColor: const Color(0xFF6750A4),
      brightness: Brightness.dark,
    ),
    fontFamily: 'GoogleSansFlex',
  ),
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
                  alignment: own ? Alignment.centerRight : Alignment.centerLeft,
                  child: _bubble(context, text, own: own),
                ),
              Align(
                alignment: Alignment.centerRight,
                child: EffectBubble(
                  effect: effect,
                  ownMessage: true,
                  autoPlay: true,
                  bubbleColor: _bubbleColor,
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

/// How long each effect is filmed for.
const _lengths = <MessageEffect, Duration>{
  MessageEffect.slam: Duration(milliseconds: 1300),
  MessageEffect.loud: Duration(milliseconds: 2200),
  MessageEffect.gentle: Duration(milliseconds: 2800),
  MessageEffect.invisibleInk: Duration(milliseconds: 4200),
  MessageEffect.echo: Duration(milliseconds: 4600),
  MessageEffect.spotlight: Duration(milliseconds: 4200),
  MessageEffect.balloons: Duration(milliseconds: 5400),
  MessageEffect.confetti: Duration(milliseconds: 4600),
  MessageEffect.love: Duration(milliseconds: 4400),
  MessageEffect.lasers: Duration(milliseconds: 4800),
  MessageEffect.fireworks: Duration(milliseconds: 6600),
  MessageEffect.celebration: Duration(milliseconds: 5000),
  MessageEffect.shootingStar: Duration(milliseconds: 3600),
};

/// What the vibrator was sent in one channel call made [at] milliseconds
/// into the film, a line for each haptic with its time in the film.
List<String> _describe(MethodCall call, int at) {
  String ms(num t) => '${(at + t).round().toString().padLeft(5)} ms';
  switch (call.method) {
    case 'compose':
      final lines = <String>[];
      var cursor = 0;
      for (final step in call.arguments as List) {
        final [name as String, scale as double, delay as int] = step as List;
        final primitive = HapticPrimitive.values.byName(name);
        cursor += delay;
        lines.add(
          '${ms(cursor)}  ${name.padRight(9)} scale '
          '${scale.toStringAsFixed(2)}',
        );
        cursor +=
            HapticCapabilities.pixel.primitives[primitive]!.inMilliseconds;
      }
      return lines;
    case 'waveform':
      final arguments = call.arguments as Map;
      final timings = (arguments['timings'] as List).cast<int>();
      final amplitudes = (arguments['amplitudes'] as List?)?.cast<int>();
      final lines = <String>[];
      var cursor = 0;
      for (var i = 0; i < timings.length; i++) {
        final amplitude = amplitudes?[i] ?? (i.isOdd ? 255 : 0);
        if (amplitude > 0) {
          lines.add(
            '${ms(cursor)}  waveform  amplitude '
            '${amplitude.toString().padLeft(3)}/255 for ${timings[i]} ms',
          );
        }
        cursor += timings[i];
      }
      return lines;
    default:
      return ['${ms(0)}  ${call.method} ${call.arguments}'];
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
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
  });

  for (final effect in MessageEffect.values) {
    testWidgets('films ${effect.name}', (tester) async {
      final frames = Directory('${_out.path}/${effect.name}');
      if (frames.existsSync()) frames.deleteSync(recursive: true);
      frames.createSync(recursive: true);

      // The haptics go to a stand-in for a Pixel's vibrator.
      debugDefaultTargetPlatformOverride = TargetPlatform.android;
      EffectHaptics.instance = EffectHaptics();
      final haptics = <String>[];
      var elapsed = 0.0;
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
        EffectHaptics.channel,
        (call) async {
          if (call.method == 'capabilities') {
            return {
              'primitives': {
                for (final MapEntry(:key, :value)
                    in HapticCapabilities.pixel.primitives.entries)
                  key.name: value.inMilliseconds,
              },
              'amplitudeControl': true,
            };
          }
          haptics.addAll(_describe(call, elapsed.round()));
          return true;
        },
      );
      addTearDown(
        () => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
          EffectHaptics.channel,
          null,
        ),
      );

      tester.view.physicalSize = _size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(RepaintBoundary(child: _conversation(effect)));
      for (var i = 0; i < 50 && find.byType(Scaffold).evaluate().isEmpty; i++) {
        await tester.pump(const Duration(milliseconds: 1));
      }
      // The frame on which the effect starts its clock.
      await tester.pump();

      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find.byType(RepaintBoundary).first,
      );
      final count =
          _lengths[effect]!.inMicroseconds ~/ _frame.inMicroseconds + 1;
      TestGesture? finger;
      for (var i = 0; i < count; i++) {
        if (i > 0) {
          await tester.pump(_frame);
          elapsed += _frame.inMicroseconds / 1000;
        }
        if (effect == MessageEffect.invisibleInk) {
          // A finger lands on the ink, swipes across it and lifts.
          final ink = tester.getRect(find.byType(InvisibleInk));
          if (i == 90) {
            finger = await tester.startGesture(
              ink.centerLeft + const Offset(24, 0),
            );
          } else if (i > 90 && i < 130) {
            await finger!.moveBy(const Offset(2.5, 0));
          } else if (i == 200) {
            await finger!.up();
          }
        }
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${frames.path}/f_${i.toString().padLeft(4, '0')}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }
      File('${_out.path}/${effect.name}.haptics.txt').writeAsStringSync(
        '${effect.name}: what a Pixel 10 Pro vibrator is sent, by time in '
        'the film\n${haptics.join('\n')}\n',
      );

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 8));
      debugDefaultTargetPlatformOverride = null;
    });
  }
}
