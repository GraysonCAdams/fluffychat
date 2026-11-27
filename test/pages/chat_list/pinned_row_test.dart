// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/widgets.dart'
    show Container, FontWeight, Rect, ReorderableList, Text;
import 'package:flutter_test/flutter_test.dart';

import '../../utils/merged_contacts/fake_rooms.dart' show setMergedContacts;

import 'chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;
  late Map<String, FakeChatListRoom> rooms;

  /// A one-to-one chat named [name] whose newest message is [day] days
  /// into 2026, so a higher [day] lists first.
  FakeChatListRoom chat(String name, int day, {int unread = 0}) {
    final id = '!${name.toLowerCase()}:x';
    return rooms[id] = addFakeChat(
      client,
      id,
      name,
      partner: '@${name.toLowerCase()}:x',
      notificationCount: unread,
      lastMessageTime: DateTime(2026, 1, day),
    );
  }

  setUp(() async {
    client = await setUpFakeChatList('pinned row test');
    rooms = {};
  });

  tearDown(() => tearDownFakeChatList(client));

  /// The avatars of the pinned row, which are larger than the list's.
  Finder pinnedAvatars() => find.byWidgetPredicate(
    (widget) => widget is SelectableAvatar && widget.size == 76,
  );

  /// The names of [names] in the order the pinned row shows them, left to
  /// right. Pinned chats are left out of the list below it.
  List<String> rowOrder(WidgetTester tester, List<String> names) =>
      List.of(names)..sort(
        (a, b) => tester
            .getCenter(find.text(a))
            .dx
            .compareTo(tester.getCenter(find.text(b)).dx),
      );

  /// The distance between the centres of neighbouring pins.
  double pinSlot(WidgetTester tester) {
    final centres =
        pinnedAvatars()
            .evaluate()
            .map((e) => tester.getCenter(find.byWidget(e.widget)).dx)
            .toList()
          ..sort();
    return centres[1] - centres[0];
  }

  /// Presses the pin named [name], holds it still when [hold] is set, and
  /// moves it [dx] sideways before letting go, where [dx] is in units of a
  /// 112dp slot and scaled to the slots the row has laid out.
  Future<void> drag(
    WidgetTester tester,
    String name,
    double dx, {
    bool hold = true,
    PointerDeviceKind kind = PointerDeviceKind.touch,
  }) async {
    final gesture = await tester.startGesture(
      tester.getCenter(find.text(name)),
      kind: kind,
    );
    final scaled = dx * pinSlot(tester) / 112;
    if (hold) await tester.pump(const Duration(milliseconds: 600));
    for (var i = 0; i < 10; i++) {
      await gesture.moveBy(Offset(scaled / 10, 0));
      await tester.pump(const Duration(milliseconds: 16));
    }
    await gesture.up();
    await tester.pumpAndSettle();
  }

  testWidgets('pins that fit spread evenly and stay centred', (tester) async {
    chat('Ada', 3).pin();
    chat('Bea', 2).pin();
    chat('Cy', 1);
    await pumpFakeChatList(tester, client);

    final width = tester.getSize(find.byType(ReorderableList)).width;
    final centres =
        pinnedAvatars()
            .evaluate()
            .map((e) => tester.getCenter(find.byWidget(e.widget)).dx)
            .toList()
          ..sort();
    expect(centres, [width / 4, width * 3 / 4]);
    await finishFakeChatList(tester, client);
  });

  testWidgets('pins that overflow start level with the list avatars', (
    tester,
  ) async {
    // More pins than fit in the test's 800dp wide window.
    for (var day = 30; day > 20; day--) {
      chat('Pin$day', day).pin();
    }
    chat('Bea', 2);
    await pumpFakeChatList(tester, client);

    final listAvatar = find.descendant(
      of: find.byType(ChatListItem),
      matching: find.byType(SelectableAvatar),
    );
    expect(listAvatar, findsOneWidget);
    expect(tester.getTopLeft(listAvatar).dx, 16);
    final firstPin = pinnedAvatars()
        .evaluate()
        .map((e) => tester.getTopLeft(find.byWidget(e.widget)).dx)
        .reduce((a, b) => a < b ? a : b);
    expect(firstPin, tester.getTopLeft(listAvatar).dx);
    await finishFakeChatList(tester, client);
  });

  testWidgets('the row follows the stored order, not unread state', (
    tester,
  ) async {
    chat('Ada', 3).pin(0.5);
    chat('Bea', 2).pin(0.25);
    chat('Cy', 1, unread: 2).pin(0.75);
    await pumpFakeChatList(tester, client);

    expect(rowOrder(tester, ['Ada', 'Bea', 'Cy']), ['Bea', 'Ada', 'Cy']);
    // The unread pin keeps its unread look where it stands.
    expect(find.text('hello from Cy'), findsOneWidget);
    await finishFakeChatList(tester, client);
  });

  testWidgets('pins without an order follow the ordered ones, newest first', (
    tester,
  ) async {
    chat('Ada', 5).pin();
    chat('Bea', 4).pin();
    chat('Cy', 1).pin(0.5);
    await pumpFakeChatList(tester, client);

    expect(rowOrder(tester, ['Ada', 'Bea', 'Cy']), ['Cy', 'Ada', 'Bea']);
    await finishFakeChatList(tester, client);
  });

  testWidgets('a drop stores the midpoint of the new neighbours', (
    tester,
  ) async {
    final ada = chat('Ada', 3)..pin(0.25);
    final bea = chat('Bea', 2)..pin(0.5);
    final cy = chat('Cy', 1)..pin(0.75);
    await pumpFakeChatList(tester, client);

    await drag(tester, 'Cy', -120);
    expect(cy.calls, ['tag:m.favourite:0.375']);
    expect(ada.calls, isEmpty);
    expect(bea.calls, isEmpty);
    // The row shows the new order before the server echoes it, and the
    // hold's selection was put back when the pin lifted.
    expect(rowOrder(tester, ['Ada', 'Bea', 'Cy']), ['Ada', 'Cy', 'Bea']);
    expect(find.byType(ChatListSelectionBar), findsNothing);
    await finishFakeChatList(tester, client);
  });

  testWidgets('a mouse drags a pin without holding it first', (tester) async {
    chat('Ada', 3).pin(0.25);
    final bea = chat('Bea', 2)..pin(0.5);
    await pumpFakeChatList(tester, client);

    await drag(tester, 'Bea', -120, hold: false, kind: PointerDeviceKind.mouse);
    expect(bea.calls, ['tag:m.favourite:0.125']);
    expect(rowOrder(tester, ['Ada', 'Bea']), ['Bea', 'Ada']);
    await finishFakeChatList(tester, client);
  });

  testWidgets('a finger that moves before the hold scrolls instead', (
    tester,
  ) async {
    chat('Ada', 3).pin(0.25);
    final bea = chat('Bea', 2)..pin(0.5);
    await pumpFakeChatList(tester, client);

    await drag(tester, 'Bea', -120, hold: false);
    expect(bea.calls, isEmpty);
    expect(find.byType(ChatListSelectionBar), findsNothing);
    await finishFakeChatList(tester, client);
  });

  testWidgets('a merged contact stores the order on each pinned room', (
    tester,
  ) async {
    final imsg = chat('Harrison', 5)..pin(0.125);
    final sms = chat('Harrison SMS', 4)..pin(0.125);
    final sms2 = chat('Harrison SMS 2', 3);
    final bea = chat('Bea', 2)..pin(0.5);
    final cy = chat('Cy', 1)..pin(0.75);
    setMergedContacts(client, {
      'c_1': {
        'rooms': [imsg.id, sms.id, sms2.id],
        'send_via': imsg.id,
        'updated': 1,
      },
    });
    await pumpFakeChatList(tester, client);
    expect(rowOrder(tester, ['Harrison', 'Bea', 'Cy']), [
      'Harrison',
      'Bea',
      'Cy',
    ]);

    await drag(tester, 'Harrison', 120);
    expect(imsg.calls, ['tag:m.favourite:0.625']);
    expect(sms.calls, ['tag:m.favourite:0.625']);
    // The contact's unpinned room stays unpinned.
    expect(sms2.calls, isEmpty);
    expect(bea.calls, isEmpty);
    expect(cy.calls, isEmpty);
    expect(rowOrder(tester, ['Harrison', 'Bea', 'Cy']), [
      'Bea',
      'Harrison',
      'Cy',
    ]);
    await finishFakeChatList(tester, client);
  });

  testWidgets('a long press that does not move selects the pin', (
    tester,
  ) async {
    final ada = chat('Ada', 3)..pin(0.25);
    chat('Bea', 2).pin(0.5);
    await pumpFakeChatList(tester, client);

    await tester.longPress(find.text('Ada'));
    await tester.pumpAndSettle();
    expect(find.byType(ChatListSelectionBar), findsOneWidget);
    expect(find.byType(SelectedChatMark), findsOneWidget);
    expect(ada.calls, isEmpty);
    await finishFakeChatList(tester, client);
  });

  /// The speech bubble of the unread pin whose preview is [text].
  Rect bubble(WidgetTester tester, String text) => tester.getRect(
    find
        .ancestor(
          of: find.text(text),
          matching: find.byWidgetPredicate(
            (widget) => widget is Container && widget.decoration != null,
          ),
        )
        .first,
  );

  testWidgets('pins that overflow sit 112 apart, bubbles 16 apart', (
    tester,
  ) async {
    for (var day = 30; day > 20; day--) {
      chat('Pin$day', day, unread: 1).pin();
    }
    await pumpFakeChatList(tester, client);

    expect(pinSlot(tester), 112);
    // Long previews fill each bubble to its widest.
    final first = bubble(tester, 'hello from Pin30');
    final second = bubble(tester, 'hello from Pin29');
    expect(first.width, 96);
    expect(second.left - first.right, 16);
    await finishFakeChatList(tester, client);
  });

  testWidgets('the bubble sits 19 above the avatar, a tail under it', (
    tester,
  ) async {
    chat('Ada', 3, unread: 1).pin();
    chat('Bea', 2);
    await pumpFakeChatList(tester, client);

    final avatar = tester.getRect(pinnedAvatars().first);
    final speech = bubble(tester, 'hello from Ada');
    expect(speech.top - avatar.top, -19);
    final tail = find.byWidgetPredicate(
      (widget) => widget.runtimeType.toString() == '_BubbleTail',
    );
    expect(tail, findsOneWidget);
    final tailRect = tester.getRect(tail);
    expect(tailRect.top, speech.bottom);
    expect(tailRect.center.dx, speech.center.dx);
    // The row keeps 8 above the bubbles and the 19 they stand above their
    // avatars, so its height is the same with or without bubbles.
    expect(tester.getSize(find.byType(ReorderableList)).height, 140);
    await finishFakeChatList(tester, client);
  });

  testWidgets('unread pins say so in bold and a bubble, without a dot', (
    tester,
  ) async {
    final semantics = tester.ensureSemantics();
    chat('Ada', 3, unread: 3).pin();
    chat('Bea', 2).pin();
    chat('Cy', 1);
    await pumpFakeChatList(tester, client);

    // No dot before the names.
    expect(
      find.descendant(
        of: find.byType(ReorderableList),
        matching: find.byWidgetPredicate(
          (widget) =>
              widget is Container &&
              widget.constraints?.maxWidth == 8 &&
              widget.constraints?.maxHeight == 8,
        ),
      ),
      findsNothing,
    );
    FontWeight? weight(String name) =>
        tester.widget<Text>(find.text(name)).style?.fontWeight;
    expect(weight('Ada'), FontWeight.w700);
    expect(weight('Bea'), isNot(FontWeight.w700));
    // Only the unread pin shows its newest message.
    expect(find.text('hello from Ada'), findsOneWidget);
    expect(find.text('hello from Bea'), findsNothing);
    // A screen reader hears what the dot showed.
    expect(find.bySemanticsLabel(RegExp(r'Unread: 3')), findsOneWidget);
    semantics.dispose();
    await finishFakeChatList(tester, client);
  });

  testWidgets('a pin name sits centred under its avatar', (tester) async {
    chat('Ada', 3, unread: 1).pin();
    chat('Bea', 2).pin();
    chat('Cy', 1);
    await pumpFakeChatList(tester, client);

    final avatars =
        pinnedAvatars()
            .evaluate()
            .map((e) => tester.getCenter(find.byWidget(e.widget)).dx)
            .toList()
          ..sort();
    expect(tester.getCenter(find.text('Ada')).dx, avatars[0]);
    expect(tester.getCenter(find.text('Bea')).dx, avatars[1]);
    await finishFakeChatList(tester, client);
  });

  testWidgets('an unread pin past the right edge shows a count there', (
    tester,
  ) async {
    // Ten pins are wider than the 800dp test screen; the unread one is
    // last.
    for (var i = 0; i < 10; i++) {
      chat('Pin$i', 20 - i, unread: i == 9 ? 1 : 0).pin((i + 1) / 11);
    }
    await pumpFakeChatList(tester, client);
    expect(find.text('1'), findsOneWidget);

    await tester.tap(find.text('1'));
    await tester.pumpAndSettle();
    expect(find.text('1'), findsNothing);
    expect(tester.getTopRight(find.text('Pin9')).dx, lessThanOrEqualTo(800));
    await finishFakeChatList(tester, client);
  });
}
