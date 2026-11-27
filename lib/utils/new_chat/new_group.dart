// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Starting a group on one of the user's networks from New Chat, and
/// adding people to a bridged group: the people picked so far, the network
/// they are on (the one picked for the new group, or the group's own), and
/// the bridge calls behind it.
library;

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/trust_user_key_dialog.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/merged_contacts/merged_timeline.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/new_chat/add_people.dart' as add_people;
import 'package:fluffychat/utils/new_chat/bridge_directory.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/send_attachments.dart';
import 'package:fluffychat/utils/share_items.dart';
import 'package:fluffychat/utils/video_poster.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Someone picked for a new group, as the group's network knows them.
class GroupMember {
  final NewChatPerson person;

  /// The person on the group's network; [BridgeUser.id] is what
  /// `create_group` is sent.
  final BridgeUser user;

  const GroupMember(this.person, this.user);

  String get key => groupMemberKey(person);
}

/// Identifies [person] among the picked members across searches: their
/// phone number, else email, else Matrix ID, else name.
String groupMemberKey(NewChatPerson person) =>
    person.phone ??
    person.email ??
    (person.userIds.isEmpty ? null : person.userIds.first) ??
    person.name;

/// The network a new group starts on: the bridge and the kind of group it
/// creates there.
class GroupNetwork {
  final BridgeInfo bridge;
  final BridgeGroupType type;

  const GroupNetwork(this.bridge, this.type);
}

/// Why a person cannot join the group being picked.
enum GroupBlock {
  /// A group chat, not a person.
  notAPerson,

  /// The group's network cannot reach them.
  notOnNetwork,

  /// They are in the group already.
  member,
}

/// The people picked for a group. A new group's [network] is set with its
/// first person in [start], and removing everyone clears it;
/// [GroupDraft.forRoom] picks people for a group that exists, on its own
/// bridge. Either way only people the [bridge] reaches can be added.
class GroupDraft extends ChangeNotifier {
  GroupNetwork? _network;
  final List<GroupMember> _members = [];

  /// The existing group's bridge, which never changes.
  final BridgeInfo? _roomBridge;

  /// The Matrix IDs of the existing group's members.
  final Set<String> _memberIds;

  /// People the network answered it cannot reach, by [groupMemberKey].
  final Set<String> _unreachable = {};

  /// What the [bridge] can look people up by; null until known, when a
  /// number or email is tried on any bridge.
  BridgeLookups? lookups;

  GroupDraft() : _roomBridge = null, _memberIds = {};

  /// People to add to a group on [bridge] whose members are [memberIds].
  GroupDraft.forRoom(BridgeInfo bridge, {Iterable<String> memberIds = const []})
    : _roomBridge = bridge,
      _memberIds = {...memberIds};

  /// The new group's network, once its first person is picked. Null for
  /// [GroupDraft.forRoom].
  GroupNetwork? get network => _network;

  /// The bridge the people are added on: the existing group's, else the
  /// new group's [network].
  BridgeInfo? get bridge => _roomBridge ?? _network?.bridge;
  List<GroupMember> get members => List.unmodifiable(_members);
  bool get isEmpty => _members.isEmpty;

  /// Whether enough people are picked for a group: two besides the user.
  bool get isGroup => _members.length >= 2;

  bool contains(NewChatPerson person) =>
      _members.any((member) => member.key == groupMemberKey(person));

  /// Whether [userId] is a member of the existing group.
  bool isMemberId(String userId) => _memberIds.contains(userId);

  /// Whether [person] is known to be in the existing group: one of their
  /// Matrix IDs, or the ghost the group's bridge lists them as, is a
  /// member. Someone known only by a number or email is found out on the
  /// pick, when the bridge names their ghost.
  bool isMember(NewChatPerson person) {
    if (_memberIds.isEmpty) return false;
    if (person.userIds.any(_memberIds.contains)) return true;
    final bridge = this.bridge;
    final ghost = bridge == null ? null : person.bridgeUsers[bridge.name]?.mxid;
    return ghost != null && _memberIds.contains(ghost);
  }

  /// Why [person] cannot be added, or null when they can. Someone the
  /// network has not been asked about yet can be added; the network is
  /// asked on the pick.
  GroupBlock? blockOf(NewChatPerson person) {
    if (person.group) return GroupBlock.notAPerson;
    final bridge = this.bridge;
    if (bridge == null || contains(person)) return null;
    if (isMember(person)) return GroupBlock.member;
    if (_unreachable.contains(groupMemberKey(person))) {
      return GroupBlock.notOnNetwork;
    }
    if (person.bridgeUsers.containsKey(bridge.name)) return null;
    if (identifierForBridge(person, bridge, lookups: lookups) == null) {
      return GroupBlock.notOnNetwork;
    }
    return null;
  }

  /// Adds the first person and fixes the group's [network].
  void start(GroupNetwork network, GroupMember first) {
    _network = network;
    _unreachable.clear();
    _members
      ..clear()
      ..add(first);
    notifyListeners();
  }

  void add(GroupMember member) {
    assert(bridge != null);
    if (_members.any((known) => known.key == member.key)) return;
    _members.add(member);
    notifyListeners();
  }

  void remove(String key) {
    _members.removeWhere((member) => member.key == key);
    if (_members.isEmpty && _roomBridge == null) {
      _network = null;
      _unreachable.clear();
    }
    notifyListeners();
  }

  void markUnreachable(NewChatPerson person) {
    _unreachable.add(groupMemberKey(person));
    notifyListeners();
  }

  /// Counts [userId] as a member of the existing group, such as someone
  /// just invited.
  void markMember(String userId) {
    _memberIds.add(userId);
    notifyListeners();
  }

  void clear() {
    _members.clear();
    _network = null;
    _unreachable.clear();
    notifyListeners();
  }
}

/// The kind of group to create on a bridge that offers [types]: `group`
/// when it is one of them, else the first. Null when it offers none.
BridgeGroupType? preferredGroupType(List<BridgeGroupType> types) =>
    types.where((type) => type.id == 'group').firstOrNull ?? types.firstOrNull;

/// How New Chat and Add people reach the bridges and the chats: reading
/// the people sources, asking the networks whether they reach a person and
/// which groups they create, starting chats and groups, sending the first
/// message or a share, reading a staged video's first frame and an
/// existing chat's timeline, and finding and inviting people for a bridged
/// group. Widget tests replace it with a fake.
class NewChatDelivery {
  const NewChatDelivery();

  /// Starts reading the bridges' contact lists and the phone's contacts
  /// into [sources], for the search.
  Future<void> loadSources(Client client, NewChatSources sources) =>
      sources.load(client);

  /// Whether the user is logged in to any bridge.
  Future<bool> hasBridges(Client client) async {
    final directory = BridgeDirectory.forClient(client);
    if (directory == null) return false;
    return (await directory.bridges()).isNotEmpty;
  }

  /// What [bridge] can look a person up by: what its capabilities declare,
  /// else what its network is known to take.
  Future<BridgeLookups> lookupsOn(Client client, BridgeInfo bridge) async {
    final directory = BridgeDirectory.forClient(client);
    if (directory == null) return BridgeLookups.knownFor(bridge);
    return directory.lookups(bridge);
  }

  /// The kind of group [bridge] creates, or null when it creates none.
  Future<BridgeGroupType?> groupTypeOn(Client client, BridgeInfo bridge) async {
    final directory = BridgeDirectory.forClient(client);
    if (directory == null) return null;
    return preferredGroupType(await directory.groupTypes(bridge));
  }

  /// Whether [bridge] reaches [identifier]; null when it does not.
  Future<BridgeUser?> resolveOnNetwork(
    Client client,
    BridgeInfo bridge,
    String identifier,
  ) {
    final directory = BridgeDirectory.forClient(client);
    if (directory == null) throw StateError('Not logged in');
    return directory.api.resolveIdentifier(bridge, identifier);
  }

  /// The user's bridge that [room] is a portal of; null when it is not one
  /// of theirs or the bridges cannot be reached.
  Future<BridgeInfo?> bridgeOfRoom(Client client, Room room) async {
    final directory = BridgeDirectory.forClient(client);
    if (directory == null) return null;
    return add_people.bridgeOfRoom(await directory.bridges(), room);
  }

  /// The first frame of a staged video, for its tile in the composer.
  Future<Uint8List?> videoPoster(XFile file) => VideoPoster.forFile(file.path);

  /// Invites [userId], a bridge ghost, to [room].
  Future<void> invite(Room room, String userId) => room.invite(userId);

  /// The room of a direct chat on the network the user picked in [choice],
  /// started through its bridge when there is none yet.
  Future<String> startChat(Client client, StartChatChoice choice) {
    final directory = BridgeDirectory.forClient(client);
    if (directory == null) throw StateError('Not logged in');
    return startBridgeChat(client, directory.api, choice);
  }

  /// The room of a Matrix direct chat with [userId], created when there is
  /// none yet.
  Future<String> startMatrixChat(Client client, String userId) =>
      client.startDirectChat(userId);

  /// Sends [text] to [room] as the chat's composer does, with [effect] when
  /// one was picked.
  Future<void> sendText(Room room, String text, {MessageEffect? effect}) =>
      effect == null
      ? room.sendTextEvent(text)
      : room.sendTextEventWithEffect(text, effect);

  /// Sends what the compose screen staged to [room] as the chat's composer
  /// does: the files through [sendAttachments], with the text as their
  /// caption when there are files, then the forwarded messages, then the
  /// text when there are no files. The message goes with [effect] when one
  /// was picked. Throws
  /// when anything was not sent, or when the user turned down sending to
  /// the room's unverified devices.
  Future<void> sendShare(
    BuildContext context,
    Room room,
    SharePayload payload, {
    MessageEffect? effect,
  }) async {
    final proceed = await showTrustUserInRoomDialog(context, room);
    if (!proceed || !context.mounted) {
      throw StateError('Sending to ${room.id} was cancelled');
    }
    Object? failure;
    final captioned = payload.files.isNotEmpty;
    await sendAttachments(
      room: room,
      files: payload.files,
      caption: captioned ? payload.text : null,
      effect: effect,
      scaffoldMessenger: ScaffoldMessenger.of(context),
      l10n: L10n.of(context),
      onError: (error, _) => failure ??= error,
    );
    if (payload.contents.isNotEmpty || payload.text.trim().isNotEmpty) {
      if (!room.otherPartyCanReceiveMessages) {
        throw OtherPartyCanNotReceiveMessages();
      }
    }
    for (final content in payload.contents) {
      await room.sendEvent(content.copy());
    }
    if (!captioned && payload.text.trim().isNotEmpty) {
      await sendText(room, payload.text, effect: effect);
    }
    if (failure case final error?) throw error;
  }

  /// The timeline of [chat], read-only on the compose screen: every room of
  /// a merged contact as one, else the chat's room. [onUpdate] fires when
  /// it changes.
  Future<Timeline> openTimeline(
    ExistingChat chat, {
    void Function()? onUpdate,
  }) {
    final contact = chat.contact;
    return contact == null
        ? chat.room.getTimeline(onUpdate: onUpdate)
        : MergedTimeline.open(contact.rooms, onUpdate: onUpdate);
  }

  /// Creates the group on [network] with [members], named [name], and
  /// waits until its room is on [client].
  Future<CreatedGroup> createGroup(
    Client client,
    GroupNetwork network,
    List<GroupMember> members,
    String? name,
  ) async {
    final directory = BridgeDirectory.forClient(client);
    if (directory == null) throw StateError('Not logged in');
    final created = await directory.api.createGroup(
      network.bridge,
      network.type,
      participants: [for (final member in members) member.user.id],
      name: name,
    );
    await awaitBridgedRoom(client, created.roomId);
    return created;
  }
}

/// The reason [block] shows under a person who cannot be added to a group
/// on [bridge].
String groupBlockReason(L10n l10n, GroupBlock block, BridgeInfo? bridge) =>
    switch (block) {
      GroupBlock.notAPerson => l10n.groupChatNotAPerson,
      GroupBlock.notOnNetwork => l10n.notOnNetwork(bridge?.displayName ?? ''),
      GroupBlock.member => l10n.alreadyInThisGroup,
    };

/// Adds [person] to [draft], or removes them when they are in it. They are
/// checked against the draft's bridge, which must be set: one it cannot
/// reach is marked so and named in a snackbar, one it fails to answer about
/// is named with the reason and can be asked about again, and one it names
/// as a member of the existing group is marked a member. True when [person]
/// was added.
Future<bool> toggleGroupMember(
  BuildContext context,
  Client client,
  NewChatDelivery delivery,
  GroupDraft draft,
  NewChatPerson person,
) async {
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  if (draft.contains(person)) {
    draft.remove(groupMemberKey(person));
    return false;
  }
  final block = draft.blockOf(person);
  if (block != null) {
    messenger.showSnackBar(
      SnackBar(content: Text(groupBlockReason(l10n, block, draft.bridge))),
    );
    return false;
  }
  final bridge = draft.bridge;
  if (bridge == null) return false;
  var user = person.bridgeUsers[bridge.name];
  if (user == null) {
    final identifier = identifierForBridge(
      person,
      bridge,
      lookups: draft.lookups,
    )!;
    while (true) {
      // The error is caught here rather than by the loading dialog, which
      // would show it without saying who or where.
      final result =
          await showFutureLoadingDialog<({BridgeUser? user, Object? error})>(
            context: context,
            future: () async {
              try {
                final user = await delivery.resolveOnNetwork(
                  client,
                  bridge,
                  identifier,
                );
                return (user: user, error: null);
              } catch (e, s) {
                Logs().w(
                  '${bridge.name} could not resolve ${person.name}',
                  e,
                  s,
                );
                return (user: null, error: e);
              }
            },
          );
      if (!context.mounted || result.isError) return false;
      final answer = result.asValue!.value;
      final error = answer.error;
      // A bridge that cannot take this kind of identifier does not reach
      // the person, like one that answered "not found".
      if (error == null || bridgeRejectsIdentifier(error)) {
        user = answer.user;
        break;
      }
      // A network that failed to answer has not said the person is not on
      // it: name who, where and why, and let the user ask again.
      final retry = await showOkCancelAlertDialog(
        context: context,
        title: l10n.networkCheckFailedTitle,
        message: l10n.personNetworkCheckFailed(
          person.name,
          bridge.displayName,
          bridgeErrorReason(error),
        ),
        okLabel: l10n.tryAgain,
        cancelLabel: l10n.cancel,
      );
      if (retry != OkCancelResult.ok || !context.mounted) return false;
    }
  }
  if (draft.bridge != bridge) return false;
  if (user == null) {
    draft.markUnreachable(person);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${person.name}: ${l10n.notOnNetwork(bridge.displayName)}',
        ),
      ),
    );
    return false;
  }
  final ghost = user.mxid;
  if (ghost != null && draft.isMemberId(ghost)) {
    // The row reads as a member from now on.
    person.userIds.add(ghost);
    draft.markMember(ghost);
    messenger.showSnackBar(
      SnackBar(content: Text('${person.name}: ${l10n.alreadyInThisGroup}')),
    );
    return false;
  }
  draft.add(GroupMember(person, user));
  return true;
}

/// Names in a snackbar the [members] that [created] says the network could
/// not add. Shows nothing when everyone was added.
void showGroupMembersNotAdded(
  BuildContext context,
  List<GroupMember> members,
  CreatedGroup created,
) {
  if (created.failedParticipants.isEmpty) return;
  final names = [
    for (final id in created.failedParticipants.keys)
      members
              .where((member) => member.user.id == id)
              .firstOrNull
              ?.person
              .name ??
          id,
  ];
  ScaffoldMessenger.of(context).showSnackBar(
    SnackBar(
      content: Text(L10n.of(context).groupMembersNotAdded(names.join(', '))),
    ),
  );
}
