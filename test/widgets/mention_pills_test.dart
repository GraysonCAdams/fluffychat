// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/html_message.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;

  setUp(() async {
    client = await setUpFakeChatList('mention pills test');
  });

  tearDown(() => tearDownFakeChatList(client));

  const harrison = '@imessage_tel=3a+1XXXXXXXXXX:d.graysons.network';

  void addMember(Room room, String id, String name) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': name},
      senderId: id,
      stateKey: id,
    ),
  );

  Room groupRoom({bool withHarrison = true}) {
    final room = addFakeChat(client, '!group:x', 'Drew, Harrison');
    addMember(room, '@imessage_drew:d.graysons.network', 'Drew Andersen');
    if (withHarrison) addMember(room, harrison, 'Harrison Young');
    addMember(room, client.userID!, 'Gray');
    return room;
  }

  Event message(Room room, Map<String, Object?> content) => Event(
    content: content,
    type: EventTypes.Message,
    eventId: '\$mention',
    senderId: '@imessage_drew:d.graysons.network',
    originServerTs: DateTime(2026, 11, 27, 10),
    status: EventStatus.synced,
    room: room,
  );

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
    await tester.pumpAndSettle();
  }

  Finder pill(String userId) => find.byKey(Key('user_pill_$userId'));
  const chipKey = ValueKey('mention_chip');
  const labelKey = ValueKey('mention_label');
  const roomGlyphKey = ValueKey('mention_room_glyph');
  String pillName(WidgetTester tester, String userId) =>
      tester.widget<MatrixPill>(pill(userId)).name;

  /// The iMessage bridge's mention, as it sends it.
  Map<String, Object?> bridgeMention(String formattedBody) => {
    'msgtype': 'm.text',
    'body': 'Cuz our discussion was after @Harrison and I’s',
    'format': 'org.matrix.custom.html',
    'formatted_body': formattedBody,
    'm.mentions': {
      'user_ids': [harrison],
    },
  };

  group('a formatted mention from the bridge', () {
    testWidgets('is a pill for the member, whose ID has =3a and +', (
      tester,
    ) async {
      final room = groupRoom();
      await pump(
        tester,
        message(
          room,
          bridgeMention(
            'Cuz our discussion was after <a href="https://matrix.to/#/'
            '$harrison">Harrison</a> and I’s',
          ),
        ),
      );
      expect(pill(harrison), findsOneWidget);
      // Labelled as written, though the member's name is Harrison Young.
      expect(pillName(tester, harrison), 'Harrison');
      expect(
        find.textContaining('@Harrison', findRichText: true),
        findsNothing,
      );
    });

    testWidgets('a user ID as link text gives way to the display name', (
      tester,
    ) async {
      final room = groupRoom();
      await pump(
        tester,
        message(
          room,
          bridgeMention(
            'after <a href="https://matrix.to/#/$harrison">$harrison</a>',
          ),
        ),
      );
      expect(pillName(tester, harrison), 'Harrison Young');
    });

    testWidgets('names a member not loaded yet by the link text', (
      tester,
    ) async {
      final room = groupRoom(withHarrison: false);
      await pump(
        tester,
        message(
          room,
          bridgeMention(
            'after <a href="https://matrix.to/#/$harrison">Harrison</a> and',
          ),
        ),
      );
      expect(pillName(tester, harrison), 'Harrison');
      // Lets the member lookup the pill started run out.
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('keeps the pill among the bridge\'s other markup', (
      tester,
    ) async {
      final room = groupRoom();
      await pump(
        tester,
        message(
          room,
          bridgeMention(
            '<strong>Cuz</strong> <em>our</em> <u>discussion</u> '
            '<del>was</del><br/><span data-mx-imessage-effect="loud">after '
            '<a href="https://matrix.to/#/$harrison">Harrison</a></span> and',
          ),
        ),
      );
      expect(pill(harrison), findsOneWidget);
      expect(
        find.textContaining('discussion', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('a mention of the user is highlighted', (tester) async {
      final room = groupRoom();
      await pump(
        tester,
        message(room, {
          'msgtype': 'm.text',
          'body': 'Friday, @Gray',
          'format': 'org.matrix.custom.html',
          'formatted_body':
              'Friday, <a href="https://matrix.to/#/${client.userID}">Gray</a>',
        }),
      );
      expect(pill(client.userID!), findsOneWidget);
      expect(tester.widget<MatrixPill>(pill(client.userID!)).isUser, isTrue);
    });

    testWidgets('a mention of someone else is not highlighted', (tester) async {
      final room = groupRoom();
      await pump(
        tester,
        message(
          room,
          bridgeMention('<a href="https://matrix.to/#/$harrison">Harrison</a>'),
        ),
      );
      expect(
        find.byWidgetPredicate((w) => w is MatrixPill && w.isUser),
        findsNothing,
      );
    });
  });

  group('one mention chip', () {
    Finder chip(Finder pill) =>
        find.descendant(of: pill, matching: find.byKey(chipKey));
    Finder label(Finder pill) =>
        find.descendant(of: pill, matching: find.byKey(labelKey));

    Future<void> pumpBoth(WidgetTester tester) async {
      final room = groupRoom();
      await pump(
        tester,
        message(
          room,
          bridgeMention(
            'Friday, <a href="https://matrix.to/#/${client.userID}">Gray</a>'
            ' after <a href="https://matrix.to/#/$harrison">Harrison</a>'
            ' in <a href="https://matrix.to/#/#lounge:x">#lounge</a>',
          ),
        ),
      );
    }

    testWidgets('every mention has the same shape, avatar and type', (
      tester,
    ) async {
      await pumpBoth(tester);
      final own = pill(client.userID!);
      final other = pill(harrison);
      final room = find.byKey(const Key('room_pill_#lounge:x'));
      final chips = [chip(own), chip(other), chip(room)];
      for (final c in chips) {
        expect(c, findsOneWidget);
      }
      final height = tester.getSize(chips.first).height;
      for (final c in chips) {
        expect(tester.getSize(c).height, height);
        final box = tester.widget<DecoratedBox>(c).decoration as BoxDecoration;
        expect(box.borderRadius, BorderRadius.circular(height / 2));
      }
      for (final p in [own, other]) {
        final avatar = tester.widget<Avatar>(
          find.descendant(of: p, matching: find.byType(Avatar)),
        );
        expect(avatar.size, 16);
      }
      // The room pill has a # in the avatar's place, the same size.
      expect(
        tester.getSize(
          find.descendant(of: room, matching: find.byKey(roomGlyphKey)),
        ),
        const Size(16, 16),
      );
      final styles = [
        for (final p in [own, other, room])
          tester.widget<Text>(label(p)).style!,
      ];
      for (final style in styles) {
        expect(style.decoration, isNot(TextDecoration.underline));
        expect(style.fontSize, styles.first.fontSize);
        expect(style.height, styles.first.height);
      }
    });

    testWidgets('someone else is a neutral chip, the user the accent one', (
      tester,
    ) async {
      await pumpBoth(tester);
      final room = find.byKey(const Key('room_pill_#lounge:x'));
      final scheme = Theme.of(tester.element(pill(harrison))).colorScheme;
      Color fill(Finder p) =>
          (tester.widget<DecoratedBox>(chip(p)).decoration as BoxDecoration)
              .color!;
      TextStyle style(Finder p) => tester.widget<Text>(label(p)).style!;

      expect(fill(pill(harrison)), MatrixPill.neutralFill(scheme));
      expect(fill(room), MatrixPill.neutralFill(scheme));
      expect(style(pill(harrison)).color, scheme.onSurface);
      expect(style(pill(harrison)).fontWeight, isNot(FontWeight.bold));

      expect(fill(pill(client.userID!)), scheme.primaryContainer);
      expect(style(pill(client.userID!)).color, scheme.onPrimaryContainer);
      expect(style(pill(client.userID!)).fontWeight, FontWeight.bold);
    });
  });

  group('a plain text mention', () {
    testWidgets('of one member is a pill', (tester) async {
      final room = groupRoom();
      await pump(
        tester,
        message(room, {
          'msgtype': 'm.text',
          'body': 'Cuz our discussion was after @Harrison and I’s',
        }),
      );
      expect(pill(harrison), findsOneWidget);
      expect(pillName(tester, harrison), 'Harrison');
      expect(
        find.textContaining('@Harrison', findRichText: true),
        findsNothing,
      );
      expect(find.textContaining('and I’s', findRichText: true), findsWidgets);
    });

    testWidgets('is labelled with the name as typed', (tester) async {
      final room = groupRoom();
      await pump(
        tester,
        message(room, {'msgtype': 'm.text', 'body': 'ask @harrison young'}),
      );
      expect(pillName(tester, harrison), 'harrison young');
    });

    testWidgets('of the user is a highlighted pill', (tester) async {
      final room = groupRoom();
      await pump(
        tester,
        message(room, {'msgtype': 'm.text', 'body': 'Friday, @Gray'}),
      );
      expect(
        find.byWidgetPredicate((w) => w is MatrixPill && w.isUser),
        findsOneWidget,
      );
    });

    testWidgets('of a name two members share stays text', (tester) async {
      final room = groupRoom();
      addMember(room, '@imessage_drew2:d.graysons.network', 'Drew Barrymore');
      await pump(
        tester,
        message(room, {'msgtype': 'm.text', 'body': '@Drew you in?'}),
      );
      expect(find.byType(MatrixPill), findsNothing);
      expect(
        find.textContaining('@Drew you in?', findRichText: true),
        findsWidgets,
      );
    });

    testWidgets('in a merged chat finds members of the linked rooms', (
      tester,
    ) async {
      // The SMS side of the group has only Drew; Harrison is a member of
      // the linked iMessage room.
      final sms = addFakeChat(
        client,
        '!sms:x',
        'Drew Andersen',
        partner: '@sms_drew:x',
      );
      addMember(sms, '@sms_drew:x', 'Drew Andersen');
      addMember(sms, client.userID!, 'Gray');
      final imessage = groupRoom();
      await tester.runAsync(
        () =>
            MergedContactsStore.forClient(client).merge([imessage.id, sms.id]),
      );
      expect(
        MergedContactsStore.forClient(client).contactForRoom(sms.id),
        isNotNull,
      );
      await pump(
        tester,
        message(sms, {'msgtype': 'm.text', 'body': '@Harrison and @Drew'}),
      );
      expect(pill(harrison), findsOneWidget);
      // Drew is in both rooms under two IDs; the room's own Drew wins.
      expect(pill('@sms_drew:x'), findsOneWidget);
      // Harrison is not a member of this room: his pill shows the name as
      // written, while the member lookup it starts runs out.
      expect(pillName(tester, harrison), 'Harrison');
      await tester.pump(const Duration(seconds: 11));
    });

    testWidgets('leaves an e-mail address and a time alone', (tester) async {
      final room = groupRoom();
      await pump(
        tester,
        message(room, {
          'msgtype': 'm.text',
          'body': 'mail harrison@harrison.com @2pm',
        }),
      );
      expect(find.byType(MatrixPill), findsNothing);
    });
  });
}
