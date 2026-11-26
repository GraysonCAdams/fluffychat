// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:cross_file/cross_file.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_picker.dart'
    as effects;
import 'package:fluffychat/pages/chat_list/merged_contact_actions.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/android_direct_share.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/new_chat/compose.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/share_items.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The compose screen behind New chat and Create group, as in iMessage: a
/// To field of people as chips, the chat the user already has with exactly
/// those people (or an empty history), and a composer for the first
/// message. Every network is asked whether it reaches each person, and
/// when the first person is on two or more, the header's network switcher
/// picks the one the conversation is on: at first the network of the most
/// recent chat with them. One person makes a direct chat there; two or
/// more make a group there, and the networks someone else is not on are
/// faded. Sending the first message starts the chat or creates the group
/// when there is none, then opens it.
///
/// Something shared into Seam or forwarded opens here too, as [share]: its
/// files and forwarded messages are staged in the composer and its text is
/// in the text field, and until a name is typed the user's recent
/// conversations are offered as recipients.
class NewPrivateChat extends StatefulWidget {
  final String? deeplink;
  final NewChatDelivery delivery;

  /// What is being shared or forwarded, staged in the composer.
  final SharedDraft? share;

  /// Opened from Create group: an account with no bridges goes on to the
  /// Matrix group page, since every group made here is on a network.
  final bool startGroup;

  const NewPrivateChat({
    super.key,
    required this.deeplink,
    this.delivery = const NewChatDelivery(),
    this.startGroup = false,
    this.share,
  });

  @override
  NewPrivateChatController createState() => NewPrivateChatController();
}

class NewPrivateChatController extends State<NewPrivateChat> {
  /// The text being typed into the To field, which searches for people.
  final TextEditingController controller = TextEditingController();

  /// The To field's focus. Backspace in it while it is empty removes the
  /// last chip.
  late final FocusNode textFieldFocus = FocusNode(onKeyEvent: _onToKey);

  /// The first message.
  late final TextEditingController messageController = TextEditingController(
    text: widget.share?.text,
  );

  /// Shared files staged in the composer, sent ahead of the text.
  late final List<XFile> stagedFiles = [...?widget.share?.files];

  /// Forwarded messages staged in the composer, sent after the files.
  late final List<Map<String, Object?>> stagedContents = [
    ...?widget.share?.contents,
  ];

  /// Whether the screen holds a share that was not sent yet.
  bool get sharing => widget.share != null;

  /// The composer's focus. Enter sends when the user's setting says so,
  /// as in a chat.
  late final FocusNode messageFocus = FocusNode(onKeyEvent: _onMessageKey);

  /// The new group's name, offered for two or more people on a network
  /// that takes one.
  final TextEditingController groupName = TextEditingController();

  Future<List<Profile>>? searchResponse;

  Timer? _searchCoolDown;

  static const Duration _coolDown = Duration(milliseconds: 500);

  /// The bridges' contact lists and the phone's address book.
  late final NewChatSources sources = NewChatSources(onChanged: _rebuildPeople);

  /// The user's bridges, once their `whoami` answered.
  List<BridgeInfo> get bridges => sources.bridges;

  /// The people in the To field, in the order they were added.
  final List<NewChatPerson<ExistingChat>> recipients = [];

  /// The group the [recipients] make once there are two of them: the
  /// network picked for it and everyone as that network knows them. Empty
  /// while there is one person or none.
  late final GroupDraft group = GroupDraft()
    ..addListener(() {
      if (mounted) setState(() {});
    });

  /// The chat the user already has with exactly the [recipients], shown
  /// above the composer and where the first message goes. Null when there
  /// is none.
  ExistingChat? conversation;

  /// The room the first message goes to in [conversation].
  Room? get sendRoom => conversation?.sendRoom;

  /// What the networks answered about each person in the To field, by
  /// [groupMemberKey].
  final Map<String, PersonReach> _reach = {};

  /// The kind of group each bridge creates, by bridge name, once it
  /// answered; null for a bridge that creates none.
  final Map<String, BridgeGroupType?> _groupTypes = {};

  /// Why each bridge failed to say which groups it creates.
  final Map<String, String> _groupTypeErrors = {};

  /// The networks of the first person in the To field, which the network
  /// switcher offers when there are two or more. Empty for a group chat or
  /// nobody.
  List<ComposeNetwork> networks = const [];

  String? _selectedNetworkId;

  /// Whether the user picked the network in the switcher, which keeps it
  /// as later answers come in.
  bool _networkPicked = false;

  /// The direct chat with the first person (every network of a merged
  /// contact), which a message to one of its rooms opens.
  ExistingChat? _personChat;

  /// The network the conversation is on: the one picked in the switcher,
  /// else the most recent.
  ComposeNetwork? get selectedNetwork =>
      networks.where((network) => network.id == _selectedNetworkId).firstOrNull;

  /// Whether the header shows the network switcher.
  bool get showNetworkSwitcher => networks.length >= 2;

  /// What the networks answered about the first person in the To field.
  PersonReach? get firstReach {
    final first = recipients.firstOrNull;
    return first == null || first.group ? null : _reach[groupMemberKey(first)];
  }

  /// The networks that failed to answer about the first person and are not
  /// in the switcher, so the user sees them and can ask again.
  List<(BridgeInfo, String)> get failedNetworks {
    final reach = firstReach;
    if (reach == null) return const [];
    final shown = {for (final network in networks) ?network.bridge?.name};
    return [
      for (final bridge in orderBridgesForSwitcher(bridges))
        if (reach.errors[bridge.name] case final error?)
          if (!shown.contains(bridge.name)) (bridge, error),
    ];
  }

  /// Whether the first person was checked and no network reaches them.
  bool get unreachable {
    final first = recipients.firstOrNull;
    final reach = firstReach;
    return first != null &&
        reach != null &&
        !isMatrixOnlyPerson(first) &&
        !reach.asking &&
        bridges.isNotEmpty &&
        networks.isEmpty;
  }

  /// Why [network] cannot take everyone in the To field, or null when it
  /// can. One person can be reached on any of their networks; a group
  /// needs a network that creates groups and reaches everyone.
  String? networkBlockOf(ComposeNetwork network) {
    if (recipients.length < 2) return null;
    final l10n = L10n.of(context);
    final bridge = network.bridge;
    if (bridge == null) return l10n.networkMakesNoGroups(network.name);
    if (_groupTypes.containsKey(bridge.name) &&
        _groupTypes[bridge.name] == null) {
      return l10n.networkMakesNoGroups(network.name);
    }
    for (final person in recipients) {
      final reach = _reach[groupMemberKey(person)];
      final error = reach?.errors[bridge.name];
      if (error != null) {
        return l10n.personNetworkCheckFailed(
          person.name,
          bridge.displayName,
          error,
        );
      }
      if (reach == null || !reach.users.containsKey(bridge.name)) {
        return l10n.checkingPersonOnNetwork(person.name, bridge.displayName);
      }
      if (reach.users[bridge.name] == null) {
        return '${person.name}: '
            '${groupBlockReason(l10n, GroupBlock.notOnNetwork, bridge)}';
      }
    }
    return null;
  }

  /// A network was picked in the switcher: the conversation moves to it,
  /// and a group is made there. For a merged contact it becomes the
  /// contact's default, as it does in the chat.
  void selectNetwork(String id) {
    final network = networks.where((network) => network.id == id).firstOrNull;
    if (network == null || networkBlockOf(network) != null) return;
    setState(() {
      _selectedNetworkId = id;
      _networkPicked = true;
      if (recipients.length >= 2) _regroupOn(network);
      _findConversation();
    });
    final contact = _personChat?.contact;
    final room = network.room;
    if (recipients.length == 1 && contact != null && room != null) {
      MergedContactsStore.forClient(
        Matrix.of(context).client,
      ).setSendVia(contact.id, room.id);
    }
  }

  /// A faded network was tapped: says why it cannot be picked, with a retry
  /// where a network failed to answer.
  void explainBlockedNetwork(ComposeNetwork network) {
    final reason = networkBlockOf(network);
    if (reason == null) return;
    final bridge = network.bridge;
    final failed = bridge == null
        ? const <NewChatPerson<ExistingChat>>[]
        : [
            for (final person in recipients)
              if (_reach[groupMemberKey(person)]?.errors[bridge.name] != null)
                person,
          ];
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(reason),
        action: failed.isEmpty
            ? null
            : SnackBarAction(
                label: L10n.of(context).tryAgain,
                onPressed: () => failed.forEach(_recheck),
              ),
      ),
    );
  }

  /// Asks [bridge] again about the first person after it failed to answer.
  void retryNetwork(BridgeInfo bridge) {
    final first = recipients.firstOrNull;
    if (first != null) _recheck(first, bridge: bridge.name);
  }

  /// Forgets the failed answers about [person], of [bridge] or of every
  /// network, and asks again.
  void _recheck(NewChatPerson<ExistingChat> person, {String? bridge}) {
    final reach = _reach[groupMemberKey(person)];
    if (reach == null) return;
    setState(() {
      if (bridge == null) {
        reach.errors.clear();
      } else {
        reach.errors.remove(bridge);
      }
      _check(person);
    });
  }

  /// Asks each network that has not answered yet whether it reaches
  /// [person]: a bridge that lists them answers without being asked, and
  /// one with nothing to look them up by does not reach them.
  void _check(NewChatPerson<ExistingChat> person) {
    if (person.group) return;
    final client = Matrix.of(context).client;
    final reach = _reach.putIfAbsent(groupMemberKey(person), PersonReach.new);
    final chat = existingDirectChatOf(client, person);
    for (final bridge in bridges) {
      if (reach.handled(bridge.name)) continue;
      final identifier =
          identifierForBridge(person, bridge) ??
          ghostOnBridge(bridges, chat, bridge);
      if (identifier != null) reach.identifiers[bridge.name] = identifier;
      final known = person.bridgeUsers[bridge.name];
      if (known != null || identifier == null) {
        reach.users[bridge.name] = known;
        continue;
      }
      reach
          .ask(
            bridge.name,
            () => widget.delivery.resolveOnNetwork(client, bridge, identifier),
          )
          .then((_) {
            if (mounted) setState(_findConversation);
          });
    }
  }

  /// Asks each bridge that has not answered yet which groups it creates,
  /// once at a time.
  Future<void> _askGroupTypes() {
    if (bridges.every((bridge) => _groupTypes.containsKey(bridge.name))) {
      return Future.value();
    }
    return _askingGroupTypes ??= _fetchGroupTypes().whenComplete(
      () => _askingGroupTypes = null,
    );
  }

  Future<void>? _askingGroupTypes;

  Future<void> _fetchGroupTypes() async {
    final client = Matrix.of(context).client;
    final pending = [
      for (final bridge in bridges)
        if (!_groupTypes.containsKey(bridge.name)) bridge,
    ];
    await Future.wait(
      pending.map((bridge) async {
        try {
          _groupTypes[bridge.name] = await widget.delivery.groupTypeOn(
            client,
            bridge,
          );
          _groupTypeErrors.remove(bridge.name);
        } catch (e, s) {
          Logs().w('${bridge.name} did not say which groups it creates', e, s);
          _groupTypeErrors[bridge.name] = bridgeErrorReason(e);
        }
      }),
    );
    if (mounted) setState(() {});
  }

  /// Makes the group again on [network], with everyone as its bridge
  /// knows them. Only a network [networkBlockOf] lets through is passed.
  void _regroupOn(ComposeNetwork network) {
    final bridge = network.bridge!;
    final type = _groupTypes[bridge.name]!;
    group.start(
      GroupNetwork(bridge, type),
      GroupMember(recipients.first, network.user!),
    );
    for (final person in recipients.skip(1)) {
      group.add(
        GroupMember(
          person,
          _reach[groupMemberKey(person)]!.users[bridge.name]!,
        ),
      );
    }
  }

  /// Takes the staged [file] out of the composer.
  void removeStagedFile(XFile file) => setState(() => stagedFiles.remove(file));

  /// Takes the staged forwarded messages out of the composer.
  void removeStagedContents() => setState(stagedContents.clear);

  /// The user's most recent chats, offered as recipients for a share while
  /// nothing is typed into the To field. Each is joined, as in the search,
  /// by the bridge contacts and phone contacts that are the same person, so
  /// their number reaches the networks the chat is not on.
  List<NewChatPerson<ExistingChat>> get recentPeople {
    final client = Matrix.of(context).client;
    final locals = MatrixLocals(L10n.of(context));
    final chats = existingChatsOf(
      client,
      client.rooms
          .where(
            (room) =>
                room.membership == Membership.join &&
                !room.isSpace &&
                room.canSendDefaultMessages,
          )
          .toList(),
      (_) => true,
    ).take(recentCount);
    return [
      for (final chat in chats)
        // A search by the chat's name brings the contacts that join its row.
        sources
            .people(
              chat.contact?.displayName(locals) ??
                  chat.room.getLocalizedDisplayname(locals),
              [chatPersonInput(chat, locals)],
            )
            .firstWhere((person) => person.chat == chat),
    ];
  }

  /// How many recent chats [recentPeople] offers.
  static const int recentCount = 8;

  /// Whether the first message is on its way, which keeps a second tap on
  /// send from starting a second chat.
  bool sending = false;

  /// Whether to show the row that asks to read the phone's contacts.
  bool get offerPhoneContacts => sources.offerPhoneContacts;

  /// The search's results from chats, bridge contacts and the phone's
  /// contacts, one row per person. Directory results follow them.
  List<NewChatPerson<ExistingChat>> people = const [];

  /// The search [people] was built for, and its chats, for rebuilding
  /// [people] when a slower source arrives.
  String _peopleQuery = '';
  List<ChatPersonInput<ExistingChat>> _chatInputs = const [];

  @override
  void initState() {
    super.initState();

    final deeplink = widget.deeplink;
    if (deeplink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        UrlLauncher(context, deeplink).openMatrixToUrl();
      });
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _loadSources());
  }

  /// Starts reading the bridges and, when allowed, the phone's contacts.
  /// Each updates the results when it arrives.
  Future<void> _loadSources() async {
    final client = Matrix.of(context).client;
    if (widget.startGroup) {
      final hasBridges = await widget.delivery.hasBridges(client);
      if (!mounted) return;
      if (!hasBridges) {
        context.go('/rooms/newgroup');
        return;
      }
    }
    await widget.delivery.loadSources(client, sources);
  }

  /// Asks for the contacts permission from the offer row.
  Future<void> allowPhoneContacts() => sources.allowPhoneContacts();

  /// Hides the offer row for good.
  Future<void> declinePhoneContacts() => sources.declinePhoneContacts();

  List<NewChatPerson<ExistingChat>> _mergePeople() =>
      sources.people(_peopleQuery, _chatInputs);

  void _rebuildPeople() {
    if (!mounted) return;
    // The bridges' list may be what came: the people in the To field are
    // asked about on each new one, and the group lookup reads it.
    recipients.forEach(_check);
    _askGroupTypes();
    _findConversation();
    if (searchResponse == null || _peopleQuery.isEmpty) {
      setState(() {});
      return;
    }
    setState(() => people = _mergePeople());
  }

  Future<void> searchUsers([String? input]) async {
    final searchTerm = input ?? controller.text;
    if (searchTerm.isEmpty) {
      _searchCoolDown?.cancel();
      setState(() {
        searchResponse = _searchCoolDown = null;
      });
      return;
    }

    _searchCoolDown?.cancel();
    // The suggestions cover the conversation from the first letter.
    setState(() {
      _searchCoolDown = Timer(_coolDown, () {
        setState(() {
          searchResponse = _searchUser(searchTerm);
        });
      });
    });
  }

  /// The chats you already have that the search found, newest first. A
  /// merged contact is one entry, like in the chat list.
  List<ExistingChat> existingChats = const [];

  /// The Matrix IDs of [people], who are left out of the directory results.
  final Set<String> _knownUserIds = {};

  /// The chats that match [searchTerm], when chats are suggested.
  List<ExistingChat> _chatsFor(String searchTerm) =>
      AppSettings.suggestContactsFromChats.value
      ? searchExistingChats(
          Matrix.of(context).client,
          searchTerm,
          MatrixLocals(L10n.of(context)),
        )
      : const [];

  Future<List<Profile>> _searchUser(String searchTerm) async {
    _knownUserIds.clear();
    existingChats = _chatsFor(searchTerm);
    final locals = MatrixLocals(L10n.of(context));
    _peopleQuery = searchTerm;
    _chatInputs = [
      for (final chat in existingChats) chatPersonInput(chat, locals),
    ];
    people = _mergePeople();
    for (final person in people) {
      _knownUserIds.addAll(person.userIds);
    }
    final List<Profile> fromDirectory;
    try {
      fromDirectory = (await Matrix.of(
        context,
      ).client.searchUserDirectory(searchTerm)).results;
    } catch (e, s) {
      if (people.isEmpty) rethrow;
      Logs().w('User directory search failed', e, s);
      return [];
    }
    final profiles = fromDirectory
        .where((profile) => !_knownUserIds.contains(profile.userId))
        .toList();

    if (searchTerm.isValidMatrixIdStrict() &&
        searchTerm.sigil == '@' &&
        !_knownUserIds.contains(searchTerm) &&
        !profiles.any((profile) => profile.userId == searchTerm)) {
      profiles.add(Profile(userId: searchTerm));
    }

    return profiles;
  }

  void inviteAction() => FluffyShare.shareInviteLink(context);

  Future<void> openScannerAction() async {
    final l10n = L10n.of(context);
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    if (PlatformInfos.isAndroid) {
      final info = await DeviceInfoPlugin().androidInfo;
      if (!mounted) return;
      if (info.version.sdkInt < 21) {
        scaffoldMessenger.showSnackBar(
          SnackBar(content: Text(l10n.unsupportedAndroidVersionLong)),
        );
        return;
      }
    }
    if (!mounted) return;
    await showAdaptiveBottomSheet(
      context: context,
      builder: (_) => QrScannerModal(
        onScan: (link) => UrlLauncher(context, link).openMatrixToUrl(),
      ),
    );
  }

  Future<void> copyUserId() async {
    final scaffoldMessenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    await Clipboard.setData(
      ClipboardData(text: Matrix.of(context).client.userID!),
    );
    if (!mounted) return;
    scaffoldMessenger.showSnackBar(
      SnackBar(content: Text(l10n.copiedToClipboard)),
    );
  }

  /// The route of [chat]: the merged conversation for a merged contact.
  String _routeOf(ExistingChat chat) {
    final contact = chat.contact;
    return contact == null
        ? '/rooms/${chat.room.id}'
        : mergedContactRoute(contact.id);
  }

  bool isRecipient(NewChatPerson person) {
    final key = groupMemberKey(person);
    return recipients.any((recipient) => groupMemberKey(recipient) == key);
  }

  /// A suggestion was tapped: adds [person] to the To field, or takes them
  /// out when they are in it. A group chat is not a person, so with nobody
  /// in the To field it opens instead.
  Future<void> pickPerson(NewChatPerson<ExistingChat> person) async {
    if (isRecipient(person)) {
      removeRecipient(groupMemberKey(person));
      _clearSearch();
      return;
    }
    if (person.group) {
      final chat = person.chat;
      if (recipients.isEmpty && chat != null) {
        if (sharing) {
          // A share goes to the group from here, so it is the recipient.
          setState(() {
            recipients.add(person);
            _findConversation();
          });
          _clearSearch();
          return;
        }
        context.go(_routeOf(chat));
        return;
      }
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(L10n.of(context).groupChatNotAPerson)),
      );
      return;
    }
    await addRecipient(person);
  }

  /// A Matrix user from the directory, as a person for the To field.
  void pickProfile(Profile profile) {
    final person =
        NewChatPerson<ExistingChat>(
            profile.displayName ?? profile.userId.localpart ?? profile.userId,
          )
          ..avatar = profile.avatarUrl
          ..userIds.add(profile.userId);
    pickPerson(person);
  }

  /// Puts [person] in the To field, and asks every network about them. The
  /// first person goes in as they are. Anyone after makes a group on the
  /// selected network, which must reach them: they go through the bridge
  /// as in [toggleGroupMember], and someone it cannot reach stays out,
  /// with the reason in a snackbar.
  Future<void> addRecipient(NewChatPerson<ExistingChat> person) async {
    if (sending) return;
    if (recipients.isNotEmpty && !await _addToGroup(person)) return;
    setState(() {
      recipients.add(person);
      _check(person);
      _findConversation();
    });
    _clearSearch();
    textFieldFocus.requestFocus();
  }

  /// Adds [person] to the [group] on the selected network, starting it
  /// with the first person when [person] is the second. False, with the
  /// reason in a snackbar, when the network cannot take them.
  Future<bool> _addToGroup(NewChatPerson<ExistingChat> person) async {
    final client = Matrix.of(context).client;
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    void say(String text) =>
        messenger.showSnackBar(SnackBar(content: Text(text)));
    if (group.isEmpty) {
      final first = recipients.first;
      if (first.group || person.group) {
        say(l10n.groupChatNotAPerson);
        return false;
      }
      // The first person's network is needed: wait for the answers.
      final reach = _reach[groupMemberKey(first)];
      final waiting = [
        if (reach != null && reach.asking) reach.settled(),
        _askGroupTypes(),
      ];
      if (waiting.isNotEmpty) {
        await showFutureLoadingDialog(
          context: context,
          future: () => Future.wait(waiting),
        );
        if (!mounted) return false;
        setState(_findConversation);
      }
      final network = selectedNetwork;
      final bridge = network?.bridge;
      if (network == null || bridge == null) {
        say(
          network == null
              ? '${first.name}: ${l10n.noNetworkCanReach}'
              : l10n.networkMakesNoGroups(network.name),
        );
        return false;
      }
      final typeError = _groupTypeErrors[bridge.name];
      final type = _groupTypes[bridge.name];
      if (type == null) {
        say(
          typeError == null
              ? l10n.networkMakesNoGroups(network.name)
              : l10n.networkCheckFailed(typeError),
        );
        return false;
      }
      final user = network.user;
      if (user == null) {
        final error = reach?.errors[bridge.name];
        say(
          error == null
              ? '${first.name}: '
                    '${groupBlockReason(l10n, GroupBlock.notOnNetwork, bridge)}'
              : l10n.personNetworkCheckFailed(
                  first.name,
                  bridge.displayName,
                  error,
                ),
        );
        return false;
      }
      group.start(GroupNetwork(bridge, type), GroupMember(first, user));
    }
    final added = await toggleGroupMember(
      context,
      client,
      widget.delivery,
      group,
      person,
    );
    if (!mounted) return false;
    if (!added) {
      // Only the first person is in: still a direct chat.
      if (group.members.length < 2) group.clear();
      return false;
    }
    final bridge = group.bridge!;
    // The selected network just answered about them.
    _reach
            .putIfAbsent(groupMemberKey(person), PersonReach.new)
            .users[bridge.name] =
        group.members.last.user;
    return true;
  }

  /// Takes the person with [key] out of the To field. With one person
  /// left, the group goes back to being a direct chat.
  void removeRecipient(String key) {
    setState(() {
      recipients.removeWhere((person) => groupMemberKey(person) == key);
      if (recipients.length < 2) {
        group.clear();
      } else {
        group.remove(key);
      }
      if (recipients.isEmpty) _networkPicked = false;
      _findConversation();
    });
  }

  void _clearSearch() {
    controller.clear();
    searchUsers();
  }

  /// Finds the first person's [networks] and the selected one, and
  /// [conversation] for the people in the To field: one person's direct
  /// chat on the selected network, a group chat picked as the recipient,
  /// or the most recent group on the group's network whose people are
  /// exactly them.
  void _findConversation() {
    final client = Matrix.of(context).client;
    final first = recipients.firstOrNull;
    final reach = firstReach;
    if (first == null || reach == null) {
      networks = const [];
      _personChat = null;
    } else {
      _personChat = existingDirectChatOf(client, first);
      networks = composeNetworksOf(
        client,
        bridges,
        _personChat,
        reach,
        MatrixLocals(L10n.of(context)),
      );
    }
    final groupBridge = group.isGroup ? group.bridge : null;
    if (groupBridge != null) {
      // A group is on its own network, whoever is first.
      _selectedNetworkId = networks
          .where((network) => network.bridge?.name == groupBridge.name)
          .firstOrNull
          ?.id;
    } else if (!_networkPicked ||
        !networks.any((network) => network.id == _selectedNetworkId)) {
      _selectedNetworkId = defaultComposeNetwork(networks)?.id;
    }
    if (first == null) {
      conversation = null;
    } else if (first.group) {
      conversation = recipients.length == 1 ? first.chat : null;
    } else if (recipients.length == 1) {
      final room = selectedNetwork?.room;
      conversation = room == null
          ? null
          : ExistingChat(
              room: room,
              contact: null,
              networks: [?spacesByChild(client)[room.id]],
            );
    } else if (groupBridge != null) {
      final room = existingGroupOf(client, bridges, groupBridge, group.members);
      conversation = room == null
          ? null
          : ExistingChat(room: room, contact: null, networks: const []);
    } else {
      conversation = null;
    }
  }

  /// Enter in the To field: the top suggestion for the typed text becomes
  /// a chip (a typed number or email is one), else a typed Matrix ID does.
  /// With nothing typed, moves on to the composer.
  void submitSearch(String text) {
    final query = text.trim();
    if (query.isEmpty) {
      if (recipients.isNotEmpty) messageFocus.requestFocus();
      return;
    }
    final locals = MatrixLocals(L10n.of(context));
    final candidates = sources.people(query, [
      for (final chat in _chatsFor(query)) chatPersonInput(chat, locals),
    ], typedEmail: true);
    final person = candidates
        .where(
          (person) =>
              !isRecipient(person) &&
              (recipients.isEmpty || groupBlockOf(person) == null) &&
              !person.group,
        )
        .firstOrNull;
    if (person != null) {
      addRecipient(person);
      return;
    }
    if (query.isValidMatrixIdStrict() && query.sigil == '@') {
      pickProfile(Profile(userId: query));
    }
  }

  KeyEventResult _onToKey(FocusNode node, KeyEvent event) {
    if (event is! KeyDownEvent ||
        event.logicalKey != LogicalKeyboardKey.backspace ||
        controller.text.isNotEmpty ||
        recipients.isEmpty) {
      return KeyEventResult.ignored;
    }
    removeRecipient(groupMemberKey(recipients.last));
    return KeyEventResult.handled;
  }

  KeyEventResult _onMessageKey(FocusNode node, KeyEvent event) {
    if (event.logicalKey != LogicalKeyboardKey.enter ||
        HardwareKeyboard.instance.isShiftPressed ||
        !AppSettings.sendOnEnter.value) {
      return KeyEventResult.ignored;
    }
    if (event is KeyDownEvent) send();
    return KeyEventResult.handled;
  }

  /// Why [person] cannot be added to the To field, or null. Once there are
  /// people in it a group chat cannot be; once the group's network is
  /// fixed, anyone it cannot reach cannot be either.
  String? groupBlockOf(NewChatPerson person) {
    if (recipients.isEmpty || isRecipient(person)) return null;
    if (person.group || recipients.first.group) {
      return L10n.of(context).groupChatNotAPerson;
    }
    if (group.isEmpty) return null;
    final block = group.blockOf(person);
    return block == null
        ? null
        : groupBlockReason(L10n.of(context), block, group.bridge);
  }

  /// Whether the title can name the group: two or more people, no group
  /// with them yet, and a network that takes a name.
  bool get showGroupName =>
      group.isGroup &&
      conversation == null &&
      (group.network?.type.nameAllowed ?? false);

  /// Whether the send button works: someone in the To field (a whole group
  /// once there are two) and a network that reaches them, a message or
  /// something staged, and a name when the network needs one.
  bool get canSend {
    if (sending || recipients.isEmpty) return false;
    if (_payload.isEmpty) return false;
    if (recipients.length >= 2 && !group.isGroup) return false;
    if (recipients.length == 1 && _newChatChoice == null) {
      final person = recipients.single;
      if (sendRoom == null && !isMatrixOnlyPerson(person)) return false;
    }
    final type = group.network?.type;
    if (conversation == null &&
        group.isGroup &&
        (type?.nameRequired ?? false) &&
        groupName.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  /// What the composer holds: the staged files and forwarded messages and
  /// the typed text.
  SharePayload get _payload => SharePayload(
    files: stagedFiles,
    contents: stagedContents,
    text: messageController.text.trim(),
  );

  /// The network a new direct chat with the one person in the To field
  /// starts on: the selected network, once its bridge answered that it
  /// reaches them. Null when there is a chat already, or none reaches them.
  StartChatChoice? get _newChatChoice {
    final network = selectedNetwork;
    final bridge = network?.bridge;
    final user = network?.user;
    if (network == null || bridge == null || user == null) return null;
    if (network.room != null) return null;
    final identifier = firstReach?.identifiers[bridge.name];
    return identifier == null
        ? null
        : StartChatChoice(bridge, identifier, user);
  }

  /// Sends the first message and opens the chat: in the [conversation]
  /// there is; else for one person a direct chat started on the selected
  /// network (or on Matrix for a Matrix user), and for two or more the
  /// group created through the selected network's bridge, named when a name
  /// was typed. The message is sent once the
  /// room is there. A share waits until everything staged went out; one
  /// from the Android share sheet then returns to the app that shared.
  Future<void> send({MessageEffect? effect}) async {
    if (!canSend) return;
    final payload = _payload;
    final client = Matrix.of(context).client;
    final personChat = _personChat;
    // A direct chat opens as the person's whole conversation, every
    // network of a merged contact in one.
    final existing = recipients.length == 1 && !recipients.single.group
        ? personChat
        : conversation;
    final room = sendRoom;
    if (existing != null && room != null) {
      if (!sharing) {
        _sendText(room, payload.text, effect);
        context.go(_routeOf(existing));
        return;
      }
      setState(() => sending = true);
      try {
        await widget.delivery.sendShare(context, room, payload, effect: effect);
      } catch (e, s) {
        Logs().w('Unable to send the share', e, s);
        if (mounted) {
          setState(() => sending = false);
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
        }
        return;
      }
      if (!mounted) return;
      final locals = MatrixLocals(L10n.of(context));
      await _afterSend(
        _routeOf(existing),
        room,
        existing.contact?.displayName(locals) ??
            existing.room.getLocalizedDisplayname(locals),
      );
      return;
    }
    setState(() => sending = true);
    try {
      if (recipients.length == 1) {
        await _startChatAndSend(client, recipients.single, payload, effect);
      } else {
        await _createGroupAndSend(client, payload, effect);
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  /// Opens the chat at [route] once a message went to [room], named [name]
  /// in the toast. A share from the Android share sheet then puts Seam
  /// behind the app that shared.
  Future<void> _afterSend(String route, Room room, String name) async {
    final l10n = L10n.of(context);
    _sent = true;
    context.go(route);
    if (widget.share?.fromShareIntent ?? false) {
      await AndroidDirectShare.returnToSourceApp(
        toast: shareSentToast(l10n, room, name),
      );
    }
  }

  /// Whether the message went out, so leaving the screen does not count as
  /// abandoning the share.
  bool _sent = false;

  /// Sends [payload] to the new room [roomId]: a share waits until all of it
  /// went out; plain text is sent as the chat shows it, without waiting.
  Future<Room> _sendNew(
    Client client,
    String roomId,
    SharePayload payload,
    MessageEffect? effect,
  ) async {
    final room = client.getRoomById(roomId);
    if (room == null) throw StateError('Room $roomId is not known');
    if (sharing) {
      await widget.delivery.sendShare(context, room, payload, effect: effect);
    } else {
      _sendText(room, payload.text, effect);
    }
    return room;
  }

  Future<void> _startChatAndSend(
    Client client,
    NewChatPerson<ExistingChat> person,
    SharePayload payload,
    MessageEffect? effect,
  ) async {
    final ({String route, Room room})? sent;
    if (isMatrixOnlyPerson(person)) {
      final result = await showFutureLoadingDialog<({String route, Room room})>(
        context: context,
        future: () async {
          final roomId = await widget.delivery.startMatrixChat(
            client,
            person.userIds.first,
          );
          final room = await _sendNew(client, roomId, payload, effect);
          return (route: '/rooms/$roomId', room: room);
        },
      );
      sent = result.asValue?.value;
    } else {
      final choice = _newChatChoice;
      if (choice == null) return;
      final result = await showFutureLoadingDialog<({String route, Room room})>(
        context: context,
        future: () async {
          final roomId = await widget.delivery.startChat(client, choice);
          final room = await _sendNew(client, roomId, payload, effect);
          final contactId = await addNewChatToMergedContact(
            client,
            person,
            roomId,
          );
          return (
            route: contactId == null
                ? '/rooms/$roomId'
                : mergedContactRoute(contactId),
            room: room,
          );
        },
      );
      sent = result.asValue?.value;
    }
    if (sent == null || !mounted) return;
    await _afterSend(sent.route, sent.room, person.name);
  }

  Future<void> _createGroupAndSend(
    Client client,
    SharePayload payload,
    MessageEffect? effect,
  ) async {
    final network = group.network;
    if (network == null) return;
    final members = group.members;
    final name = groupName.text.trim();
    final result = await showFutureLoadingDialog<(CreatedGroup, Room)>(
      context: context,
      future: () async {
        final created = await widget.delivery.createGroup(
          client,
          network,
          members,
          network.type.nameAllowed && name.isNotEmpty ? name : null,
        );
        final room = await _sendNew(client, created.roomId, payload, effect);
        return (created, room);
      },
    );
    final sent = result.asValue?.value;
    if (sent == null || !mounted) return;
    final (created, room) = sent;
    showGroupMembersNotAdded(context, members, created);
    await _afterSend(
      '/rooms/${created.roomId}',
      room,
      name.isNotEmpty
          ? name
          : members.map((member) => member.person.name).join(', '),
    );
  }

  /// Sends [text] without waiting for the server: the chat it opens shows
  /// the message as sending, and as failed with a retry if it does not go.
  void _sendText(Room room, String text, MessageEffect? effect) {
    widget.delivery.sendText(room, text, effect: effect).catchError((
      Object e,
      StackTrace s,
    ) {
      Logs().w('Unable to send the first message', e, s);
    });
  }

  /// Whether a long press on send offers iMessage's effects: a typed
  /// message with nothing staged (the bridge carries an effect on text
  /// only), going out on iMessage. That is the chat's network when there
  /// is one, else the new group's or the new direct chat's.
  bool get effectsAvailable {
    if (stagedFiles.isNotEmpty || stagedContents.isNotEmpty) return false;
    if (messageController.text.trim().isEmpty) return false;
    final room = sendRoom;
    if (room != null) return canSendMessageEffects(room);
    if (group.isGroup) return group.bridge?.name == 'imessage';
    return _newChatChoice?.bridge.name == 'imessage';
  }

  /// A long press on send: where [effectsAvailable], the effect picker,
  /// whose pick sends the message with it. [bubbleColor] and
  /// [onBubbleColor] are the send button's.
  Future<void> onSendLongPress(Color bubbleColor, Color onBubbleColor) async {
    if (!canSend || !effectsAvailable) return;
    final effect = await effects.showMessageEffectPicker(
      context,
      text: messageController.text,
      bubbleColor: bubbleColor,
      onBubbleColor: onBubbleColor,
    );
    if (effect != null && mounted) await send(effect: effect);
  }

  @override
  void dispose() {
    _searchCoolDown?.cancel();
    group.dispose();
    sources.dispose();
    controller.dispose();
    textFieldFocus.dispose();
    messageController.dispose();
    messageFocus.dispose();
    groupName.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final view = NewPrivateChatView(this);
    if (!(widget.share?.fromShareIntent ?? false)) return view;
    // Leaving a share from the share sheet unsent drops it with the screen
    // and goes back to the app that shared.
    return PopScope(
      onPopInvokedWithResult: (didPop, _) {
        if (didPop && !_sent) AndroidDirectShare.returnToSourceApp();
      },
      child: view,
    );
  }
}
