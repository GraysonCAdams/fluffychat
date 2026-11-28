// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui' as ui;

import 'package:fluffychat/widgets/layouts/empty_page.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/seam_startup.dart';
import 'package:fluffychat/widgets/seam_stitch_loader.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

typedef M = SeamStitchMotion;

/// A client whose first sync can be held back and then finished.
class _SyncingClient extends FakeChatListClient {
  _SyncingClient(super.clientName, {required super.database});

  String? batch;

  @override
  String? get prevBatch => batch;

  void finishSync() {
    batch = 'synced';
    onSyncStatus.add(SyncStatusUpdate(SyncStatus.finished));
  }
}

List<double> pose(WidgetTester tester) {
  final state = tester.state<SeamStitchLoaderState>(
    find.byType(SeamStitchLoader),
  );
  final m = state.motion;
  return [...m.cut, m.cutA, m.pulse, m.wiggleNow, m.tailAngle()];
}

Widget host(Widget child, {bool reduced = false}) => MaterialApp(
  home: MediaQuery(
    data: MediaQueryData(disableAnimations: reduced),
    child: Center(child: child),
  ),
);

/// The colour at ([x], [y]) of the still mark painted at 432 px (one pixel per
/// artboard unit) over [background].
Future<Color> markPixel(
  Color background,
  Color ink,
  Color? pale,
  int x,
  int y,
) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(
    recorder,
  )..drawRect(const Rect.fromLTWH(0, 0, 432, 432), Paint()..color = background);
  SeamStitchPainter(
    motion: SeamStitchMotion()..land(),
    ink: ink,
    pale: pale,
  ).paint(canvas, const Size.square(432));
  final image = await recorder.endRecording().toImage(432, 432);
  final data = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!;
  final i = (y * 432 + x) * 4;
  return Color.fromARGB(
    data.getUint8(i + 3),
    data.getUint8(i),
    data.getUint8(i + 1),
    data.getUint8(i + 2),
  );
}

void main() {
  group('two tones', () {
    const cobalt = Color(0xFF1A5AD7);
    // artboard (216, 150) above the seam and (216, 260) below it, through the
    // mark's .81 frame
    const above = (216, 171), below = (216, 260);

    test('the piece above the seam takes pale, the rest the ink', () async {
      final up = await markPixel(
        cobalt,
        Colors.white,
        SeamStitchPainter.periwinkle,
        above.$1,
        above.$2,
      );
      final down = await markPixel(
        cobalt,
        Colors.white,
        SeamStitchPainter.periwinkle,
        below.$1,
        below.$2,
      );
      expect(up, SeamStitchPainter.periwinkle);
      expect(down, Colors.white);
    });

    test('a faded pale replaces the ink rather than tinting it', () async {
      const surface = Color(0xFF000000);
      final up = await markPixel(
        surface,
        Colors.white,
        SeamStitchPainter.faded(Colors.white),
        above.$1,
        above.$2,
      );
      // white at 55% over black, not white
      expect((up.r * 255).round(), closeTo(140, 2));
    });

    test('without pale the mark is one colour', () async {
      final up = await markPixel(
        cobalt,
        Colors.white,
        null,
        above.$1,
        above.$2,
      );
      expect(up, Colors.white);
    });

    test('lighter is cobalt 30% to white on light, 45% on dark', () {
      expect(
        SeamStitchPainter.lighter(cobalt, dark: false).toARGB32(),
        0xFF5F8CE3,
      );
      expect(
        SeamStitchPainter.lighter(
          const Color(0xFF84AAFF),
          dark: true,
        ).toARGB32(),
        0xFFBBD0FF,
      );
    });
  });

  group('motion', () {
    test('the logo pose has every stitch drawn and nothing moving', () {
      final m = SeamStitchMotion()..land();
      expect(m.cut, M.ub);
      expect(m.cutA, 1);
      expect(m.pulse, 1);
      expect(m.wiggleNow, 0);
      expect(m.tailAngle(), 0);
    });

    test('stitches draw on left to right, then dissolve and reset', () {
      final m = SeamStitchMotion()..evalAt(0);
      expect(m.cut, M.ua);
      m.evalAt(M.t0 + M.per + M.draw / 2);
      expect(m.cut[0], M.ub[0]);
      expect(m.cut[1], inExclusiveRange(M.ua[1], M.ub[1]));
      expect(m.cut[2], M.ua[2]);
      m.evalAt((M.tLand + M.tIn) / 2);
      expect(m.cutA, inExclusiveRange(0, 1));
      m.evalAt(M.tIn + .1);
      expect(m.cut, M.ua);
    });

    test('one loop is 4.75 s and the needle wiggles twice', () {
      expect(M.loop, closeTo(4.75, 1e-9));
      final m = SeamStitchMotion();
      final lean = <double>[];
      for (var t = 0.0; t < M.loop; t += .01) {
        m.evalAt(t);
        lean.add(m.wiggleNow);
      }
      // Each wiggle is one stretch of lean away from rest.
      var swings = 0;
      for (var i = 1; i < lean.length; i++) {
        if (lean[i - 1] == 0 && lean[i] != 0) swings++;
      }
      expect(swings, 2);
    });
  });

  testWidgets('the loader animates while loading', (tester) async {
    await tester.pumpWidget(host(const SeamStitchLoader(startAt: 0)));
    final first = pose(tester);
    await tester.pump(const Duration(milliseconds: 500));
    await tester.pump(const Duration(milliseconds: 500));
    final second = pose(tester);
    expect(second, isNot(equals(first)));
    final state = tester.state<SeamStitchLoaderState>(
      find.byType(SeamStitchLoader),
    );
    expect(state.tau, greaterThan(0));
    await tester.pumpWidget(const SizedBox());
  });

  testWidgets('with reduced motion the loader holds the logo pose', (
    tester,
  ) async {
    await tester.pumpWidget(
      host(const SeamStitchLoader(startAt: 0), reduced: true),
    );
    final first = pose(tester);
    await tester.pump(const Duration(seconds: 2));
    expect(pose(tester), first);
    expect(first.sublist(0, 4), M.ub);
    expect(tester.binding.hasScheduledFrame, isFalse);
  });

  testWidgets('finishing the pass lands on the logo and crossfades', (
    tester,
  ) async {
    const settled = SizedBox(key: Key('settled'));
    Widget loader(bool loading) =>
        host(SeamStitchLoader(startAt: 1, loading: loading, settled: settled));
    await tester.pumpWidget(loader(true));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(loader(false));
    final state = tester.state<SeamStitchLoaderState>(
      find.byType(SeamStitchLoader),
    );
    // It sews on to the end of its pass before it stops.
    await tester.pump(const Duration(milliseconds: 40));
    for (var i = 0; i < 80 && !state.landed; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(state.landed, isTrue);
    expect(state.tau, closeTo(M.tLand, .06));
    expect(pose(tester).sublist(0, 4), M.ub);
    await tester.pumpAndSettle();
    final fade = tester.widget<FadeTransition>(
      find
          .ancestor(
            of: find.byKey(const Key('settled')),
            matching: find.byType(FadeTransition),
          )
          .first,
    );
    expect(fade.opacity.value, 1);
  });

  testWidgets('the start screen sews until the app is ready, then fades', (
    tester,
  ) async {
    final app = Completer<Widget>();
    await tester.pumpWidget(SeamStartup(app: app.future));
    expect(find.byType(SeamStitchLoader), findsOneWidget);
    expect(
      tester.widget<ColoredBox>(find.byType(ColoredBox).first).color,
      SeamStartup.cobalt,
    );
    expect(
      tester.getSize(find.byType(SeamStitchLoader)),
      const Size.square(SeamStartup.loaderSize),
    );
    await tester.pump(const Duration(seconds: 1));
    app.complete(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: Text('the app', key: Key('the app')),
      ),
    );
    await tester.pump();
    expect(find.byKey(const Key('the app')), findsOneWidget);
    expect(find.byType(SeamStitchLoader), findsOneWidget);
    await tester.pumpAndSettle();
    expect(find.byType(SeamStitchLoader), findsNothing);
    expect(find.byKey(const Key('the app')), findsOneWidget);
  });

  group('empty pane', () {
    late _SyncingClient client;
    late SharedPreferences prefs;

    setUp(() async {
      client = await setUpFakeChatList(
        'empty_pane',
        create: (name, database) => _SyncingClient(name, database: database),
      );
      prefs = await SharedPreferences.getInstance();
    });

    Future<void> pumpPane(WidgetTester tester) => tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp(
          theme: ThemeData(useMaterial3: true),
          home: const EmptyPage(),
        ),
      ),
    );

    testWidgets('shows the still glyph once synced', (tester) async {
      client.batch = 'synced';
      await pumpPane(tester);
      expect(find.byType(SeamStitchLoader), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    });

    testWidgets('sews in the glyph colours until the first sync is done', (
      tester,
    ) async {
      await pumpPane(tester);
      final loader = tester.widget<SeamStitchLoader>(
        find.byType(SeamStitchLoader),
      );
      final glyph = ThemeData(
        useMaterial3: true,
      ).colorScheme.surfaceContainerHigh;
      expect(loader.color, glyph);
      // the upper half fainter, as seam_glyph.png draws it
      expect(loader.pale, SeamStitchPainter.faded(glyph));
      expect(loader.pale!.a, closeTo(glyph.a * .55, 1e-6));
      expect(loader.loading, isTrue);

      client.finishSync();
      await tester.pump();
      expect(
        tester.widget<SeamStitchLoader>(find.byType(SeamStitchLoader)).loading,
        isFalse,
      );
      await tester.pumpAndSettle();
      final state = tester.state<SeamStitchLoaderState>(
        find.byType(SeamStitchLoader),
      );
      expect(state.landed, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
