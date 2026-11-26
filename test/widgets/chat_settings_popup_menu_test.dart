// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/widgets/chat_settings_popup_menu.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;
  late Room room;

  setUp(() async {
    client = await setUpFakeChatList('chat settings popup menu test');
    room = addFakeChat(client, '!grp:x', 'Squad Goals');
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<void> openMenu(WidgetTester tester, VoidCallback? onOpen) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            appBar: AppBar(
              actions: [
                ChatSettingsPopupMenu(room, true, onOpenInNewWindow: onOpen),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byType(PopupMenuButton<ChatPopupMenuActions>));
    await tester.pumpAndSettle();
  }

  testWidgets('offers to open the chat in a new window, first', (tester) async {
    var opened = 0;
    await openMenu(tester, () => opened++);
    final items = tester
        .widgetList<PopupMenuItem<ChatPopupMenuActions>>(
          find.byType(PopupMenuItem<ChatPopupMenuActions>),
        )
        .map((item) => item.value)
        .toList();
    expect(items.first, ChatPopupMenuActions.openInNewWindow);

    await tester.tap(find.text('Open in new window'));
    await tester.pumpAndSettle();
    expect(opened, 1);
  });

  testWidgets('leaves it out when the chat cannot move to a window', (
    tester,
  ) async {
    await openMenu(tester, null);
    expect(find.text('Open in new window'), findsNothing);
    expect(find.text('Search'), findsOneWidget);
  });
}
