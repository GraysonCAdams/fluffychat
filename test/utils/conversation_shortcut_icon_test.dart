// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/utils/conversation_shortcut_icon.dart';
import 'package:fluffychat/utils/fallback_avatar_image.dart';
import 'package:fluffychat/utils/notification_avatar_extension.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'message_search/search_test_client.dart';

/// The alpha of the pixel at ([x], [y]) of the PNG [bytes].
Future<int> _alphaAt(Uint8List bytes, int x, int y) async {
  final codec = await ui.instantiateImageCodec(bytes);
  final image = (await codec.getNextFrame()).image;
  final data = (await image.toByteData())!;
  final alpha = data.getUint8((y * image.width + x) * 4 + 3);
  image.dispose();
  return alpha;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });

  test(
    'a group without a picture gets its members, not its initials',
    () async {
      final client = await createSearchTestClient();
      final room = client.rooms.firstWhere(
        (room) => !room.isSpace && !room.isDirectChat,
      );
      expect(GroupAvatar.shows(room), isTrue);
      for (final id in ['@drew:example.org', '@harrison:example.org']) {
        room.setState(
          StrippedStateEvent(
            type: EventTypes.RoomMember,
            stateKey: id,
            senderId: id,
            content: {'membership': 'join', 'displayname': id.substring(1, 5)},
          ),
        );
      }
      const name = 'Drew Andersen, Harrison Young';

      final icon = await conversationShortcutIcon(client, room, name);

      expect(icon, isNotNull);
      expect(icon, isNot(equals(await renderFallbackAvatar(name))));
      // The initials fill the square with their colour; the collage leaves
      // the corners clear and puts a face in the middle, inside the circle
      // Android masks the icon to.
      expect(await _alphaAt(icon!, 0, 0), 0);
      expect(await _alphaAt(icon, 108, 108), 255);
      // Nothing outside that circle, a third of the side from the middle.
      expect(await _alphaAt(icon, 40, 40), 0);
      expect(await _alphaAt((await renderFallbackAvatar(name))!, 0, 0), 255);
    },
  );

  test('a direct chat gets the person\'s photo', () async {
    final client = await createSearchTestClient();
    final dm = client.rooms.firstWhere((room) => room.isDirectChat);
    final partner = dm.directChatMatrixID!;
    final photo = Uri.parse('mxc://example.org/drew');
    dm.setState(
      StrippedStateEvent(
        type: EventTypes.RoomMember,
        stateKey: partner,
        senderId: partner,
        content: {'membership': 'join', 'avatar_url': photo.toString()},
      ),
    );
    expect(dm.avatar, photo);
    expect(GroupAvatar.shows(dm), isFalse);
    // The homeserver serves the photo as a thumbnail.
    final served = (await renderFallbackAvatar('Zed'))!;
    // Asked of the fake homeserver before it is swapped out, and kept.
    expect(await client.authenticatedMediaSupported(), isTrue);
    final requested = <Uri>[];
    client.httpClient = MockClient((request) async {
      requested.add(request.url);
      return request.url.path.endsWith('/media/thumbnail/example.org/drew')
          ? http.Response.bytes(served, 200)
          : http.Response('{"errcode":"M_NOT_FOUND"}', 404);
    });

    final icon = await conversationShortcutIcon(client, dm, 'Drew');

    expect(requested.single.path, endsWith('/thumbnail/example.org/drew'));
    expect(icon, isNotNull);
    expect(icon, isNot(equals(await renderFallbackAvatar('Drew'))));
    expect(icon, await client.tryDownloadNotificationAvatar(photo));
  });
}
