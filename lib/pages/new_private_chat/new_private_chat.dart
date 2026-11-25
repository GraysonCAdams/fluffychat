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
import 'package:fluffychat/utils/new_chat/bridge_directory.dart';
import 'package:fluffychat/utils/new_chat/new_chat_people.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_launcher.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../widgets/adaptive_dialogs/user_dialog.dart';

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

  /// The bridges' contact lists and the phone's address book.
  late final NewChatSources sources = NewChatSources(onChanged: _rebuildPeople);

  /// The user's bridges, once their `whoami` answered.
  List<BridgeInfo> get bridges => sources.bridges;

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
  Future<void> _loadSources() => sources.load(Matrix.of(context).client);

  /// Asks for the contacts permission from the offer row.
  Future<void> allowPhoneContacts() => sources.allowPhoneContacts();

  /// Hides the offer row for good.
  Future<void> declinePhoneContacts() => sources.declinePhoneContacts();

  List<NewChatPerson<ExistingChat>> _mergePeople() =>
      sources.people(_peopleQuery, _chatInputs);

  void _rebuildPeople() {
    if (!mounted) return;
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

  Future<List<Profile>> _searchUser(String searchTerm) async {
    _knownUserIds.clear();
    existingChats = AppSettings.suggestContactsFromChats.value
        ? searchExistingChats(
            Matrix.of(context).client,
            searchTerm,
            MatrixLocals(L10n.of(context)),
          )
        : const [];
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
    final choice = await pickStartChatNetwork(context, client, person);
    if (choice == null || !mounted) return;
    final result = await showFutureLoadingDialog<String>(
      context: context,
      future: () => startBridgeChat(client, directory.api, choice),
    );
    final roomId = result.asValue?.value;
    if (roomId == null || !mounted) return;
    final contactId = await addNewChatToMergedContact(client, person, roomId);
    if (!mounted) return;
    context.go(
      contactId == null ? '/rooms/$roomId' : mergedContactRoute(contactId),
    );
  }

  @override
  void dispose() {
    sources.dispose();
    controller.dispose();
    textFieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NewPrivateChatView(this);
}
