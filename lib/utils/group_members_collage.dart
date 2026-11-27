// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/utils/group_collage_image.dart';
import 'package:fluffychat/utils/notification_avatar_extension.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:matrix/matrix.dart';

final Map<String, Uint8List?> _collageCache = {};

/// The picture of a group chat without an avatar of its own, outside the
/// chat list: its members' photos as `GroupAvatar` shows them, drawn by
/// [renderGroupCollage] into the middle [fill] of the square. Null when
/// fewer than two members can be loaded.
Future<Uint8List?> groupMembersCollage(
  Client client,
  Room room, {
  int size = notificationAvatarDimension,
  double fill = 1,
}) async {
  await GroupAvatar.loadMembers(
    room,
  ).timeout(const Duration(seconds: 4), onTimeout: () {});
  final users = (await Future.wait(
    GroupAvatar.memberIds(room, max: 4).map(
      (id) => room
          .requestUser(id, ignoreErrors: true, requestProfile: false)
          .timeout(const Duration(seconds: 2), onTimeout: () => null),
    ),
  )).nonNulls.toList();
  if (users.length < 2) return null;
  final key =
      'collage:${room.id}:$size:$fill:'
      '${users.map((u) => '${u.id}${u.avatarUrl}').join()}';
  if (_collageCache.containsKey(key)) return _collageCache[key];
  final members = await Future.wait(
    users.map(
      (user) async => (
        name: user.calcDisplayname(),
        image: await client.tryDownloadNotificationAvatar(user.avatarUrl),
      ),
    ),
  );
  return _collageCache[key] = await renderGroupCollage(
    members,
    size: size,
    fill: fill,
  );
}
