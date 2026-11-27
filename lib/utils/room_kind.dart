// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/utils/matrix_features.dart';
import 'package:matrix/matrix.dart';

/// Whether a chat is one-to-one or a group, and who in it is a person,
/// decided the same way on every screen.
///
/// A bridge keeps its bot joined in every chat it bridges and lists it as a
/// functional member (`io.element.functional_members`). Such service
/// members are not people in the conversation: they never name a chat,
/// count as a member, type or read.
extension RoomKind on Room {
  /// The state event listing the room's service members, by MSC4171.
  static const String functionalMembersType = 'io.element.functional_members';

  /// The bridge of this room: from state in memory, else from the stored
  /// state scan when [MatrixFeatures] has started for the client.
  RoomBridge? get _bridge =>
      RoomBridge.fromState(this) ??
      MatrixFeatures.startedFor(client)?.bridgeOf(this);

  /// The users that are not people in this room: the
  /// [functionalMembersType] event's `service_members`, and the bridge bot
  /// the room's bridge state names.
  Set<String> get serviceMembers {
    final listed = getState(
      functionalMembersType,
    )?.content.tryGetList<String>('service_members');
    return {...?listed, ?_bridge?.bot};
  }

  /// The other members known in memory: the room's heroes and the joined
  /// members loaded, without the user, the [serviceMembers] and anyone whose
  /// member event says they left or were banned.
  Set<String> get _otherPeople {
    final skip = {client.userID, ...serviceMembers};
    final ids = {
      ...?summary.mHeroes,
      for (final user in getParticipants(const [Membership.join])) user.id,
    }..removeWhere(skip.contains);
    ids.removeWhere((id) {
      final membership = getState(
        EventTypes.RoomMember,
        id,
      )?.content.tryGet<String>('membership');
      return membership == 'leave' || membership == 'ban';
    });
    return ids;
  }

  /// How many people besides the user are in this room: the joined count
  /// less the user and the [serviceMembers] (joined unless their member
  /// event in memory says otherwise). Without a joined count, the people
  /// known in memory.
  int get otherPeopleCount {
    final people = _otherPeople.length;
    final joined = summary.mJoinedMemberCount;
    if (joined == null) return people;
    final service = serviceMembers.where((id) {
      final membership = getState(
        EventTypes.RoomMember,
        id,
      )?.content.tryGet<String>('membership');
      return (membership ?? 'join') == 'join';
    }).length;
    return max(0, joined - 1 - service);
  }

  /// What the room's bridge says it is: `dm`, `group`, or null when the
  /// bridge state does not say (or the room is not bridged).
  String? get bridgeRoomType => _bridge?.roomType;

  /// Whether this is a one-to-one chat. A bridge that says what the room is
  /// (`com.beeper.room_type` in its bridge state, `dm` or `group`) decides;
  /// otherwise `m.direct` does. Members are not counted: a bridge keeps its
  /// bot joined in every chat, and a lazily loaded member list is often
  /// incomplete.
  bool get isOneToOne {
    if (isSpace) return false;
    return switch (bridgeRoomType) {
      'dm' => true,
      'group' => false,
      _ => isDirectChat,
    };
  }

  /// Whether this chat is certainly one-to-one, as merge suggestions need:
  /// the bridge says `dm`, or, when it says nothing, `m.direct` lists it and
  /// exactly one other person is in it besides the [serviceMembers]. A group
  /// that `m.direct` lists by mistake is not.
  bool get isMergeableOneToOne {
    if (isSpace) return false;
    return switch (bridgeRoomType) {
      'dm' => true,
      'group' => false,
      _ => isDirectChat && otherPeopleCount == 1,
    };
  }

  /// The other person of a one-to-one chat: the user `m.direct` lists it
  /// under, else (for a chat only its bridge calls `dm`) the one person in
  /// it. Null for a group, or when that person is not known.
  String? get oneToOnePartnerId {
    if (!isOneToOne) return null;
    final listed = directChatMatrixID;
    if (listed != null) return listed;
    final people = _otherPeople;
    return people.length == 1 ? people.single : null;
  }

  /// Whether this is a group chat: neither a one-to-one chat nor a space.
  bool get isGroupChat => !isSpace && !isOneToOne;

  /// Whether [user] is a person in this chat for typing and read receipts:
  /// not the user and not one of the [serviceMembers].
  bool countsAsPerson(String user) =>
      user != client.userID && !serviceMembers.contains(user);

  /// The chat's name as the app shows it: [Room.getLocalizedDisplayname],
  /// except that a chat without a name of its own is not named after its
  /// [serviceMembers], and a one-to-one chat is named after the other
  /// person alone, without "Group with".
  String chatDisplayname([
    MatrixLocalizations i18n = const MatrixDefaultLocalizations(),
  ]) {
    final sdkName = getLocalizedDisplayname(i18n);
    if (name.isNotEmpty || canonicalAlias.isNotEmpty) return sdkName;
    final heroes = summary.mHeroes ?? const <String>[];
    final service = serviceMembers;
    final oneToOne = isOneToOne;
    if (!heroes.any(service.contains) && (isDirectChat || !oneToOne)) {
      return sdkName;
    }
    final me = client.userID;
    final people = [
      for (final id in heroes)
        if (id.isNotEmpty && id != me && !service.contains(id)) id,
    ];
    if (people.isEmpty) return sdkName;
    final result = people
        .map(
          (id) =>
              unsafeGetUserFromMemoryOrFallback(id).calcDisplayname(i18n: i18n),
        )
        .join(', ');
    if (isAbandonedDMRoom) return i18n.wasDirectChatDisplayName(result);
    return oneToOne ? result : i18n.groupWith(result);
  }

  /// The chat's picture as the app shows it: its own, else for a
  /// one-to-one chat the other person's. The SDK only finds the other
  /// person through `m.direct`, which a bridged chat can be missing from.
  Uri? get chatAvatar {
    final own = avatar;
    if (own != null || isDirectChat) return own;
    final partner = oneToOnePartnerId;
    return partner == null
        ? null
        : unsafeGetUserFromMemoryOrFallback(partner).avatarUrl;
  }
}
