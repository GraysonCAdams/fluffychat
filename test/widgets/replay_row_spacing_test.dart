// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

// Measures the ink around the dot in "time · arrow" under an effect message,
// in the app's own fonts, which this file loads for itself.

import 'dart:io';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/played_message_effects.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/message_search/search_test_client.dart';

class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    MatrixFeatures.scanStoredState = false;
    final sans = FontLoader('GoogleSansFlex');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      sans.addFont(
        Future.value(
          ByteData.sublistView(
            File(
              'assets/fonts/google_sans_flex/GoogleSansFlex-$weight.ttf',
            ).readAsBytesSync(),
          ),
        ),
      );
    }
    await sans.load();
    final flutterRoot = Platform.environment['FLUTTER_ROOT']!;
    final icons = FontLoader('MaterialIcons')
      ..addFont(
        Future.value(
          ByteData.sublistView(
            File(
              '$flutterRoot/bin/cache/artifacts/material_fonts/'
              'MaterialIcons-Regular.otf',
            ).readAsBytesSync(),
          ),
        ),
      );
    await icons.load();
    client = await createSearchTestClient();
  });

  testWidgets('the dot sits as far from the time as from the arrow', (
    tester,
  ) async {
    await AppSettings.playedMessageEffects.setItem('[]');
    PlayedMessageEffects.resetForTest();
    final room = client.rooms.firstWhere((room) => !room.isSpace);
    final event = Event(
      content: withEffect({
        'msgtype': 'm.text',
        'body': 'Boom',
      }, MessageEffect.slam),
      type: EventTypes.Message,
      eventId: '\$fx',
      senderId: '@alice:example.org',
      originServerTs: DateTime(2026, 11, 26, 19, 42),
      status: EventStatus.synced,
      room: room,
    );
    PlayedMessageEffects.markPlayed(event);
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
          theme: ThemeData(fontFamily: 'GoogleSansFlex'),
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            backgroundColor: Colors.white,
            body: RepaintBoundary(
              child: ListView(
                controller: scrollController,
                children: [
                  Message(
                    event,
                    timeRevealed: true,
                    bigEmojis: const {},
                    onSelect: (_) {},
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
              ),
            ),
          ),
        ),
      ),
    );
    for (var i = 0; i < 50 && find.byType(Message).evaluate().isEmpty; i++) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.pump(const Duration(seconds: 3));

    final line = tester.getRect(
      find.byKey(const ValueKey('message_effect_replay_line')),
    );
    final dot = tester.getRect(find.byKey(const ValueKey('replay_dot')));
    final boundary = tester.renderObject<RenderRepaintBoundary>(
      find.byType(RepaintBoundary).first,
    );
    const scale = 4.0;
    final origin = tester.getTopLeft(find.byType(RepaintBoundary).first);
    final pixels = (await tester.runAsync(() async {
      final image = await boundary.toImage(pixelRatio: scale);
      final data = await image.toByteData();
      final width = image.width;
      image.dispose();
      return (data!, width);
    }))!;
    // Which columns of the line have ink, in logical pixels from the left.
    bool inkAt(int x) {
      for (
        var y = ((line.top - origin.dy) * scale).round();
        y < ((line.bottom - origin.dy) * scale).round();
        y++
      ) {
        final i = (y * pixels.$2 + x) * 4;
        final r = pixels.$1.getUint8(i);
        final g = pixels.$1.getUint8(i + 1);
        final b = pixels.$1.getUint8(i + 2);
        if (r + g + b < 3 * 200) return true;
      }
      return false;
    }

    int column(double dx) => ((dx - origin.dx) * scale).round();
    // The dot's ink, then the nearest ink either side of it.
    var dotLeft = column(dot.left);
    while (!inkAt(dotLeft)) {
      dotLeft++;
    }
    var dotRight = column(dot.right);
    while (!inkAt(dotRight)) {
      dotRight--;
    }
    var before = dotLeft - 1;
    while (!inkAt(before)) {
      before--;
    }
    var after = dotRight + 1;
    while (!inkAt(after)) {
      after++;
    }
    final gapBefore = (dotLeft - before - 1) / scale;
    final gapAfter = (after - dotRight - 1) / scale;
    debugPrint('Ink gaps around the dot: $gapBefore dp and $gapAfter dp');
    expect(gapBefore, greaterThan(2));
    expect((gapBefore - gapAfter).abs(), lessThanOrEqualTo(1));
    // The sender's lookup in the database runs outside the test's clock.
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 200)),
    );
    await tester.pump(const Duration(seconds: 11));
  });
}
