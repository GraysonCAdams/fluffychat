// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Starting a group on one of the user's networks from New Chat or the
/// share page: the people picked so far, the network the first of them
/// fixed, and the bridge calls behind it.
library;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/start_chat_sheet.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/new_chat/bridge_directory.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
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
}

/// The people picked for a new group. The first person fixes the
/// [network]; after that only people that network reaches can be added.
/// Removing everyone clears the network.
class GroupDraft extends ChangeNotifier {
  GroupNetwork? _network;
  final List<GroupMember> _members = [];

  /// People the network answered it cannot reach, by [groupMemberKey].
  final Set<String> _unreachable = {};

  GroupNetwork? get network => _network;
  List<GroupMember> get members => List.unmodifiable(_members);
  bool get isEmpty => _members.isEmpty;

  /// Whether enough people are picked for a group: two besides the user.
  bool get isGroup => _members.length >= 2;

  bool contains(NewChatPerson person) =>
      _members.any((member) => member.key == groupMemberKey(person));

  /// Why [person] cannot be added, or null when they can. Someone the
  /// network has not been asked about yet can be added; the network is
  /// asked on the pick.
  GroupBlock? blockOf(NewChatPerson person) {
    if (person.group) return GroupBlock.notAPerson;
    final network = _network;
    if (network == null || contains(person)) return null;
    if (_unreachable.contains(groupMemberKey(person))) {
      return GroupBlock.notOnNetwork;
    }
    if (person.bridgeUsers.containsKey(network.bridge.name)) return null;
    if (identifierForBridge(person, network.bridge) == null) {
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
    assert(_network != null);
    if (_members.any((known) => known.key == member.key)) return;
    _members.add(member);
    notifyListeners();
  }

  void remove(String key) {
    _members.removeWhere((member) => member.key == key);
    if (_members.isEmpty) {
      _network = null;
      _unreachable.clear();
    }
    notifyListeners();
  }

  void markUnreachable(NewChatPerson person) {
    _unreachable.add(groupMemberKey(person));
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

/// How New Chat and the share page reach the bridges: reading the people
/// sources, picking a network for a person, and starting groups. Widget
/// tests replace it with a fake.
class NewChatDelivery {
  const NewChatDelivery();

  /// Starts reading the bridges' contact lists and the phone's contacts
  /// into [sources], for the search.
  Future<void> loadSources(Client client, NewChatSources sources) =>
      sources.load(client);

  /// The network to start a chat with [person] on, from New Chat's network
  /// picker; null when the user closed it.
  Future<StartChatChoice?> pickNetwork(
    BuildContext context,
    Client client,
    NewChatPerson person,
  ) => pickStartChatNetwork(context, client, person);

  /// The network for a group whose first member is [person]: the picker
  /// lists only the bridges that create groups, iMessage first, and picks
  /// by itself when one network reaches the person. Null when the user
  /// closed it or no network creates groups.
  Future<(GroupNetwork, BridgeUser)?> pickGroupNetwork(
    BuildContext context,
    Client client,
    NewChatPerson person,
  ) async {
    final directory = BridgeDirectory.forClient(client);
    if (directory == null) return null;
    final bridges = await directory.bridges();
    final types = <String, BridgeGroupType>{};
    await Future.wait(
      bridges.map((bridge) async {
        final type = preferredGroupType(await directory.groupTypes(bridge));
        if (type != null) types[bridge.name] = type;
      }),
    );
    if (!context.mounted) return null;
    final choice = await pickStartChatNetwork(
      context,
      client,
      person,
      bridges: [
        for (final bridge in bridges)
          if (types.containsKey(bridge.name)) bridge,
      ],
      group: true,
    );
    if (choice == null) return null;
    return (
      GroupNetwork(choice.bridge, types[choice.bridge.name]!),
      choice.resolved,
    );
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
/// on [network].
String groupBlockReason(L10n l10n, GroupBlock block, GroupNetwork? network) =>
    switch (block) {
      GroupBlock.notAPerson => l10n.groupChatNotAPerson,
      GroupBlock.notOnNetwork => l10n.notOnNetwork(
        network?.bridge.displayName ?? '',
      ),
    };

/// Adds [person] to [draft], or removes them when they are in it. The
/// first person goes through the network picker, which fixes the group's
/// network; later people are checked against that network, and one it
/// cannot reach is marked so and named in a snackbar. True when [person]
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
      SnackBar(content: Text(groupBlockReason(l10n, block, draft.network))),
    );
    return false;
  }
  final network = draft.network;
  if (network == null) {
    final picked = await delivery.pickGroupNetwork(context, client, person);
    if (picked == null || draft.network != null) return false;
    final (network, user) = picked;
    draft.start(network, GroupMember(person, user));
    return true;
  }
  var user = person.bridgeUsers[network.bridge.name];
  if (user == null) {
    final identifier = identifierForBridge(person, network.bridge)!;
    final result = await showFutureLoadingDialog<BridgeUser?>(
      context: context,
      future: () =>
          delivery.resolveOnNetwork(client, network.bridge, identifier),
    );
    if (result.isError) return false;
    user = result.asValue!.value;
  }
  if (draft.network != network) return false;
  if (user == null) {
    draft.markUnreachable(person);
    messenger.showSnackBar(
      SnackBar(
        content: Text(
          '${person.name}: ${l10n.notOnNetwork(network.bridge.displayName)}',
        ),
      ),
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
