// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/merged_contact_actions.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:fluffychat/pages/new_private_chat/start_chat_sheet.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/new_chat/add_people.dart' as add_people;
import 'package:fluffychat/utils/new_chat/compose.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// One network the first person in the To field is on, as the compose
/// screen's network switcher offers it: a chat the user has with them
/// there ([room]), or a network a bridge reaches them on with no chat yet.
class ComposeNetworkOption {
  final BridgeInfo? bridge;
  final Room? room;
  final String name;
  final Uri? avatar;

  const ComposeNetworkOption({
    required this.bridge,
    required this.room,
    required this.name,
    required this.avatar,
  });

  String get id => room?.id ?? 'bridge:${bridge?.name}';

  /// The bubble colour of the network, as a merged chat's send button
  /// takes it.
  Color? get color => NetworkColors.colorFor(
    room == null ? bridge?.networkId : NetworkColors.bridgeIdOf(room!),
  );
}

/// The compose screen behind New chat and Create group, as in iMessage: a
/// To field of people as chips, the chat the user already has with exactly
/// those people (or an empty history), and a composer for the first
/// message. One person makes a direct chat; two or more make a group on
/// the network the group's first people share. Sending the first message
/// starts the chat or creates the group when there is none, then opens it.
class NewPrivateChat extends StatefulWidget {
  final String? deeplink;
  final NewChatDelivery delivery;

  /// Opened from Create group: an account with no bridges goes on to the
  /// Matrix group page, since every group made here is on a network.
  final bool startGroup;

  const NewPrivateChat({
    super.key,
    required this.deeplink,
    this.delivery = const NewChatDelivery(),
    this.startGroup = false,
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
  final TextEditingController messageController = TextEditingController();

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
  /// network the first two fixed and everyone as that network knows them.
  /// Empty while there is one person or none.
  late final GroupDraft group = GroupDraft()
    ..addListener(() {
      if (mounted) setState(() {});
    });

  /// The chat the user already has with exactly the [recipients], shown
  /// above the composer and where the first message goes. Null when there
  /// is none.
  ExistingChat? conversation;

  /// The networks of the first person in the To field, for the network
  /// switcher; it shows when there are two or more. Empty otherwise.
  List<ComposeNetworkOption> networkOptions = const [];

  /// The [ComposeNetworkOption.id] picked in the switcher: at first the
  /// network of the most recent chat with the person.
  String? selectedNetworkId;

  /// The merged contact chat of the first person, which a send to one of
  /// its rooms opens.
  ExistingChat? _personChat;

  ComposeNetworkOption? get selectedNetwork => networkOptions
      .where((option) => option.id == selectedNetworkId)
      .firstOrNull;

  /// Whether the network switcher shows.
  bool get showNetworkSwitcher => networkOptions.length >= 2;

  /// Whether [option] can take everyone in the To field: in a group, every
  /// person after the first must be known on its network.
  bool networkEnabled(ComposeNetworkOption option) {
    if (recipients.length < 2) return true;
    final bridge = option.bridge;
    if (bridge == null) return false;
    return recipients
        .skip(1)
        .every((person) => person.bridgeUsers.containsKey(bridge.name));
  }

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
    // The bridges' list, which the group lookup reads, may be what came.
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

  /// Puts [person] in the To field. The first person goes in as they are.
  /// The second makes a group: the first two go through the group network
  /// picker and the bridge as in [toggleGroupMember], which fixes the
  /// network, and everyone after is checked against it. Someone the
  /// network cannot reach stays out, with the reason in a snackbar.
  Future<void> addRecipient(NewChatPerson<ExistingChat> person) async {
    if (sending) return;
    if (recipients.isNotEmpty) {
      final client = Matrix.of(context).client;
      final option = selectedNetwork;
      final optionBridge = option?.bridge;
      if (group.isEmpty && showNetworkSwitcher && optionBridge != null) {
        // The switcher picked the network: the group starts there.
        final network = await widget.delivery.groupNetworkOn(
          client,
          optionBridge,
        );
        if (network == null || !mounted) return;
        group.start(network, _firstMemberOn(recipients.first, option!));
      }
      if (group.isEmpty) {
        final started = await toggleGroupMember(
          context,
          client,
          widget.delivery,
          group,
          recipients.first,
        );
        if (!started || !mounted) return;
      }
      final added = await toggleGroupMember(
        context,
        client,
        widget.delivery,
        group,
        person,
      );
      if (!mounted) return;
      if (!added) {
        // Only the first person is in: still a direct chat.
        if (group.members.length < 2) group.clear();
        return;
      }
    }
    setState(() {
      recipients.add(person);
      _findConversation();
    });
    _clearSearch();
    textFieldFocus.requestFocus();
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
      _findConversation();
    });
  }

  void _clearSearch() {
    controller.clear();
    searchUsers();
  }

  /// Finds [conversation] for the people in the To field: one person's
  /// direct chat or merged contact, or the most recent group on the
  /// group's network whose people are exactly them.
  void _findConversation() {
    final client = Matrix.of(context).client;
    final network = group.network;
    if (recipients.isEmpty) {
      networkOptions = const [];
      selectedNetworkId = null;
      _personChat = null;
    }
    if (recipients.length == 1) {
      final chat = existingDirectChatOf(client, recipients.single);
      _personChat = chat;
      networkOptions = _optionsOf(client, recipients.single, chat);
      final options = networkOptions;
      if (options.length < 2) {
        selectedNetworkId = null;
        conversation = chat;
        return;
      }
      if (!options.any((option) => option.id == selectedNetworkId)) {
        selectedNetworkId = _mostRecent(options).id;
      }
      final room = selectedNetwork?.room;
      conversation = room == null
          ? null
          : ExistingChat(
              room: room,
              contact: null,
              networks: [?spacesByChild(client)[room.id]],
            );
    } else if (group.isGroup && network != null) {
      final room = existingGroupOf(
        client,
        bridges,
        network.bridge,
        group.members,
      );
      conversation = room == null
          ? null
          : ExistingChat(room: room, contact: null, networks: const []);
    } else {
      conversation = null;
    }
  }

  /// The networks [person] is on: each room of their chat (every room of
  /// a merged contact), then each bridge that knows them with no room
  /// there yet.
  List<ComposeNetworkOption> _optionsOf(
    Client client,
    NewChatPerson person,
    ExistingChat? chat,
  ) {
    final locals = MatrixLocals(L10n.of(context));
    final spaces = spacesByChild(client);
    final options = <ComposeNetworkOption>[];
    final covered = <String>{};
    for (final room in chat?.contact?.rooms ?? [?chat?.room]) {
      final space = spaces[room.id];
      final bridge = add_people.bridgeOfRoom(bridges, room);
      if (bridge != null) covered.add(bridge.name);
      options.add(
        ComposeNetworkOption(
          bridge: bridge,
          room: room,
          name: networkName(room, space, locals),
          avatar: space?.avatar ?? bridge?.icon,
        ),
      );
    }
    for (final bridge in bridges) {
      if (covered.contains(bridge.name)) continue;
      if (!person.bridgeUsers.containsKey(bridge.name)) continue;
      final spaceId = bridge.spaceRoomId;
      final space = spaceId == null ? null : client.getRoomById(spaceId);
      options.add(
        ComposeNetworkOption(
          bridge: bridge,
          room: null,
          name: bridge.displayName,
          avatar: space?.avatar ?? bridge.icon,
        ),
      );
    }
    return options;
  }

  /// The option whose chat had the last message, else the first.
  ComposeNetworkOption _mostRecent(List<ComposeNetworkOption> options) {
    final withRooms = options.where((option) => option.room != null).toList()
      ..sort(
        (a, b) => b.room!.latestEventReceivedTime.compareTo(
          a.room!.latestEventReceivedTime,
        ),
      );
    return withRooms.firstOrNull ?? options.first;
  }

  /// The switcher's [id] was tapped: one person's conversation moves to
  /// that network, and a group starts again on it.
  Future<void> selectNetwork(String id) async {
    if (recipients.length < 2) {
      setState(() {
        selectedNetworkId = id;
        _findConversation();
      });
      return;
    }
    final option = networkOptions.where((o) => o.id == id).firstOrNull;
    final bridge = option?.bridge;
    if (option == null || bridge == null || !networkEnabled(option)) return;
    final network = await widget.delivery.groupNetworkOn(
      Matrix.of(context).client,
      bridge,
    );
    if (network == null || !mounted) return;
    final first = _firstMemberOn(recipients.first, option);
    setState(() {
      selectedNetworkId = id;
      group.start(network, first);
      for (final person in recipients.skip(1)) {
        group.add(GroupMember(person, person.bridgeUsers[bridge.name]!));
      }
      _findConversation();
    });
  }

  /// The first person as [option]'s network knows them: the bridge's
  /// contact, else the ghost of their chat there.
  GroupMember _firstMemberOn(
    NewChatPerson<ExistingChat> person,
    ComposeNetworkOption option,
  ) {
    final known = person.bridgeUsers[option.bridge?.name];
    if (known != null) return GroupMember(person, known);
    final ghost = option.room?.directChatMatrixID;
    return GroupMember(
      person,
      BridgeUser(id: ghost ?? person.phone ?? person.name, mxid: ghost),
    );
  }

  /// The + at the end of the switcher: starts the person on a network
  /// they have no chat on, from the network sheet.
  Future<void> addNetwork() async {
    final person = recipients.firstOrNull;
    if (person == null) return;
    final client = Matrix.of(context).client;
    final choice = await widget.delivery.pickNetwork(context, client, person);
    if (choice == null || !mounted) return;
    person.bridgeUsers[choice.bridge.name] ??= choice.resolved;
    setState(() {
      _findConversation();
      selectedNetworkId = networkOptions
          .where((option) => option.bridge?.name == choice.bridge.name)
          .firstOrNull
          ?.id;
      _findConversation();
    });
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
    if (person.group) return L10n.of(context).groupChatNotAPerson;
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
  /// once there are two), a message, and a name when the network needs one.
  bool get canSend {
    if (sending || recipients.isEmpty) return false;
    if (messageController.text.trim().isEmpty) return false;
    if (recipients.length >= 2 && !group.isGroup) return false;
    final type = group.network?.type;
    if (conversation == null &&
        group.isGroup &&
        (type?.nameRequired ?? false) &&
        groupName.text.trim().isEmpty) {
      return false;
    }
    return true;
  }

  /// Sends the first message and opens the chat: in the [conversation]
  /// there is; else for one person a direct chat started on the network
  /// the user picks (or on Matrix for a Matrix user), and for two or more
  /// the group created through the network's bridge, named when a name was
  /// typed. The message is sent once the room is there.
  Future<void> send() async {
    if (!canSend) return;
    final text = messageController.text.trim();
    final client = Matrix.of(context).client;
    final existing = conversation;
    if (existing != null) {
      _sendText(existing.sendRoom, text);
      final personChat = _personChat;
      context.go(
        recipients.length == 1 && personChat != null
            ? _routeOf(personChat)
            : _routeOf(existing),
      );
      return;
    }
    setState(() => sending = true);
    try {
      if (recipients.length == 1) {
        await _startChatAndSend(client, recipients.single, text);
      } else {
        await _createGroupAndSend(client, text);
      }
    } finally {
      if (mounted) setState(() => sending = false);
    }
  }

  Future<void> _startChatAndSend(
    Client client,
    NewChatPerson<ExistingChat> person,
    String text,
  ) async {
    final String? route;
    if (isMatrixOnlyPerson(person)) {
      final result = await showFutureLoadingDialog<String>(
        context: context,
        future: () async {
          final roomId = await widget.delivery.startMatrixChat(
            client,
            person.userIds.first,
          );
          _sendTextTo(client, roomId, text);
          return '/rooms/$roomId';
        },
      );
      route = result.asValue?.value;
    } else {
      final option = selectedNetwork;
      final optionBridge = option?.bridge;
      final known = optionBridge == null
          ? null
          : person.bridgeUsers[optionBridge.name];
      // The switcher picked the network; the sheet asks only without one.
      final choice = optionBridge != null && known != null
          ? StartChatChoice(optionBridge, known.id, known)
          : await widget.delivery.pickNetwork(context, client, person);
      if (choice == null || !mounted) return;
      final result = await showFutureLoadingDialog<String>(
        context: context,
        future: () async {
          final roomId = await widget.delivery.startChat(client, choice);
          _sendTextTo(client, roomId, text);
          final contactId = await addNewChatToMergedContact(
            client,
            person,
            roomId,
          );
          return contactId == null
              ? '/rooms/$roomId'
              : mergedContactRoute(contactId);
        },
      );
      route = result.asValue?.value;
    }
    if (route == null || !mounted) return;
    context.go(route);
  }

  Future<void> _createGroupAndSend(Client client, String text) async {
    final network = group.network;
    if (network == null) return;
    final members = group.members;
    final name = groupName.text.trim();
    final result = await showFutureLoadingDialog<CreatedGroup>(
      context: context,
      future: () async {
        final created = await widget.delivery.createGroup(
          client,
          network,
          members,
          network.type.nameAllowed && name.isNotEmpty ? name : null,
        );
        _sendTextTo(client, created.roomId, text);
        return created;
      },
    );
    final created = result.asValue?.value;
    if (created == null || !mounted) return;
    showGroupMembersNotAdded(context, members, created);
    context.go('/rooms/${created.roomId}');
  }

  void _sendTextTo(Client client, String roomId, String text) {
    final room = client.getRoomById(roomId);
    if (room == null) throw StateError('Room $roomId is not known');
    _sendText(room, text);
  }

  /// Sends [text] without waiting for the server: the chat it opens shows
  /// the message as sending, and as failed with a retry if it does not go.
  void _sendText(Room room, String text) {
    widget.delivery.sendText(room, text).catchError((Object e, StackTrace s) {
      Logs().w('Unable to send the first message', e, s);
    });
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
  Widget build(BuildContext context) => NewPrivateChatView(this);
}
