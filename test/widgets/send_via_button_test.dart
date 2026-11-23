// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/merged_network_menu.dart';
import 'package:fluffychat/pages/chat/send_via_button.dart';
import 'package:fluffychat/utils/merged_contacts/send_router.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../utils/merged_contacts/fake_rooms.dart';

void main() {
  late List<MergedNetwork> networks;

  setUp(() async {
    final client = await fakeMergedClient();
    final imessage = addDirectChat(
      client,
      id: '!imsg:x',
      partner: '@imessage_tel=3a+1:x',
      name: 'Harrison',
    );
    final sms = addDirectChat(
      client,
      id: '!sms:x',
      partner: '@gmessages_1.2:x',
      name: 'Harrison',
    );
    networks = [
      MergedNetwork(imessage, null, 'iMessage'),
      MergedNetwork(sms, null, 'SMS'),
    ];
  });

  Future<void> pumpButton(
    WidgetTester tester, {
    required SendTarget target,
    required List<String> picks,
    required List<String> defaults,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: SendViaButton(
              networks: networks,
              target: target,
              defaultRoomId: '!imsg:x',
              onPick: picks.add,
              onSetDefault: defaults.add,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('tapping picks another network and keeps it for the contact', (
    tester,
  ) async {
    final picks = <String>[];
    final defaults = <String>[];
    await pumpButton(
      tester,
      target: const SendTarget('!imsg:x'),
      picks: picks,
      defaults: defaults,
    );
    // The button has no label; the network is named in its tooltip.
    expect(find.byTooltip('Send via iMessage'), findsOneWidget);
    expect(find.text('iMessage'), findsNothing);
    await tester.tap(find.byKey(const Key('send_via_button')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('SMS').last);
    await tester.pumpAndSettle();
    expect(picks, ['!sms:x']);
    expect(defaults, ['!sms:x']);
  });

  testWidgets('while replying the button shows the reply\'s network, locked', (
    tester,
  ) async {
    final picks = <String>[];
    final defaults = <String>[];
    await pumpButton(
      tester,
      target: const SendTarget('!sms:x', locked: true),
      picks: picks,
      defaults: defaults,
    );
    expect(find.text('SMS'), findsNothing);
    expect(find.byIcon(Icons.lock), findsOneWidget);
    await tester.tap(find.byKey(const Key('send_via_button')));
    await tester.pumpAndSettle();
    // No menu opened: iMessage is not offered.
    expect(find.text('iMessage'), findsNothing);
    expect(picks, isEmpty);
  });
}
