// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/utils/fallback_avatar_image.dart';
import 'package:fluffychat/utils/group_members_collage.dart';
import 'package:fluffychat/utils/notification_avatar_extension.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:matrix/matrix.dart';

/// The side of a drawn shortcut icon, as `renderFallbackAvatar` draws it.
const _drawnIconSize = 216;

/// How much of a shortcut icon a members' collage takes up. Android masks
/// an adaptive icon to a circle as wide as its middle two thirds; the faces
/// of a four member grid reach 0.61 of the collage's side from its centre,
/// so a collage at 0.54 of the icon stays inside that circle.
const shortcutCollageFill = 0.54;

/// The picture of [room]'s conversation shortcut, named [name]. Android
/// shows it as the icon of the chat's notifications, its bubble and its
/// share target, and updates them whenever the shortcut is pushed again.
///
/// It is the chat list's picture of the chat: the room's avatar (for a
/// direct chat, the person's photo), else for a group without one its
/// members' collage, else its initials.
Future<Uint8List?> conversationShortcutIcon(
  Client client,
  Room room,
  String name,
) async {
  final avatar = await client.tryDownloadNotificationAvatar(room.avatar);
  if (avatar != null) return avatar;
  if (GroupAvatar.shows(room)) {
    final collage = await groupMembersCollage(
      client,
      room,
      size: _drawnIconSize,
      fill: shortcutCollageFill,
    );
    if (collage != null) return collage;
  }
  // Given no image, the share sheet shows an empty grey circle.
  return renderFallbackAvatar(name, size: _drawnIconSize);
}
