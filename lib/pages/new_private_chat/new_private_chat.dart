// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat_view.dart';
import 'package:fluffychat/pages/new_private_chat/qr_scanner_modal.dart';
import 'package:fluffychat/utils/adaptive_bottom_sheet.dart';
import 'package:fluffychat/utils/fluffy_share.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/url_launcher.dart';
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

  /// The direct chat with each person found among your chats, by user ID.
  final Map<String, String> _directChats = {};

  /// The direct chat already open with [userId], if one was found.
  String? directChatWith(String userId) => _directChats[userId];

  /// People from your direct chats whose name or ID contains [searchTerm].
  ///
  /// The server's user directory never returns bridged contacts, since
  /// Synapse keeps every user in an appservice namespace out of it, so they
  /// are only found here.
  List<Profile> _searchDirectChats(String searchTerm) {
    final client = Matrix.of(context).client;
    final needle = searchTerm.toLowerCase();
    final profiles = <String, Profile>{};
    for (final room in client.rooms) {
      if (room.membership != Membership.join) continue;
      final userId = room.directChatMatrixID;
      if (userId == null || profiles.containsKey(userId)) continue;
      final user = room.unsafeGetUserFromMemoryOrFallback(userId);
      final displayname = user.calcDisplayname();
      if (!displayname.toLowerCase().contains(needle) &&
          !userId.toLowerCase().contains(needle)) {
        continue;
      }
      _directChats[userId] = room.id;
      profiles[userId] = Profile(
        userId: userId,
        displayName: displayname,
        avatarUrl: user.avatarUrl,
      );
    }
    return profiles.values.toList()
      ..sort((a, b) => a.displayName!.compareTo(b.displayName!));
  }

  Future<List<Profile>> _searchUser(String searchTerm) async {
    _directChats.clear();
    final fromChats = AppSettings.suggestContactsFromChats.value
        ? _searchDirectChats(searchTerm)
        : <Profile>[];
    final List<Profile> fromDirectory;
    try {
      fromDirectory = (await Matrix.of(
        context,
      ).client.searchUserDirectory(searchTerm)).results;
    } catch (e, s) {
      if (fromChats.isEmpty) rethrow;
      Logs().w('User directory search failed', e, s);
      return fromChats;
    }
    final profiles = [
      ...fromChats,
      ...fromDirectory.where(
        (profile) => !_directChats.containsKey(profile.userId),
      ),
    ];

    if (searchTerm.isValidMatrixIdStrict() &&
        searchTerm.sigil == '@' &&
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

  void openUserModal(Profile profile) {
    final roomId = _directChats[profile.userId];
    if (roomId != null) {
      context.go('/rooms/$roomId');
      return;
    }
    UserDialog.show(context: context, profile: profile);
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
