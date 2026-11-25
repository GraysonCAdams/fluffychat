// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/merged_contact_actions.dart';
import 'package:fluffychat/pages/chat_list/merged_contact_list.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:fluffychat/pages/new_private_chat/start_chat_sheet.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/bridge_provisioning.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/contact_identifiers.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/model.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:fluffychat/utils/new_chat/bridge_directory.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/phone_contacts.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/merged_contacts/network_badges.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/adaptive_dialogs/user_dialog.dart';

/// A chat the user already has, as a New Chat search result.
class ExistingChat {
  /// The chat, or for a merged contact the room that represents it.
  final Room room;

  /// The merged contact [room] belongs to, or null.
  final MergedContact? contact;

  /// The networks (bridge spaces) the chat is on, without repeats.
  final List<Room> networks;

  const ExistingChat({
    required this.room,
    required this.contact,
    required this.networks,
  });
}

class NewPrivateChat extends StatefulWidget {
  final String? deeplink;
  const NewPrivateChat({super.key, required this.deeplink});

  @override
  NewPrivateChatController createState() => NewPrivateChatController();
}

class NewPrivateChatController extends State<NewPrivateChat> {
  final TextEditingController controller = TextEditingController();
  final FocusNode textFieldFocus = FocusNode();

  Future<List<Profile>>? searchResponse;

  Timer? _searchCoolDown;

  static const Duration _coolDown = Duration(milliseconds: 500);

  /// The user's bridges, once their `whoami` answered.
  List<BridgeInfo> bridges = const [];

  List<BridgeContactInput> _bridgeContacts = const [];

  List<PhoneBookEntry> _phoneBook = const [];

  /// Whether to show the row that asks to read the phone's contacts.
  bool offerPhoneContacts = false;

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
    final directory = BridgeDirectory.forClient(client);
    if (directory != null) {
      directory.bridges().then((value) {
        if (mounted) setState(() => bridges = value);
      });
      directory.contacts().then((value) {
        if (!mounted) return;
        _bridgeContacts = value;
        _rebuildPeople();
      });
    }
    if (await PhoneContacts.shouldOffer()) {
      if (mounted) setState(() => offerPhoneContacts = true);
    } else {
      await _loadPhoneBook();
    }
  }

  Future<void> _loadPhoneBook() async {
    final entries = await PhoneContacts.load();
    if (!mounted || entries.isEmpty) return;
    _phoneBook = entries;
    _rebuildPeople();
  }

  /// Asks for the contacts permission from the offer row.
  Future<void> allowPhoneContacts() async {
    final granted = await PhoneContacts.request();
    if (!mounted) return;
    setState(() => offerPhoneContacts = false);
    if (granted) await _loadPhoneBook();
  }

  /// Hides the offer row for good.
  Future<void> declinePhoneContacts() async {
    setState(() => offerPhoneContacts = false);
    await PhoneContacts.decline();
  }

  String get _phoneRegion => MergeSuggestionService.defaultPhoneRegion();

  List<NewChatPerson<ExistingChat>> _mergePeople() => mergeNewChatPeople(
    query: _peopleQuery,
    chats: _chatInputs,
    bridgeContacts: _bridgeContacts,
    phoneBook: _phoneBook,
    defaultRegion: _phoneRegion,
  );

  void _rebuildPeople() {
    if (searchResponse == null || _peopleQuery.isEmpty) return;
    setState(() => people = _mergePeople());
  }

  /// What New Chat knows about the other person of [chat].
  ChatPersonInput<ExistingChat> _chatInput(
    ExistingChat chat,
    MatrixLocals locals,
  ) {
    final client = chat.room.client;
    final rooms = chat.contact?.rooms ?? [chat.room];
    final suggestions = MergeSuggestionService.forClient(client);
    final stored = chat.contact?.entry.identifier;
    var phone = stored?['type'] == IdentifierType.phone.name
        ? stored!['value'] as String?
        : null;
    for (final room in rooms) {
      if (phone != null) break;
      phone = suggestions.phoneOf(room)?.value;
    }
    return ChatPersonInput(
      chat: chat,
      name:
          chat.contact?.displayName(locals) ??
          chat.room.getLocalizedDisplayname(locals),
      avatar: chat.contact?.avatar ?? chat.room.avatar,
      phone: phone,
      userIds: [for (final room in rooms) ?room.directChatMatrixID],
      networks: [
        for (final network in chat.networks)
          NetworkRef(
            key: network.id,
            name: network.getLocalizedDisplayname(locals),
            icon: network.avatar,
          ),
      ],
    );
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
    _searchCoolDown = Timer(_coolDown, () {
      setState(() {
        searchResponse = _searchUser(searchTerm);
      });
    });
  }

  /// The chats you already have that the search found, newest first. A
  /// merged contact is one entry, like in the chat list.
  List<ExistingChat> existingChats = const [];

  /// The Matrix IDs of [people], who are left out of the directory results.
  final Set<String> _knownUserIds = {};

  /// Your chats whose name, or whose other person's ID, contains
  /// [searchTerm]: what a chat list search for it finds.
  ///
  /// The server's user directory never returns bridged contacts, since
  /// Synapse keeps every user in an appservice namespace out of it, so they
  /// are only found here.
  List<ExistingChat> _searchChats(String searchTerm) {
    final client = Matrix.of(context).client;
    final locals = MatrixLocals(L10n.of(context));
    final needle = searchTerm.toLowerCase();
    final rooms = client.rooms
        .where((room) => room.membership == Membership.join && !room.isSpace)
        .toList();
    bool matches(Room room) =>
        room.getLocalizedDisplayname(locals).toLowerCase().contains(needle) ||
        (room.directChatMatrixID?.toLowerCase().contains(needle) ?? false);
    final store = MergedContactsStore.forClient(client);
    final named = <String>{
      for (final entry in store.contacts)
        if (MergedContact.resolve(
              client,
              entry,
            )?.matchesSearch(needle, locals) ??
            false)
          ...entry.rooms,
    };
    final listed = MergedChatList.build(
      client,
      rooms,
      (room) => matches(room) || named.contains(room.id),
    );
    final spaces = spacesByChild(client);
    return [
      for (final room in listed.rooms)
        ExistingChat(
          room: room,
          contact: listed.contacts[room.id],
          networks: NetworkBadges.distinctOf(
            listed.contacts[room.id]?.networks(spaces) ?? [spaces[room.id]],
          ),
        ),
    ];
  }

  Future<List<Profile>> _searchUser(String searchTerm) async {
    _knownUserIds.clear();
    existingChats = AppSettings.suggestContactsFromChats.value
        ? _searchChats(searchTerm)
        : const [];
    final locals = MatrixLocals(L10n.of(context));
    _peopleQuery = searchTerm;
    _chatInputs = [for (final chat in existingChats) _chatInput(chat, locals)];
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

  void openUserModal(Profile profile) =>
      UserDialog.show(context: context, profile: profile);

  /// Opens [chat]: the merged conversation for a merged contact.
  void openExistingChat(ExistingChat chat) {
    final contact = chat.contact;
    context.go(
      contact == null
          ? '/rooms/${chat.room.id}'
          : mergedContactRoute(contact.id),
    );
  }

  /// Opens [person]'s chat, or lets the user pick a network to start one on.
  Future<void> openPerson(NewChatPerson<ExistingChat> person) async {
    final chat = person.chat;
    if (chat != null) return openExistingChat(chat);
    final client = Matrix.of(context).client;
    final directory = BridgeDirectory.forClient(client);
    if (directory == null) return;
    final bridges = await directory.bridges();
    if (!mounted) return;
    final choice = await showAdaptiveBottomSheet<StartChatChoice>(
      context: context,
      builder: (_) => StartChatSheet(
        person: person,
        bridges: bridges,
        resolve: directory.api.resolveIdentifier,
      ),
    );
    if (choice == null || !mounted) return;
    final result = await showFutureLoadingDialog<String>(
      context: context,
      future: () => _startChat(client, directory.api, choice),
    );
    final roomId = result.asValue?.value;
    if (roomId == null || !mounted) return;
    final contactId = await _addToMergedContact(client, person, roomId);
    if (!mounted) return;
    context.go(
      contactId == null ? '/rooms/$roomId' : mergedContactRoute(contactId),
    );
  }

  /// How long [_startChat] waits for a new room to come down the sync.
  static const Duration _roomTimeout = Duration(seconds: 30);

  /// The room of [choice]: the existing direct chat the bridge reported, or
  /// one `create_dm` starts. Waits until the room is on this client and
  /// joins it if the bridge only invited the user.
  Future<String> _startChat(
    Client client,
    BridgeProvisioning api,
    StartChatChoice choice,
  ) async {
    final known = choice.resolved.dmRoomId;
    final roomId = known != null && client.getRoomById(known) != null
        ? known
        : await api.createDm(choice.bridge, choice.identifier);
    if (client.getRoomById(roomId) == null) {
      await client
          .waitForRoomInSync(roomId, join: true, invite: true)
          .timeout(_roomTimeout);
    }
    final room = client.getRoomById(roomId);
    if (room != null && room.membership == Membership.invite) {
      await room.join();
    }
    return roomId;
  }

  /// Adds [roomId] to the merged contact with [person]'s phone number, if
  /// there is one, and returns that contact's ID.
  Future<String?> _addToMergedContact(
    Client client,
    NewChatPerson person,
    String roomId,
  ) async {
    final phone = person.phone;
    if (phone == null) return null;
    final store = MergedContactsStore.forClient(client);
    final suggestions = MergeSuggestionService.forClient(client);
    bool hasPhone(MergedContactEntry entry) {
      final stored = entry.identifier;
      if (stored?['type'] == IdentifierType.phone.name &&
          stored?['value'] == phone) {
        return true;
      }
      final contact = MergedContact.resolve(client, entry);
      return contact?.rooms.any(
            (room) => suggestions.phoneOf(room)?.value == phone,
          ) ??
          false;
    }

    final entry = store.contacts.where(hasPhone).firstOrNull;
    if (entry == null) return null;
    if (!entry.rooms.contains(roomId)) {
      try {
        await store.merge([roomId], intoContactId: entry.id);
      } catch (e, s) {
        Logs().w('Unable to add the new chat to its contact', e, s);
        return null;
      }
    }
    return entry.id;
  }

  @override
  void dispose() {
    controller.dispose();
    textFieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NewPrivateChatView(this);
}
