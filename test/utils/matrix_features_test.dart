// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/room_features.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../pages/chat_list/chat_list_fakes.dart';

/// Adds [userId] to [room] as a joined member.
void join(Room room, String userId) => room.setState(
  StrippedStateEvent(
    type: EventTypes.RoomMember,
    content: {'membership': 'join'},
    senderId: userId,
    stateKey: userId,
  ),
);

void main() {
  late FakeChatListClient client;
  late MatrixFeatures features;

  setUp(() async {
    client = await setUpFakeChatList('matrix features test');
    features = MatrixFeatures(client);
  });

  tearDown(() {
    features.dispose();
    tearDownFakeChatList(client);
  });

  /// A bridged direct chat with [ghost], its bot also a member.
  Room bridgedChat(String id, String ghost, {String network = 'iMessage'}) {
    final room = addFakeChat(client, id, id, partner: ghost);
    final bot = '@${network.toLowerCase()}bot:x';
    addFakeBridge(room, bot: bot, network: network);
    join(room, bot);
    return room;
  }

  group('auto detection', () {
    test('an account with no chats is in messenger mode', () {
      expect(features.signals.realContacts, 0);
      expect(features.signals.messengerMode, isTrue);
      expect(features.isRelevant(MatrixFeature.status), isFalse);
      expect(features.isRelevant(MatrixFeature.identity), isFalse);
      expect(features.isRelevant(MatrixFeature.explore), isFalse);
    });

    test('bridged chats alone keep messenger mode', () {
      bridgedChat('!a:x', '@imessage_tel=3a+14045550142:x');
      bridgedChat('!b:x', '@gmessages_1.2:x', network: 'Google Messages');
      expect(features.signals.realContacts, 0);
      expect(features.isRelevant(MatrixFeature.status), isFalse);
    });

    test('a plain Matrix chat brings the features back', () {
      bridgedChat('!a:x', '@imessage_tel=3a+14045550142:x');
      addFakeChat(client, '!kim:x', 'Kim', partner: '@kim:matrix.org');
      expect(features.signals.realContacts, 1);
      expect(features.signals.messengerMode, isFalse);
      for (final feature in [
        MatrixFeature.status,
        MatrixFeature.identity,
        MatrixFeature.fullUserIds,
        MatrixFeature.explore,
      ]) {
        expect(features.isRelevant(feature), isTrue, reason: feature.name);
      }
    });

    test('the older uk.half-shot.bridge event marks a chat bridged', () {
      final room = addFakeChat(client, '!a:x', 'A', partner: '@ghost:x');
      addFakeBridge(room, type: 'uk.half-shot.bridge');
      expect(features.isBridged(room), isTrue);
      expect(features.signals.realContacts, 0);
    });

    test('puppets and bridge bots in plain rooms are not contacts', () {
      bridgedChat('!a:x', '@imessage_tel=3a+14045550142:x');
      // A group made on Matrix with the same puppet, and the management
      // room with the bridge bot.
      final group = addFakeChat(client, '!g:x', 'Group');
      join(group, '@imessage_tel=3a+14045550142:x');
      addFakeChat(
        client,
        '!mgmt:x',
        'iMessage bridge',
        partner: '@imessagebot:x',
      );
      // A bot of a bridge that has no chat yet, recognised by its name.
      addFakeChat(
        client,
        '!tg:x',
        'Telegram bridge',
        partner: '@telegrambot:x',
      );
      // The fake chat's default sender is a member too.
      expect(features.signals.realContacts, 1);
      expect(
        features.bridgeUsers,
        containsAll(['@imessage_tel=3a+14045550142:x', '@imessagebot:x']),
      );
    });

    test('the user is never their own contact', () {
      addFakeChat(client, '!notes:x', 'Notes', partner: '@me:x');
      expect(features.signals.realContacts, 0);
    });

    test('server notices are not contacts', () {
      final room = addFakeChat(
        client,
        '!notice:x',
        'Notices',
        partner: '@notices:other',
      );
      room.roomAccountData['m.tag'] = BasicEvent(
        type: 'm.tag',
        content: {
          'tags': {TagType.serverNotice: {}},
        },
      );
      expect(features.signals.realContacts, 0);
    });

    test('a bridge space does not count as a space; a Matrix one does', () {
      bridgedChat('!a:x', '@imessage_tel=3a+14045550142:x');
      addFakeSpace(client, '!net:x', 'iMessage', ['!a:x']);
      expect(features.signals.hasSpaces, isFalse);
      expect(features.isRelevant(MatrixFeature.spaces), isFalse);

      final invite = Room(
        id: '!club:matrix.org',
        client: client,
        membership: Membership.invite,
      );
      invite.setState(
        StrippedStateEvent(
          type: EventTypes.RoomCreate,
          content: {'type': RoomCreationTypes.mSpace},
          senderId: '@kim:matrix.org',
          stateKey: '',
        ),
      );
      client.rooms.add(invite);
      features.recompute();
      expect(features.isRelevant(MatrixFeature.spaces), isTrue);
    });

    test('custom emotes show once a room has a pack', () {
      final room = addFakeChat(client, '!a:x', 'A');
      expect(features.isRelevant(MatrixFeature.customEmotes), isFalse);
      room.setState(
        StrippedStateEvent(
          type: 'im.ponies.room_emotes',
          content: {
            'images': {
              'blob': {'url': 'mxc://x/blob'},
            },
          },
          senderId: '@me:x',
          stateKey: '',
        ),
      );
      features.recompute();
      expect(features.isRelevant(MatrixFeature.customEmotes), isTrue);
    });

    test('room plumbing is decided per chat', () {
      final bridged = bridgedChat('!a:x', '@imessage_tel=3a+14045550142:x');
      final plain = addFakeChat(
        client,
        '!kim:x',
        'Kim',
        partner: '@kim:matrix.org',
      );
      expect(
        features.isRelevant(MatrixFeature.roomPlumbing, room: bridged),
        isFalse,
      );
      expect(
        features.isRelevant(MatrixFeature.roomPlumbing, room: plain),
        isTrue,
      );
    });

    test('listeners hear when the signals change', () {
      expect(features.signals.messengerMode, isTrue);
      var calls = 0;
      features.addListener(() => calls++);
      features.recompute();
      expect(calls, 0);
      addFakeChat(client, '!kim:x', 'Kim', partner: '@kim:matrix.org');
      features.recompute();
      expect(calls, 1);
    });
  });

  group('mode and overrides', () {
    test('auto is the default', () {
      expect(features.mode, MatrixFeaturesMode.auto);
      expect(features.overrides, isEmpty);
    });

    test('always show and always hide beat detection', () async {
      final bridged = bridgedChat('!a:x', '@imessage_tel=3a+14045550142:x');
      await features.setMode(MatrixFeaturesMode.alwaysShow);
      for (final feature in MatrixFeature.values) {
        expect(
          features.isRelevant(feature, room: bridged),
          isTrue,
          reason: feature.name,
        );
      }
      await features.setMode(MatrixFeaturesMode.alwaysHide);
      for (final feature in MatrixFeature.values) {
        expect(features.isRelevant(feature), isFalse, reason: feature.name);
      }
    });

    test('an override beats the mode and can be removed', () async {
      await features.setOverride(
        MatrixFeature.status,
        MatrixFeatureOverride.show,
      );
      expect(features.isRelevant(MatrixFeature.status), isTrue);
      await features.setMode(MatrixFeaturesMode.alwaysHide);
      expect(features.isRelevant(MatrixFeature.status), isTrue);
      expect(features.isRelevant(MatrixFeature.identity), isFalse);
      await features.setOverride(MatrixFeature.status, null);
      expect(features.isRelevant(MatrixFeature.status), isFalse);
    });

    test('unreadable stored settings fall back to auto', () async {
      await AppSettings.matrixFeaturesMode.setItem('sometimes');
      await AppSettings.matrixFeatureOverrides.setItem('{"status": "maybe"');
      expect(features.mode, MatrixFeaturesMode.auto);
      expect(features.overrides, isEmpty);
    });
  });

  group('user labels', () {
    test('messenger mode shortens own IDs and names bridge contacts', () {
      final room = bridgedChat('!a:x', '@imessage_tel=3a+14045550142:x');
      expect(features.userLabel('@gray:x'), '@gray');
      expect(features.userLabel('@kim:matrix.org'), '@kim:matrix.org');
      expect(
        features.userLabel('@imessage_tel=3a+14045550142:x', room: room),
        '+1 404 555 0142 · iMessage',
      );
      // A ghost whose ID carries no number shows its network.
      final gm = bridgedChat(
        '!b:x',
        '@gmessages_1.2:x',
        network: 'Google Messages',
      );
      expect(
        features.userLabel('@gmessages_1.2:x', room: gm),
        'Google Messages',
      );
      // Without the room, the puppet is known once the signals are worked
      // out again, as a sync does.
      features.recompute();
      expect(features.userLabel('@gmessages_1.2:x'), 'Google Messages');
    });

    test('full IDs return with the feature', () async {
      await features.setOverride(
        MatrixFeature.fullUserIds,
        MatrixFeatureOverride.show,
      );
      expect(features.userLabel('@gray:x'), '@gray:x');
    });
  });

  group('stored state scan', () {
    test('finds bridges in state not kept in memory and caches them', () async {
      final room = addFakeChat(client, '!old:x', 'Old', partner: '@ghost:x');
      final scanned = <String>[];
      final scanner = MatrixFeatures(
        client,
        storedState: (room) async {
          scanned.add(room.id);
          return [
            StrippedStateEvent(
              type: 'm.bridge',
              content: {'bridgebot': '@bot:x'},
              senderId: '@bot:x',
              stateKey: 'k',
            ),
          ];
        },
      );
      // Until the scan has read the room, it counts as neither kind.
      expect(scanner.scanning, isTrue);
      expect(scanner.signals.realContacts, 0);
      await pumpEventQueue();
      expect(scanned, ['!old:x']);
      expect(scanner.isBridged(room), isTrue);
      scanner.dispose();

      // The next start reads the cache instead of scanning again.
      final next = MatrixFeatures(
        client,
        storedState: (room) async {
          scanned.add(room.id);
          return [];
        },
      );
      await pumpEventQueue();
      expect(scanned, ['!old:x']);
      expect(next.isBridged(room), isTrue);
      next.dispose();
    });
  });

  group('room features', () {
    test('state changes are allowed only where the network says so', () {
      final features = RoomFeatures.fromJson({
        'state': {
          'm.room.name': {'level': CapabilityLevel.full},
          'm.room.avatar': {'level': CapabilityLevel.unsupported},
        },
      });
      expect(features.isUnrestricted, isTrue);
      expect(features.allowsState('m.room.name'), isTrue);
      expect(features.allowsState('m.room.avatar'), isFalse);
      expect(features.allowsState('m.room.topic'), isFalse);
      expect(RoomFeatures.unrestricted.allowsState('m.room.name'), isFalse);
    });
  });
}
