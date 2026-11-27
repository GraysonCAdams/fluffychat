// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/reader_stack.dart';
import 'package:fluffychat/pages/chat/status_mark.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

const _grey = Color(0xFFAAAAAA);

/// Shows [child] as a page, with reduced motion when [reduceMotion].
Widget _app(Widget child, {bool reduceMotion = false}) => MaterialApp(
  home: Builder(
    builder: (context) => MediaQuery(
      data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
      child: Scaffold(body: Center(child: child)),
    ),
  ),
);

Future<void> _pumpMark(
  WidgetTester tester,
  StatusMarkState state, {
  bool reduceMotion = false,
  Key? key,
}) => tester.pumpWidget(
  _app(
    StatusMark(key: key, state: state, color: _grey),
    reduceMotion: reduceMotion,
  ),
);

final _painters = find.byWidgetPredicate(
  (widget) => widget is CustomPaint && widget.painter is StatusMarkPainter,
);

StatusMarkPainter _painter(WidgetTester tester) =>
    tester.widget<CustomPaint>(_painters).painter! as StatusMarkPainter;

/// Where the mark's painting stands on its scale, 0 sending to 3 read.
double _level(WidgetTester tester) => _painter(tester).level;

List<StackedReader> _readers(List<String> names) => [
  for (final name in names) StackedReader(id: '@$name:x', name: name),
];

Future<void> _pumpStack(
  WidgetTester tester,
  List<String> names, {
  bool reduceMotion = false,
}) => tester.pumpWidget(
  _app(
    ReaderStack(readers: _readers(names), color: _grey),
    reduceMotion: reduceMotion,
  ),
);

final _faces = find.descendant(
  of: find.byType(ReaderStack),
  matching: find.byType(Avatar),
);

double _opacityOf(WidgetTester tester, Finder face) => tester
    .widget<Opacity>(
      find.ancestor(of: face, matching: find.byType(Opacity)).first,
    )
    .opacity;

void main() {
  group('the status mark', () {
    testWidgets('is built in its state without animating', (tester) async {
      await _pumpMark(tester, StatusMarkState.read);
      expect(_level(tester), 3);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('does not replay its history when built again', (tester) async {
      await _pumpMark(tester, StatusMarkState.sent, key: const Key('a'));
      // Scrolled away and back: a new mark for the same message.
      await _pumpMark(tester, StatusMarkState.read, key: const Key('b'));
      expect(_level(tester), 3);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('animates a live change from sent to read', (tester) async {
      await _pumpMark(tester, StatusMarkState.sent);
      await _pumpMark(tester, StatusMarkState.read);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 60));
      expect(_level(tester), inExclusiveRange(1, 3));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_level(tester), 3);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('plays every step when it skips from sending to read', (
      tester,
    ) async {
      await _pumpMark(tester, StatusMarkState.sending);
      await tester.pump(const Duration(milliseconds: 100));
      await _pumpMark(tester, StatusMarkState.read);
      final levels = <double>[];
      for (var i = 0; i < 40; i++) {
        await tester.pump(const Duration(milliseconds: 16));
        levels.add(_level(tester));
      }
      // The draw-on, the second ring sliding out, and the fill.
      expect(levels.any((l) => l > 0 && l < 1), isTrue, reason: '$levels');
      expect(levels.any((l) => l > 1 && l < 2), isTrue, reason: '$levels');
      expect(levels.any((l) => l > 2 && l < 3), isTrue, reason: '$levels');
      for (var i = 1; i < levels.length; i++) {
        expect(levels[i], greaterThanOrEqualTo(levels[i - 1]));
      }
      expect(levels.last, 3);
      expect(
        StatusMark.durationBetween(0, 3),
        const Duration(milliseconds: 550),
      );
    });

    testWidgets('changes at once with reduced motion', (tester) async {
      await _pumpMark(tester, StatusMarkState.sending, reduceMotion: true);
      await _pumpMark(tester, StatusMarkState.read, reduceMotion: true);
      expect(_level(tester), 3);
      expect(tester.hasRunningAnimations, isFalse);
    });

    testWidgets('fades to the error icon and back on a retry', (tester) async {
      await _pumpMark(tester, StatusMarkState.sending);
      await _pumpMark(tester, StatusMarkState.failed);
      await tester.pump(const Duration(milliseconds: 80));
      // Halfway, the ring and the icon cross-fade.
      expect(find.byIcon(Icons.error_outlined), findsOneWidget);
      expect(find.byType(CustomPaint), findsWidgets);
      await tester.pump(const Duration(milliseconds: 300));
      final icon = tester.widget<Icon>(find.byIcon(Icons.error_outlined));
      expect(
        icon.color,
        Theme.of(tester.element(find.byType(StatusMark))).colorScheme.error,
      );
      expect(_painters, findsNothing);

      await _pumpMark(tester, StatusMarkState.sending);
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byIcon(Icons.error_outlined), findsNothing);
      expect(_level(tester), 0);
      await _pumpMark(tester, StatusMarkState.sent);
      await tester.pump(const Duration(milliseconds: 300));
      expect(_level(tester), 1);
    });

    testWidgets('keeps one neutral colour in every state', (tester) async {
      for (final state in [
        StatusMarkState.sending,
        StatusMarkState.sent,
        StatusMarkState.readBySome,
        StatusMarkState.read,
      ]) {
        await _pumpMark(tester, state);
        await tester.pump(const Duration(milliseconds: 600));
        final painter = _painter(tester);
        expect(painter.color, _grey, reason: '$state');
      }
    });
  });

  group('the reader stack', () {
    testWidgets('overlaps up to three faces with cutouts, then +N', (
      tester,
    ) async {
      await _pumpStack(tester, ['Pat', 'Anne', 'Harrison', 'Drew']);
      expect(tester.hasRunningAnimations, isFalse);
      expect(_faces, findsNWidgets(3));
      expect(find.text('+1'), findsOneWidget);
      // Newest in front at the start, each face 10dp (of 16) along.
      final lefts = [
        for (final name in ['Pat', 'Anne', 'Harrison'])
          tester
              .getTopLeft(
                find.byWidgetPredicate((w) => w is Avatar && w.name == name),
              )
              .dx,
      ];
      expect(lefts[1] - lefts[0], ReaderStack.step);
      expect(lefts[2] - lefts[1], ReaderStack.step);
      // Every face behind another has the front one's circle cut out of
      // it, 1.5dp wider; the front face is whole.
      final cutouts = tester
          .widgetList<ClipPath>(
            find.descendant(
              of: find.byType(ReaderStack),
              matching: find.byType(ClipPath),
            ),
          )
          .map((clip) => clip.clipper)
          .toList();
      expect(cutouts.whereType<ReaderCutout>(), hasLength(3));
      for (final cutout in cutouts.whereType<ReaderCutout>()) {
        expect(cutout.radius, ReaderStack.size / 2 + ReaderStack.cutout);
        expect(cutout.dx, -ReaderStack.step);
      }
      expect(cutouts.where((c) => c == null), hasLength(1));
    });

    testWidgets('a new reader scales in at the front', (tester) async {
      await _pumpStack(tester, ['Drew']);
      await _pumpStack(tester, ['Harrison', 'Drew']);
      expect(tester.hasRunningAnimations, isTrue);
      await tester.pump(const Duration(milliseconds: 80));
      final harrison = find.byWidgetPredicate(
        (w) => w is Avatar && w.name == 'Harrison',
      );
      expect(_opacityOf(tester, harrison), inExclusiveRange(0, 1));
      await tester.pumpAndSettle();
      expect(_opacityOf(tester, harrison), 1);
      expect(
        tester.getTopLeft(harrison).dx,
        lessThan(
          tester
              .getTopLeft(
                find.byWidgetPredicate((w) => w is Avatar && w.name == 'Drew'),
              )
              .dx,
        ),
      );
    });

    testWidgets('a face pushed into +N fades out, and +N counts up', (
      tester,
    ) async {
      await _pumpStack(tester, ['Harrison', 'Drew', 'Anne', 'Pat']);
      expect(find.text('+1'), findsOneWidget);
      await _pumpStack(tester, [
        'Lee',
        'Kim',
        'Harrison',
        'Drew',
        'Anne',
        'Pat',
      ]);
      await tester.pump(const Duration(milliseconds: 80));
      // Drew is on the way out, fading.
      final drew = find.byWidgetPredicate(
        (w) => w is Avatar && w.name == 'Drew',
      );
      expect(drew, findsOneWidget);
      expect(_opacityOf(tester, drew), inExclusiveRange(0, 1));
      // +N is counting from 1 to 3.
      expect(find.text('+3'), findsNothing);
      await tester.pumpAndSettle();
      expect(drew, findsNothing);
      expect(_faces, findsNWidgets(3));
      expect(find.text('+3'), findsOneWidget);
    });

    testWidgets('changes at once with reduced motion', (tester) async {
      await _pumpStack(tester, ['Drew'], reduceMotion: true);
      await _pumpStack(tester, [
        'Lee',
        'Kim',
        'Harrison',
        'Drew',
      ], reduceMotion: true);
      await tester.pump();
      expect(tester.hasRunningAnimations, isFalse);
      expect(_faces, findsNWidgets(3));
      expect(find.text('+1'), findsOneWidget);
    });
  });

  group('under a bubble', () {
    late FakeChatListClient client;

    setUp(() async {
      client = await setUpFakeChatList('status mark motion test');
    });

    tearDown(() => tearDownFakeChatList(client));

    Event mine(Room room, EventStatus status) => Event(
      content: {'msgtype': 'm.text', 'body': 'On my way'},
      type: EventTypes.Message,
      eventId: status.isSent ? r'$sent' : r'$txn1',
      unsigned: {'transaction_id': 'txn1'},
      senderId: client.userID!,
      originServerTs: DateTime(2026, 11, 27, 10),
      status: status,
      room: room,
    );

    Room direct() {
      final room = addFakeChat(client, '!anne:x', 'Anne', partner: '@anne:x');
      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          content: {'membership': 'join', 'displayname': 'Gray'},
          senderId: client.userID!,
          stateKey: client.userID,
        ),
      );
      return room;
    }

    Future<void> pump(WidgetTester tester, Event event) async {
      final timeline = Timeline(
        room: event.room,
        chunk: TimelineChunk(events: [event]),
      );
      final scrollController = ScrollController();
      addTearDown(scrollController.dispose);
      final prefs = await SharedPreferences.getInstance();
      await tester.pumpWidget(
        Provider<MatrixState>.value(
          value: FakeMatrix(client, prefs),
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: ListView(
                controller: scrollController,
                children: [
                  Message(
                    event,
                    bigEmojis: const {},
                    onSelect: (_) {},
                    showDeliveryStatus: true,
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
      );
    }

    testWidgets('one mark goes from Sending to sent, animating', (
      tester,
    ) async {
      final room = direct();
      await pump(tester, mine(room, EventStatus.sending));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Sending'), findsOneWidget);
      final mark = find.byType(StatusMark);
      expect(tester.widget<StatusMark>(mark).state, StatusMarkState.sending);
      final before = tester.state(mark);

      await pump(tester, mine(room, EventStatus.synced));
      expect(find.text('Sending'), findsNothing);
      expect(tester.widget<StatusMark>(mark).state, StatusMarkState.sent);
      // The same mark, drawing its check on.
      expect(tester.state(mark), same(before));
      await tester.pump(const Duration(milliseconds: 60));
      expect(_level(tester), inExclusiveRange(0, 1));
      await tester.pump(const Duration(milliseconds: 300));
      expect(_level(tester), 1);
    });

    testWidgets('a failed message keeps its label beside the mark', (
      tester,
    ) async {
      final room = direct();
      await pump(tester, mine(room, EventStatus.error));
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Could not be sent'), findsOneWidget);
      expect(
        tester.widget<StatusMark>(find.byType(StatusMark)).state,
        StatusMarkState.failed,
      );
      expect(
        tester.getTopRight(find.text('Could not be sent')).dx,
        lessThanOrEqualTo(tester.getTopLeft(find.byType(StatusMark)).dx),
      );
    });
  });
}
