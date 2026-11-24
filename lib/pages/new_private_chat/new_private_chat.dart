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
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_launcher.dart';
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

  @override
  void initState() {
    super.initState();

    final deeplink = widget.deeplink;
    if (deeplink != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        UrlLauncher(context, deeplink).openMatrixToUrl();
      });
    }
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

  /// The people of [existingChats], who are left out of the directory
  /// results.
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
        if (MergedContact.resolve(client, entry)?.matchesSearch(
              needle,
              locals,
            ) ??
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
    for (final chat in existingChats) {
      for (final room in chat.contact?.rooms ?? [chat.room]) {
        final userId = room.directChatMatrixID;
        if (userId != null) _knownUserIds.add(userId);
      }
    }
    final List<Profile> fromDirectory;
    try {
      fromDirectory = (await Matrix.of(
        context,
      ).client.searchUserDirectory(searchTerm)).results;
    } catch (e, s) {
      if (existingChats.isEmpty) rethrow;
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

  @override
  void dispose() {
    controller.dispose();
    textFieldFocus.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => NewPrivateChatView(this);
}
