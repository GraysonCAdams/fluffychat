// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/media_sending_indicator.dart';
import 'package:fluffychat/pages/chat/events/pending_media_tile.dart';
import 'package:fluffychat/pages/chat/events/video_player.dart';
import 'package:fluffychat/utils/pending_media.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/pending_media_fixtures.dart';

void main() {
  Future<void> pump(WidgetTester tester, PendingMedia media) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: PendingMediaTile(
              media: media,
              borderRadius: BorderRadius.circular(20),
            ),
          ),
        ),
      ),
    );
    // The localizations load deferred, a frame or more after the first.
    for (
      var i = 0;
      i < 50 && find.byType(PendingMediaTile).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 1));
    }
  }

  Size tileSize(WidgetTester tester) => tester.getSize(
    find.descendant(
      of: find.byType(PendingMediaTile),
      matching: find.byType(Material),
    ),
  );

  group('size', () {
    testWidgets('a photo without a hint is 4:3', (tester) async {
      await pump(
        tester,
        const PendingMedia(
          state: PendingMediaState.pending,
          kind: PendingMediaKind.image,
          fileName: 'a.jpg',
        ),
      );
      expect(tileSize(tester), const Size(256, 192));
    });

    testWidgets('a portrait photo with a hint is portrait', (tester) async {
      await pump(
        tester,
        const PendingMedia(
          state: PendingMediaState.pending,
          kind: PendingMediaKind.image,
          fileName: 'a.jpg',
          aspectRatio: 3024 / 4032,
        ),
      );
      expect(tileSize(tester), const Size(192, 256));
    });

    testWidgets('a video takes the video bubble\'s size', (tester) async {
      await pump(
        tester,
        const PendingMedia(
          state: PendingMediaState.pending,
          kind: PendingMediaKind.video,
          fileName: 'a.mp4',
          aspectRatio: 2160 / 3840,
        ),
      );
      expect(tileSize(tester), videoBubbleSize(2160 / 3840));
      await pump(
        tester,
        const PendingMedia(
          state: PendingMediaState.pending,
          kind: PendingMediaKind.video,
          fileName: 'a.mp4',
        ),
      );
      expect(tileSize(tester), videoBubbleSize(4 / 3));
    });
  });

  testWidgets('pending shows the ring and, with a preview, blurs it', (
    tester,
  ) async {
    await pump(
      tester,
      const PendingMedia(
        state: PendingMediaState.pending,
        kind: PendingMediaKind.image,
        fileName: 'a.jpg',
      ),
    );
    expect(find.byType(MediaProgressDisc), findsOneWidget);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byIcon(Icons.image_outlined), findsOneWidget);

    await pump(
      tester,
      PendingMedia(
        state: PendingMediaState.pending,
        kind: PendingMediaKind.image,
        fileName: 'a.jpg',
        preview: previewJpeg(),
      ),
    );
    expect(find.byType(MediaProgressDisc), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
  });

  testWidgets('failed says so and shows no ring', (tester) async {
    await pump(
      tester,
      const PendingMedia(
        state: PendingMediaState.failed,
        kind: PendingMediaKind.video,
        fileName: 'a.mp4',
      ),
    );
    expect(find.text("Video didn't arrive"), findsOneWidget);
    expect(find.byIcon(Icons.videocam_off_outlined), findsOneWidget);
    expect(find.byType(MediaProgressDisc), findsNothing);
  });
}
