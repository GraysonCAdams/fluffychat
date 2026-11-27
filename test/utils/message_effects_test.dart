// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n_en.dart';
import 'package:fluffychat/pages/chat/effects/played_message_effects.dart';
import 'package:fluffychat/pages/chat_list/message_preview_cache.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'merged_contacts/fake_rooms.dart';
import 'message_search/search_test_client.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late Room iMessage;
  late Room whatsApp;
  final l10n = L10nEn();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    MatrixFeatures.scanStoredState = false;
    client = await fakeMergedClient();
    iMessage = addDirectChat(
      client,
      id: '!imessage:example.org',
      partner: '@imessage_15551234567:example.org',
      name: 'Ada',
    );
    whatsApp = addDirectChat(
      client,
      id: '!whatsapp:example.org',
      partner: '@whatsapp_15551234567:example.org',
      name: 'Ada',
    );
  });

  Event message(
    Map<String, Object?> content, {
    Room? room,
    String id = '\$event',
    DateTime? at,
    Map<String, Object?>? unsigned,
  }) => Event(
    content: content,
    type: EventTypes.Message,
    eventId: id,
    senderId: '@imessage_15551234567:example.org',
    originServerTs: at ?? DateTime.now(),
    unsigned: unsigned,
    room: room ?? iMessage,
  );

  const text = <String, Object?>{'msgtype': 'm.text', 'body': 'The password'};

  group('the adapter', () {
    test('covers every effect iMessage sends', () {
      expect(MessageEffect.values, hasLength(13));
      expect(MessageEffect.ofKind(MessageEffectKind.bubble), hasLength(4));
      expect(MessageEffect.ofKind(MessageEffectKind.screen), hasLength(9));
      expect(
        MessageEffect.values.map((effect) => effect.id).toSet(),
        hasLength(13),
        reason: 'two effects share an id',
      );
    });

    for (final effect in MessageEffect.values) {
      test('${effect.name} survives the round trip through content', () {
        final content = withEffect(text, effect);
        expect(content['body'], 'The password');
        expect(content[messageEffectKey], effect.id);
        expect(effectOf(message(content)), effect);
        expect(MessageEffect.fromId(effect.id), effect);
        expect(effect.localizedName(l10n), isNotEmpty);
      });
    }

    test('the key and ids are the ones the bridge reads', () {
      expect(messageEffectKey, 'com.beeper.imessage.effect');
      expect(
        {for (final effect in MessageEffect.values) effect.name: effect.id},
        {
          'slam': 'com.apple.MobileSMS.expressivesend.impact',
          'loud': 'com.apple.MobileSMS.expressivesend.loud',
          'gentle': 'com.apple.MobileSMS.expressivesend.gentle',
          'invisibleInk': 'com.apple.MobileSMS.expressivesend.invisibleink',
          'echo': 'com.apple.messages.effect.CKEchoEffect',
          'spotlight': 'com.apple.messages.effect.CKSpotlightEffect',
          'balloons': 'com.apple.messages.effect.CKHappyBirthdayEffect',
          'confetti': 'com.apple.messages.effect.CKConfettiEffect',
          'love': 'com.apple.messages.effect.CKHeartEffect',
          'lasers': 'com.apple.messages.effect.CKLasersEffect',
          'fireworks': 'com.apple.messages.effect.CKFireworksEffect',
          'celebration': 'com.apple.messages.effect.CKSparklesEffect',
          'shootingStar': 'com.apple.messages.effect.CKShootingStarEffect',
        },
      );
    });

    test('reads no effect from a plain message or an unknown id', () {
      expect(effectOf(message(text)), isNull);
      expect(
        effectOf(message({...text, messageEffectKey: 'com.apple.new'})),
        isNull,
      );
      expect(effectOf(message({...text, messageEffectKey: 7})), isNull);
    });

    test('only an iMessage chat can send effects', () {
      expect(canSendMessageEffects(iMessage), isTrue);
      expect(canSendMessageEffects(whatsApp), isFalse);
    });

    test('a group tells by the network its bridge names', () {
      Room group(String id, String network) {
        final room = Room(id: id, client: client);
        room.setState(
          StrippedStateEvent(
            type: 'm.bridge',
            content: {
              'bridgebot': '@bot:example.org',
              'protocol': {'id': network.toLowerCase(), 'displayname': network},
            },
            senderId: '@bot:example.org',
            stateKey: 'x',
          ),
        );
        return room;
      }

      expect(
        canSendMessageEffects(group('!g1:example.org', 'iMessage')),
        isTrue,
      );
      expect(
        canSendMessageEffects(group('!g2:example.org', 'Signal')),
        isFalse,
      );
      expect(
        canSendMessageEffects(Room(id: '!plain:example.org', client: client)),
        isFalse,
      );
    });
  });

  group('sending', () {
    test('the content carries the text and the effect', () {
      final content = iMessage.textContentWithEffect(
        'Happy birthday',
        MessageEffect.balloons,
      );
      expect(content['msgtype'], 'm.text');
      expect(content['body'], 'Happy birthday');
      expect(content[messageEffectKey], MessageEffect.balloons.id);
      expect(content.containsKey('formatted_body'), isFalse);
    });

    test('markdown is formatted as in a plain send', () {
      final content = iMessage.textContentWithEffect(
        '**Wow** & more',
        MessageEffect.loud,
      );
      expect(content['formatted_body'], '<strong>Wow</strong> &amp; more');
      expect(content[messageEffectKey], MessageEffect.loud.id);
      expect(
        iMessage
            .textContentWithEffect('1 < 2 & 3', MessageEffect.loud)
            .containsKey('formatted_body'),
        isFalse,
      );
    });

    test('the sent event has the effect on it', () async {
      final sending = await createSearchTestClient();
      final room = sending.rooms.firstWhere((room) => !room.isSpace);
      await room.sendTextEventWithEffect('Boom', MessageEffect.fireworks);
      final sent = room.lastEvent!;
      expect(sent.body, 'Boom');
      expect(effectOf(sent), MessageEffect.fireworks);
    });
  });

  group('invisible ink previews', () {
    test('the text is replaced wherever a preview is shown', () {
      final ink = message(withEffect(text, MessageEffect.invisibleInk));
      expect(effectPreviewOf(ink, l10n), 'Sent with Invisible Ink');
      expect(
        MessagePreviewCache.preview(ink, l10n, MatrixLocals(l10n)).text,
        'Sent with Invisible Ink',
      );
    });

    test(
      'the spoiler the bridge wraps the text in comes off in the bubble',
      () {
        const html = '<span data-mx-spoiler>The <b>password</b></span>';
        final ink = message({
          ...withEffect(text, MessageEffect.invisibleInk),
          'format': 'org.matrix.custom.html',
          'formatted_body': html,
        }, id: '\$spoiler');
        expect(effectBodyHtml(ink, html), '<span>The <b>password</b></span>');
        expect(
          effectBodyHtml(ink, '<span data-mx-spoiler="reason">x</span>'),
          '<span>x</span>',
        );
        // A spoiler somebody wrote stays one.
        expect(effectBodyHtml(message(text, id: '\$typed'), html), html);
        expect(
          effectBodyHtml(
            message(withEffect(text, MessageEffect.loud), id: '\$loud2'),
            html,
          ),
          html,
        );
      },
    );

    test('other messages keep their text', () {
      final loud = message(withEffect(text, MessageEffect.loud), id: '\$loud');
      expect(effectPreviewOf(loud, l10n), isNull);
      expect(effectPreviewOf(message(text, id: '\$plain'), l10n), isNull);
      expect(
        MessagePreviewCache.preview(loud, l10n, MatrixLocals(l10n)).text,
        contains('The password'),
      );
    });
  });

  group('playing once', () {
    setUp(() async {
      await AppSettings.playedMessageEffects.setItem('[]');
      PlayedMessageEffects.resetForTest();
    });

    test('a new message plays, then never again', () {
      final event = message(withEffect(text, MessageEffect.confetti));
      expect(PlayedMessageEffects.shouldAutoPlay(event), isTrue);
      PlayedMessageEffects.markPlayed(event);
      expect(PlayedMessageEffects.shouldAutoPlay(event), isFalse);
      // Not after a restart either.
      PlayedMessageEffects.resetForTest();
      expect(PlayedMessageEffects.shouldAutoPlay(event), isFalse);
    });

    test('a message played while sending stays played once sent', () {
      final content = withEffect(text, MessageEffect.confetti);
      final echo = message(
        content,
        id: 'txn1',
        unsigned: {'transaction_id': 'txn1'},
      );
      PlayedMessageEffects.markPlayed(echo);
      final synced = message(
        content,
        id: '\$real',
        unsigned: {'transaction_id': 'txn1'},
      );
      expect(PlayedMessageEffects.shouldAutoPlay(synced), isFalse);
    });

    test('an old message does not play by itself', () {
      final old = message(
        withEffect(text, MessageEffect.confetti),
        at: DateTime.now().subtract(const Duration(days: 2)),
      );
      expect(PlayedMessageEffects.shouldAutoPlay(old), isFalse);
    });
  });
}
