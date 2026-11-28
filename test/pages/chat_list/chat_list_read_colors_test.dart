// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:math';

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../../utils/merged_contacts/fake_rooms.dart' show setMergedContacts;
import 'chat_list_fakes.dart';

/// A read row recedes: its name, preview and time in on surface variant,
/// the name at regular weight. An unread row keeps on surface, bold, with
/// its time in primary.
void main() {
  late FakeChatListClient client;
  var rooms = 0;

  setUp(() async {
    client = await setUpFakeChatList('chat list read colors');
  });

  tearDown(() => tearDownFakeChatList(client));

  final time = DateTime.now().subtract(const Duration(minutes: 5));

  Room chat(String name, String body, {int unread = 0, bool read = false}) {
    final id = '!r${rooms++}:x';
    final partner = '@p$id';
    final room = addFakeChat(
      client,
      id,
      name,
      partner: partner,
      notificationCount: unread,
      lastMessageTime: time,
    );
    room.lastEvent = Event(
      content: {'msgtype': MessageTypes.Text, 'body': body},
      type: EventTypes.Message,
      eventId: '\$$id-last',
      senderId: partner,
      originServerTs: time,
      room: room,
    );
    if (read) {
      final receipt = LatestReceiptStateData(
        room.lastEvent!.eventId,
        time.millisecondsSinceEpoch + 1,
      );
      room.receiptState.global.latestOwnReceipt = receipt;
      room.receiptState.global.ownPublic = receipt;
    }
    return room;
  }

  Future<ColorScheme> show(
    WidgetTester tester,
    Brightness brightness,
    Widget row,
  ) async {
    final prefs = await SharedPreferences.getInstance();
    late ColorScheme scheme;
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: (context, child) => Theme(
            data: FluffyThemes.buildTheme(context, brightness),
            child: Builder(
              builder: (context) {
                scheme = Theme.of(context).colorScheme;
                return child!;
              },
            ),
          ),
          home: Scaffold(body: ListView(children: [row])),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return scheme;
  }

  /// The resolved style of the text that reads [text].
  TextStyle styleOf(WidgetTester tester, String text) => tester
      .widgetList<RichText>(find.byType(RichText))
      .singleWhere((t) => t.text.toPlainText() == text)
      .text
      .style!;

  for (final brightness in Brightness.values) {
    group(brightness.name, () {
      testWidgets('a read chat recedes', (tester) async {
        final room = chat('Sam Ortiz', 'Sounds good', read: true);
        final scheme = await show(
          tester,
          brightness,
          ChatListItem(room, onTap: () {}),
        );
        final name = styleOf(tester, 'Sam Ortiz');
        expect(name.color, scheme.onSurfaceVariant);
        expect(name.fontWeight ?? FontWeight.w400, FontWeight.w400);
        expect(styleOf(tester, 'Sounds good').color, scheme.onSurfaceVariant);
        // The time is the row's only 11 point text.
        final clock = tester
            .widgetList<RichText>(find.byType(RichText))
            .singleWhere((t) => t.text.style?.fontSize == 11);
        expect(clock.text.style!.color, scheme.onSurfaceVariant);
      });

      testWidgets('an unread chat stands out', (tester) async {
        final room = chat('Maya Chen', 'Tonight?', unread: 2);
        final scheme = await show(
          tester,
          brightness,
          ChatListItem(room, onTap: () {}),
        );
        final name = styleOf(tester, 'Maya Chen');
        expect(name.color, scheme.onSurface);
        expect(name.fontWeight, FontWeight.w700);
        expect(styleOf(tester, 'Tonight?').color, scheme.onSurface);
      });

      testWidgets('a read merged contact recedes too', (tester) async {
        final a = chat('Jordan Lee', 'See you', read: true);
        final b = chat('Jordan Lee', 'Running late', read: true);
        setMergedContacts(client, {
          'c_1': {
            'rooms': [a.id, b.id],
            'send_via': a.id,
            'updated': 1,
          },
        });
        final contact = MergedContact.ofRoom(client, a.id)!;
        final scheme = await show(
          tester,
          brightness,
          ChatListItem(
            a,
            contact: contact,
            networks: [
              Room(id: '!s1:x', client: client),
              Room(id: '!s2:x', client: client),
            ],
            onTap: () {},
          ),
        );
        expect(styleOf(tester, 'Jordan Lee').color, scheme.onSurfaceVariant);
        // The merged contacts store saves on a timer; let it run out.
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 11));
      });

      testWidgets('read text keeps 4.5:1 contrast', (tester) async {
        final room = chat('Sam Ortiz', 'Sounds good', read: true);
        final scheme = await show(
          tester,
          brightness,
          ChatListItem(room, onTap: () {}),
        );
        final fg = scheme.onSurfaceVariant.computeLuminance();
        final bg = scheme.surface.computeLuminance();
        final ratio = (max(fg, bg) + 0.05) / (min(fg, bg) + 0.05);
        expect(ratio, greaterThanOrEqualTo(4.5));
      });
    });
  }
}
