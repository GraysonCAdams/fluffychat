// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/state_event_summary.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_search/search_test_client.dart';
import 'state_event_fixtures.dart';

void main() {
  late Client client;
  late L10n l10n;
  late BridgedChatFixture chat;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await createSearchTestClient();
    l10n = await lookupL10n(const Locale('en'));
  });

  tearDownAll(() => client.dispose(closeDatabase: true));

  setUp(() {
    chat = BridgedChatFixture(
      client.rooms.firstWhere((room) => room.isDirectChat),
    );
  });

  group('line', () {
    test('drops the symbol the translation puts first', () {
      expect(
        StateEventSummary.line(chat.gloriaAccepted(), l10n),
        'Gloria accepted the invitation',
      );
    });

    test('names the bridge bot by its network', () {
      expect(
        StateEventSummary.line(chat.botInvitedGloria(), l10n),
        'Google Messages invited Gloria',
      );
      expect(
        StateEventSummary.line(chat.botRenamed(), l10n),
        'Google Messages changed the chat name',
      );
    });

    test('keeps the bot name when the bridge names no network', () {
      chat = BridgedChatFixture(
        client.rooms.firstWhere((room) => room.isDirectChat),
        withNetworkName: false,
      );
      expect(
        StateEventSummary.line(chat.botInvitedGloria(), l10n),
        'Google Messages bridge bot invited Gloria',
      );
    });
  });

  group('isHousekeeping', () {
    test('the own join and everything the bot sets up', () {
      expect(StateEventSummary.isHousekeeping(chat.ownAccepted()), isTrue);
      expect(StateEventSummary.isHousekeeping(chat.botInvitedGloria()), isTrue);
      expect(StateEventSummary.isHousekeeping(chat.botRenamed()), isTrue);
      expect(StateEventSummary.isHousekeeping(chat.botChangedAvatar()), isTrue);
    });

    test('not what people do, nor the bot removing someone', () {
      expect(StateEventSummary.isHousekeeping(chat.gloriaAccepted()), isFalse);
      expect(StateEventSummary.isHousekeeping(chat.gloriaRenamed()), isFalse);
      expect(StateEventSummary.isHousekeeping(chat.botKickedGloria()), isFalse);
    });
  });

  group('headlineIndex', () {
    test('is the newest event that is not housekeeping', () {
      expect(
        StateEventSummary.headlineIndex([
          chat.ownAccepted(),
          chat.gloriaAccepted(),
          chat.botRenamed(),
          chat.botChangedAvatar(),
        ]),
        1,
      );
    });

    test('is the newest event when all are housekeeping', () {
      expect(
        StateEventSummary.headlineIndex([
          chat.ownAccepted(),
          chat.botRenamed(),
          chat.botChangedAvatar(),
        ]),
        2,
      );
    });
  });

  group('runAt', () {
    test('returns the whole run, oldest first, from any of its events', () {
      final older = chat.message('Before', minute: 0);
      final a = chat.ownAccepted(minute: 1);
      final b = chat.botInvitedGloria(minute: 2);
      final c = chat.gloriaAccepted(minute: 3);
      final newer = chat.message('After', minute: 4);
      final newestFirst = [newer, c, b, a, older];
      for (final index in [1, 2, 3]) {
        expect(StateEventSummary.runAt(newestFirst, index), [a, b, c]);
      }
      expect(StateEventSummary.runAt(newestFirst, 0), isNull);
      expect(StateEventSummary.runAt(newestFirst, 4), isNull);
    });

    test('a system event on its own is not a run', () {
      final newestFirst = [
        chat.message('After', minute: 2),
        chat.gloriaRenamed(minute: 1),
        chat.message('Before'),
      ];
      expect(StateEventSummary.runAt(newestFirst, 1), isNull);
    });
  });
}
