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
/// Members come from memory first, then from the database. A room with
/// fewer than two of them there loads its member list once (see
/// [loadMembers]): bridges name their groups, and Synapse sends no heroes
/// for a named room, while a room loaded from the database keeps no members
/// in memory, so the newest sender is often the only one known.
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

  /// The rooms of each client whose member list was loaded this session or
  /// is loading, by room ID.
  static final _membersLoaded = Expando<Map<String, Future<void>>>();

  /// The most joined members a room may have for its list to be loaded:
  /// enough for any group on a phone network, few enough that a large
  /// public room without a picture never downloads its member list.
  static const int maxLoadedMembers = 50;

  /// Loads the joined members of [room] into memory, once per session: from
  /// the database, else from the server, keeping the server's list in the
  /// database for the next start. Completes at once for a room that was
  /// loaded, or whose member count is unknown or over [maxLoadedMembers].
  static Future<void> loadMembers(Room room) {
    final rooms = _membersLoaded[room.client] ??= {};
    final loaded = rooms[room.id];
    if (loaded != null) return loaded;
    final count = room.summary.mJoinedMemberCount;
    if (count == null || count > maxLoadedMembers) return Future.value();
    return rooms[room.id] = room
        .requestParticipants(const [Membership.join], true, true)
        .then<void>((_) {})
        .catchError((Object e, StackTrace s) {
          // Tried again by the next avatar built for the room.
          rooms.remove(room.id);
          Logs().w('Unable to load the members of ${room.id}', e, s);
        });
  }

  /// The members the collage of [room] shows, at most [max] (three in the
  /// app): the sender of the newest message first, then the room's heroes,
  /// then whoever else is in memory. The user and the chat's bridge bot are
  /// left out.
  static List<String> memberIds(Room room, {int max = 3}) {
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
    if (ids.length < max) {
      for (final user in room.getParticipants(const [Membership.join])) {
        add(user.id);
        if (ids.length >= max) break;
      }
    }
    return ids.take(max).toList();
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

  /// The room whose member list this avatar waits for.
  String? _loadingRoomId;

  void _loadMembers(Room room) {
    if (_loadingRoomId == room.id) return;
    _loadingRoomId = room.id;
    GroupAvatar.loadMembers(room).then((_) {
      if (mounted && widget.room.id == room.id) setState(() {});
    });
  }

  @override
  Widget build(BuildContext context) {
    final room = widget.room;
    final ids = GroupAvatar.memberIds(room);
    if (ids.length < 2) _loadMembers(room);
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
