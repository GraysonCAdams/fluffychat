// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

/// Renders each fixture in `fixtures/` with the app's real pages and
/// compares it with `goldens/<screen>.png`. `--update-goldens` rewrites
/// them. See README.md in this folder.
library;

import 'package:fluffychat/config/themes.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'harness.dart';
import 'screens/chat.dart';
import 'screens/chat_list.dart';
import 'screens/desktop.dart';
import 'screens/new_chat.dart';

/// A screen that waits on something that never comes fails instead of
/// hanging the run.
const _timeout = Timeout(Duration(minutes: 3));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(loadParityFonts);

  test('the device seed gives the reference phone\'s accent colours', () {
    final scheme = ColorScheme.fromSeed(
      seedColor: deviceSeed,
      brightness: Brightness.dark,
      dynamicSchemeVariant: DynamicSchemeVariant.rainbow,
    );
    expect(scheme.primary, const Color(0xFFB0C6FF));
    expect(scheme.primaryContainer, const Color(0xFF18438F));
    expect(scheme.secondaryContainer, const Color(0xFF404659));
  });

  testWidgets('text renders in the app font, not a fallback', (tester) async {
    const sample = 'Hamburgefonstiv';
    await tester.pumpWidget(
      Builder(
        builder: (context) => MaterialApp(
          theme: FluffyThemes.buildTheme(context, Brightness.dark, deviceSeed),
          home: const Material(
            child: Column(
              children: [
                Text(sample),
                // A family nobody loaded falls back to the test font.
                Text(sample, style: TextStyle(fontFamily: 'NotLoaded')),
              ],
            ),
          ),
        ),
      ),
    );
    final texts = find.text(sample);
    final paragraph = tester.renderObject<RenderParagraph>(texts.first);
    expect(paragraph.text.style?.fontFamily, appFontFamily);
    expect(
      tester.getSize(texts.first).width,
      isNot(closeTo(tester.getSize(texts.last).width, 1)),
    );
  });

  for (final screen in [
    'chat-list',
    'chat-list-selected',
    'chat-list-search',
    'network-menu',
  ]) {
    testWidgets(screen, (tester) async {
      await _withShadows(
        () => pumpChatListScreen(tester, ParityFixture.load(screen)),
      );
    }, timeout: _timeout);
  }

  for (final screen in ['chat-dm', 'chat-dm-linked']) {
    testWidgets(screen, (tester) async {
      await _withShadows(
        () => pumpChatScreen(tester, ParityFixture.load(screen)),
      );
    }, timeout: _timeout);
  }

  for (final screen in ['new-chat', 'new-chat-results']) {
    testWidgets(screen, (tester) async {
      await _withShadows(
        () => pumpNewChatScreen(tester, ParityFixture.load(screen)),
      );
    }, timeout: _timeout);
  }

  // The Windows app's window, so Flutter's own widgets behave as on
  // Windows too (scroll bars, text selection, tooltips).
  testWidgets(
    'desktop',
    (tester) async {
      await _withShadows(() => pumpDesktopScreen(tester));
    },
    variant: TargetPlatformVariant.only(TargetPlatform.windows),
    timeout: _timeout,
  );
}

/// Runs [body] with elevation shadows drawn as on a device, not as the
/// solid outlines widget tests draw by default. The test framework checks
/// that the flag is back to its default when the test body ends.
Future<void> _withShadows(Future<void> Function() body) async {
  debugDisableShadows = false;
  try {
    await body();
  } finally {
    debugDisableShadows = true;
  }
}
