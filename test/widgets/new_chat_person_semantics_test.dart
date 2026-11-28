// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui' show Tristate;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';

import '../utils/merged_contacts/fake_rooms.dart';

class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

/// A row of New Chat's people (the recent conversations a share offers, the
/// search results) is one button a screen reader names after the chat,
/// with its networks, not a picture of initials beside separate texts.
void main() {
  late Client client;

  setUp(() async => client = await fakeMergedClient());

  Future<void> show(WidgetTester tester, List<NewChatPersonTile> rows) async {
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrix(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(body: ListView(children: rows)),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  NewChatPerson<String> person(
    String name, {
    List<String> networks = const [],
  }) {
    final p = NewChatPerson<String>(name)..chat = 'chat-$name';
    p.networks.addAll([for (final n in networks) NetworkRef(key: n, name: n)]);
    return p;
  }

  testWidgets('a recent chat is one button named after it', (tester) async {
    final handle = tester.ensureSemantics();
    var tapped = 0;
    await show(tester, [
      NewChatPersonTile(
        person: person('Group with bob'),
        onTap: () => tapped++,
      ),
    ]);
    final finder = find.bySemanticsLabel('Group with bob');
    expect(finder, findsOneWidget);
    final node = tester.getSemantics(finder);
    final data = node.getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.hasAction(SemanticsAction.tap), isTrue);
    // The initials are not read on their own.
    expect(find.bySemanticsLabel('GW'), findsNothing);
    expect(find.bySemanticsLabel('G'), findsNothing);
    await tester.tap(finder);
    expect(tapped, 1);
    handle.dispose();
  });

  testWidgets('a merged contact names its networks', (tester) async {
    final handle = tester.ensureSemantics();
    await show(tester, [
      NewChatPersonTile(
        person: person(
          'Harrison Young',
          networks: ['iMessage', 'Google Messages'],
        ),
        onTap: () {},
      ),
    ]);
    final finder = find.bySemanticsLabel(
      'Harrison Young, iMessage, Google Messages',
    );
    expect(finder, findsOneWidget);
    expect(
      tester.getSemantics(finder).getSemanticsData().flagsCollection.isButton,
      isTrue,
    );
    // The logos are not separate stops.
    expect(find.bySemanticsLabel('iMessage'), findsNothing);
    handle.dispose();
  });

  testWidgets('a person who cannot join says why and is disabled', (
    tester,
  ) async {
    final handle = tester.ensureSemantics();
    await show(tester, [
      NewChatPersonTile(
        person: person('Dana'),
        blockedReason: 'Not on iMessage',
        onTap: () {},
      ),
    ]);
    final finder = find.bySemanticsLabel('Dana, Not on iMessage');
    expect(finder, findsOneWidget);
    final data = tester.getSemantics(finder).getSemanticsData();
    expect(data.flagsCollection.isButton, isTrue);
    expect(data.flagsCollection.isEnabled, Tristate.isFalse);
    expect(data.hasAction(SemanticsAction.tap), isFalse);
    handle.dispose();
  });
}
