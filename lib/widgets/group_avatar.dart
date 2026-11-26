// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

extension GroupChatExtension on Room {
  /// Whether this is a group chat: neither a direct chat nor a space.
  bool get isGroupChat => !isDirectChat && !isSpace;
}

/// The picture of a group chat that has none of its own: its members as a
/// collage, two overlapping or three in a cluster, as Google Messages shows
/// them. With fewer than two members to show it is the usual [Avatar] with
/// the initials of [name].
///
/// Members come from memory first, then from the database, never from the
/// server, so a list of these scrolls without network calls.
class GroupAvatar extends StatefulWidget {
  final Room room;
  final String name;
  final double size;

  /// The color behind the avatar, which outlines each face so the faces
  /// read as separate.
  final Color? outlineColor;
  final void Function()? onTap;

  const GroupAvatar({
    required this.room,
    required this.name,
    this.size = Avatar.defaultSize,
    this.outlineColor,
    this.onTap,
    super.key,
  });

  /// Whether [room] is shown as a collage: a group without a picture.
  static bool shows(Room room) => room.isGroupChat && room.avatar == null;

  /// The members the collage of [room] shows, at most three: the sender of
  /// the newest message first, then the room's heroes, then whoever else is
  /// in memory. The user and the chat's bridge bot are left out.
  static List<String> memberIds(Room room) {
    final skip = {
      room.client.userID,
      MatrixFeatures.forClient(room.client).bridgeOf(room)?.bot,
    };
    final ids = <String>[];
    void add(String? id) {
      if (id == null || skip.contains(id) || ids.contains(id)) return;
      ids.add(id);
    }

    add(room.lastEvent?.senderId);
    room.summary.mHeroes?.forEach(add);
    if (ids.length < 3) {
      for (final user in room.getParticipants(const [Membership.join])) {
        add(user.id);
        if (ids.length >= 3) break;
      }
    }
    return ids.take(3).toList();
  }

  @override
  State<GroupAvatar> createState() => _GroupAvatarState();
}

class _GroupAvatarState extends State<GroupAvatar> {
  // Members missing from memory are loaded once per room and set of
  // members, not on every build: the chat list rebuilds its rows on every
  // sync.
  Object? _key;
  Future<List<User>>? _future;

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final ids = GroupAvatar.memberIds(room);
    final fromMemory = [
      for (final id in ids)
        if (room.getState(EventTypes.RoomMember, id) case final state?)
          state.asUser(room),
    ];
    if (fromMemory.length == ids.length) return _collage(context, fromMemory);
    final key = (room.id, ids.join('\n'));
    if (key != _key || _future == null) {
      _key = key;
      _future = Future.wait(
        ids.map(
          (id) async =>
              await room.requestUser(
                id,
                ignoreErrors: true,
                requestState: false,
                requestProfile: false,
              ) ??
              room.unsafeGetUserFromMemoryOrFallback(id),
        ),
      );
    }
    return FutureBuilder<List<User>>(
      future: _future,
      initialData: fromMemory,
      builder: (context, snapshot) =>
          _collage(context, snapshot.data ?? fromMemory),
    );
  }

  Widget _collage(BuildContext context, List<User> members) {
    final size = widget.size;
    if (members.length < 2) {
      return Avatar(name: widget.name, size: size, onTap: widget.onTap);
    }
    final outline =
        widget.outlineColor ?? Theme.of(context).colorScheme.surface;
    // Two faces are two thirds of the size, one top left and one bottom
    // right. Three are just over half, one centred on top and two below.
    final three = members.length >= 3;
    final face = three ? size * 0.54 : size * 2 / 3;
    final positions = three
        ? [
            Offset((size - face) / 2, 0),
            Offset(0, size * 0.42),
            Offset(size - face, size * 0.42),
          ]
        : [Offset.zero, Offset(size - face, size - face)];
    final ring = size >= 40 ? 2.0 : 1.5;
    final collage = SizedBox(
      width: size,
      height: size,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final (i, user) in members.take(3).indexed)
            Positioned(
              left: positions[i].dx,
              top: positions[i].dy,
              child: Avatar(
                mxContent: user.avatarUrl,
                name: user.calcDisplayname(),
                size: face,
                shapeBorder: RoundedSuperellipseBorder(
                  side: BorderSide(width: ring, color: outline),
                  borderRadius: BorderRadius.circular(face / 2),
                ),
              ),
            ),
        ],
      ),
    );
    final onTap = widget.onTap;
    if (onTap == null) return collage;
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      child: GestureDetector(onTap: onTap, child: collage),
    );
  }
}
