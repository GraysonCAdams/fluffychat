// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Renders the desktop media viewer mockups (desktop_viewer_mockups.dart) to
// PNG under build/desktop_viewer/: each layout at 1920x1080 with a portrait
// video playing and at 1280x800 with a landscape photo zoomed in, and the
// overlay layout's interactions frame by frame at 30 fps:
//
//   flutter test test/mockups/desktop_viewer_sheet_test.dart
//   ffmpeg -framerate 30 -i build/desktop_viewer/clip/%04d.png \
//     -c:v libx264 -pix_fmt yuv420p clip.mp4
//
// The photos are the CC0 ones in test/fixtures/pending_media.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'desktop_viewer_mockups.dart';

const _fixtures = 'test/fixtures/pending_media';
const _out = 'build/desktop_viewer';
const _frame = Duration(microseconds: 33333);

void main() {
  final bulldog = MemoryImage(
    File('$_fixtures/bulldog_life_jacket.jpg').readAsBytesSync(),
  );
  final onigiri = MemoryImage(File('$_fixtures/onigiri.jpg').readAsBytesSync());
  final dog = MemoryImage(File('$_fixtures/dog_on_deck.jpg').readAsBytesSync());

  List<MockMedia> media() => [
    MockMedia(bulldog, const Size(1024, 682)),
    MockMedia(onigiri, const Size(1024, 768)),
    MockMedia(dog, const Size(1080, 1920), video: true, label: '0:16'),
    MockMedia(bulldog, const Size(1024, 682)),
    MockMedia(onigiri, const Size(1024, 768)),
    MockMedia(dog, const Size(1080, 1920), video: true, label: '0:16'),
    MockMedia(bulldog, const Size(1024, 682)),
    MockMedia(onigiri, const Size(1024, 768)),
  ];

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
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

  final boundary = GlobalKey();

  Future<void> pumpViewer(
    WidgetTester tester,
    ViewerVariant variant,
    MockViewerState state, {
    String? caption,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        debugShowCheckedModeBanner: false,
        home: Builder(
          builder: (context) => Theme(
            data: FluffyThemes.buildTheme(context, Brightness.dark),
            child: RepaintBoundary(
              key: boundary,
              child: Column(
                children: [
                  Expanded(
                    child: Material(
                      type: MaterialType.transparency,
                      child: MockDesktopViewer(variant: variant, state: state),
                    ),
                  ),
                  if (caption != null)
                    Container(
                      height: 40,
                      color: const Color(0xFF202124),
                      alignment: Alignment.centerLeft,
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        caption,
                        style: const TextStyle(
                          fontFamily: 'GoogleSansFlex',
                          fontSize: 16,
                          color: Colors.white,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> precache(WidgetTester tester) async {
    final context = tester.element(find.byKey(boundary));
    await tester.runAsync(() async {
      for (final image in [bulldog, onigiri, dog]) {
        await precacheImage(image, context);
      }
    });
  }

  Future<void> save(WidgetTester tester, String path) async {
    await tester.runAsync(() async {
      final render =
          boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await render.toImage();
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      final file = File(path)..parent.createSync(recursive: true);
      file.writeAsBytesSync(png!.buffer.asUint8List());
    });
  }

  for (final variant in ViewerVariant.values) {
    testWidgets('${variant.name} frames', (tester) async {
      addTearDown(tester.view.reset);
      tester.view.devicePixelRatio = 1;

      tester.view.physicalSize = const Size(1920, 1080);
      final video = MockViewerState(
        media: media(),
        index: 5,
        filmstrip: true,
        position: 0.31,
        hoverVolume: true,
        hoverArrow: 1,
      );
      await pumpViewer(tester, variant, video);
      await precache(tester);
      await pumpViewer(tester, variant, video);
      await tester.pump(const Duration(seconds: 1));
      await save(tester, '$_out/${variant.name}_1920_video.png');

      tester.view.physicalSize = const Size(1280, 800);
      final photo = MockViewerState(
        media: media(),
        index: 1,
        filmstrip: true,
        zoom: 2.0,
      );
      await pumpViewer(tester, variant, photo);
      await tester.pump(const Duration(seconds: 1));
      await save(tester, '$_out/${variant.name}_1280_photo.png');
    });
  }

  testWidgets('overlay interactions, 30 fps', (tester) async {
    addTearDown(tester.view.reset);
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 840);
    final state = MockViewerState(media: media(), index: 4, position: 0.1);
    var caption = 'Photo, bars shown';
    await pumpViewer(tester, ViewerVariant.overlay, state, caption: caption);
    await precache(tester);
    var n = 0;

    Future<void> hold(double seconds) async {
      for (var i = 0; i < (seconds * 30).round(); i++) {
        if (state.current.video && state.playing) {
          state.position = (state.position + 1 / 30 / 16) % 1;
        }
        await pumpViewer(
          tester,
          ViewerVariant.overlay,
          state,
          caption: caption,
        );
        await tester.pump(_frame);
        await save(
          tester,
          '$_out/clip/${(++n).toString().padLeft(4, '0')}.png',
        );
      }
    }

    await hold(0.7);
    caption = 'Mouse over the right arrow';
    state.hoverArrow = 1;
    await hold(0.5);
    caption =
        'Right arrow, next: a portrait video, letterboxed, controls in a pill';
    state.hoverArrow = 0;
    state.index = 5;
    await hold(1.2);
    caption = 'F  shows the filmstrip below the controls, never under them';
    state.filmstrip = true;
    await hold(1.2);
    caption = 'Volume slider opens on hover';
    state.hoverVolume = true;
    await hold(0.8);
    state.hoverVolume = false;
    caption = 'Mouse rests 2.5 s: bars, arrows and cursor fade out';
    state.chrome = false;
    await hold(1.4);
    caption = 'Mouse moves: everything returns';
    state.chrome = true;
    await hold(0.8);
    caption = 'F  hides the filmstrip';
    state.filmstrip = false;
    await hold(0.7);
    caption = 'Left arrow, back to the photo';
    state.index = 4;
    await hold(0.7);
    for (final zoom in [1.6, 2.0, 2.5]) {
      caption = 'Ctrl+scroll zooms: ${(zoom * 100).round()}%';
      state.zoom = zoom;
      await hold(0.35);
    }
    await hold(0.5);
    caption = '0  fits it to the window again';
    state.zoom = null;
    await hold(1.0);
  });
}
