// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/optical_line.dart';
import 'package:fluffychat/pages/chat/events/state_event_group.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/message_search/search_test_client.dart';
import '../../utils/state_event_fixtures.dart';

void main() {
  late Client client;
  late BridgedChatFixture chat;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  setUp(() async {
    client = await createSearchTestClient();
    chat = BridgedChatFixture(
      client.rooms.firstWhere((room) => room.isDirectChat),
    );
  });

  tearDown(() => client.dispose(closeDatabase: true));

  final expandedChanges = <bool>[];

  Future<void> pump(
    WidgetTester tester,
    List<Event> run, {
    bool expanded = false,
    bool still = false,
  }) async {
    expandedChanges.clear();
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Builder(
          builder: (context) => MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: still),
            child: Scaffold(
              body: Center(
                child: StateEventGroup(
                  run: run,
                  expanded: expanded,
                  onExpandedChanged: expandedChanges.add,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The height a line takes in the group: zero while it is folded away.
  double shown(WidgetTester tester, String text) {
    final clip = find.ancestor(
      of: find.text(text),
      matching: find.byType(ClipRect),
    );
    final target = clip.evaluate().isEmpty ? find.text(text) : clip.first;
    return tester.getSize(target).height;
  }

  const headline = 'Gloria accepted the invitation';
  const renamed = 'Google Messages changed the chat name';
  const avatar = 'Google Messages changed the chat avatar';
  const accepted = 'You accepted the invitation';

  List<Event> fourEvents() => [
    chat.ownAccepted(minute: 1),
    chat.gloriaAccepted(minute: 2),
    chat.botRenamed(minute: 7),
    chat.botChangedAvatar(minute: 8),
  ];

  testWidgets('folded: the headline and "+N more", the rest folded away', (
    tester,
  ) async {
    await pump(tester, fourEvents());
    // Gloria's join leads, though the bot's housekeeping came after it.
    expect(shown(tester, headline), greaterThan(0));
    expect(shown(tester, '+3 more'), greaterThan(0));
    for (final text in [accepted, renamed, avatar]) {
      expect(shown(tester, text), 0, reason: text);
    }
  });

  testWidgets('a tap unfolds every event and the faint line goes', (
    tester,
  ) async {
    await pump(tester, fourEvents());
    await tester.tap(find.text(headline));
    await tester.pumpAndSettle();
    for (final text in [accepted, headline, renamed, avatar]) {
      expect(shown(tester, text), greaterThan(0), reason: text);
    }
    expect(shown(tester, '+3 more'), 0);
    expect(expandedChanges, [true]);
  });

  testWidgets('open: a row shows its time beneath on a tap, and hides it', (
    tester,
  ) async {
    await pump(tester, fourEvents(), expanded: true);
    expect(find.text('2:07 PM'), findsNothing);
    await tester.tap(find.text(renamed));
    await tester.pumpAndSettle();
    expect(find.text('2:07 PM'), findsOneWidget);
    expect(
      tester.getTopLeft(find.text('2:07 PM')).dy,
      greaterThan(tester.getBottomLeft(find.text(renamed)).dy - 1),
    );
    await tester.tap(find.text(renamed));
    await tester.pumpAndSettle();
    expect(find.text('2:07 PM'), findsNothing);
    expect(expandedChanges, isEmpty);
  });

  testWidgets('open: a tap on the headline folds the run and its times', (
    tester,
  ) async {
    await pump(tester, fourEvents(), expanded: true);
    await tester.tap(find.text(renamed));
    await tester.pumpAndSettle();
    await tester.tap(find.text(headline));
    await tester.pumpAndSettle();
    expect(shown(tester, renamed), 0);
    expect(shown(tester, '+3 more'), greaterThan(0));
    expect(expandedChanges, [false]);
    await tester.tap(find.text(headline));
    await tester.pumpAndSettle();
    expect(find.text('2:07 PM'), findsNothing);
  });

  testWidgets('a pair shows its older event as the faint line', (tester) async {
    await pump(tester, [
      chat.botInvitedGloria(minute: 1),
      chat.gloriaAccepted(minute: 2),
    ]);
    expect(find.text('+1 more'), findsNothing);
    expect(shown(tester, 'Google Messages invited Gloria'), greaterThan(0));
    expect(shown(tester, headline), greaterThan(0));
  });

  testWidgets('a pair whose other event is newer counts it instead', (
    tester,
  ) async {
    await pump(tester, [
      chat.gloriaAccepted(minute: 1),
      chat.botRenamed(minute: 2),
    ]);
    expect(shown(tester, '+1 more'), greaterThan(0));
    expect(shown(tester, renamed), 0);
  });

  testWidgets('with reduced motion a tap unfolds at once', (tester) async {
    await pump(tester, fourEvents(), still: true);
    await tester.tap(find.text(headline));
    await tester.pump();
    for (final text in [accepted, renamed, avatar]) {
      expect(shown(tester, text), greaterThan(0), reason: text);
    }
    expect(shown(tester, '+3 more'), 0);
  });

  testWidgets('a run the chat remembers as open starts open', (tester) async {
    await pump(tester, fourEvents(), expanded: true);
    expect(shown(tester, renamed), greaterThan(0));
    expect(shown(tester, '+3 more'), 0);
  });

  group('OpticalCentre', () {
    const style = TextStyle(fontSize: 10);

    testWidgets('moves a line whose ink sits off its box centre', (
      tester,
    ) async {
      // A leading space takes room but draws nothing, so the ink of
      // " XX" sits right of centre and the shift is to the left.
      final shift = await tester.runAsync(
        () => OpticalCentre.measure(' XX', style, TextScaler.noScaling, 200, 1),
      );
      expect(shift, lessThan(-1));
      expect(
        OpticalCentre.lookup(' XX', style, TextScaler.noScaling, 200, 1),
        shift,
      );
    });

    testWidgets('leaves a line with even ink alone', (tester) async {
      final shift = await tester.runAsync(
        () =>
            OpticalCentre.measure('XXXX', style, TextScaler.noScaling, 200, 1),
      );
      expect(shift!.abs(), lessThan(0.5));
    });

    testWidgets('centres a line cut with an ellipsis on its visible ink', (
      tester,
    ) async {
      final shift = await tester.runAsync(
        () => OpticalCentre.measure(
          'XXXXXXXXXXXXXXXXXXXXXXXX',
          style,
          TextScaler.noScaling,
          55,
          1,
        ),
      );
      expect(shift!.abs(), lessThan(1));
    });
  });
}
