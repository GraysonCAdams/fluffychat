// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:async/async.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/notification_snooze.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;

import '../../utils/fluffy_share.dart';
import 'chat_list.dart';
import 'header_menu.dart';

/// The own avatar, opening the account menu: accounts, status, snooze,
/// settings and the like. Shown beside the chat list's search field, or in
/// the Windows title bar (TitleBarAccountButton), which sits outside the
/// app's pages; so the menu opens over the pages of [controller]'s
/// navigator and the choices act through the chat list.
class ClientChooserButton extends StatefulWidget {
  /// The chat list the menu acts on. Null only in the title bar while no
  /// chat list is up.
  final ChatListController? controller;

  /// Diameter of the avatar.
  final double size;

  /// Called for a click while there is no [controller]. The menu opens once
  /// a chat list arrives.
  final VoidCallback? onPressedWithoutList;

  const ClientChooserButton(
    this.controller, {
    this.size = 32,
    this.onPressedWithoutList,
    super.key,
  });

  @override
  State<ClientChooserButton> createState() => _ClientChooserButtonState();
}

class _ClientChooserButtonState extends State<ClientChooserButton> {
  ChatListController get controller => widget.controller!;

  /// Set by a click that arrived before the chat list did.
  bool _openWhenListArrives = false;

  @override
  void didUpdateWidget(covariant ClientChooserButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_openWhenListArrives && widget.controller != null) {
      _openWhenListArrives = false;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _openMenu();
      });
    }
  }

  void _onPressed() {
    if (widget.controller == null) {
      _openWhenListArrives = true;
      widget.onPressedWithoutList?.call();
      return;
    }
    _openMenu();
  }

  /// Opens the menu below the button, as a PopupMenuButton places it, on
  /// the overlay of the chat list's navigator, which need not hold the
  /// button; or closes the header menu open (see [HeaderMenu]).
  Future<void> _openMenu() async {
    final controller = widget.controller;
    if (controller == null || !controller.mounted) return;
    final listContext = controller.context;
    final button = context.findRenderObject()! as RenderBox;
    final overlay =
        Navigator.of(listContext).overlay!.context.findRenderObject()!
            as RenderBox;
    final under =
        (PopupMenuTheme.of(context).position ?? PopupMenuPosition.over) ==
        PopupMenuPosition.under;
    final offset = under ? Offset(0, button.size.height) : Offset.zero;
    final position = RelativeRect.fromRect(
      Rect.fromPoints(
        overlay.globalToLocal(button.localToGlobal(offset)),
        overlay.globalToLocal(
          button.localToGlobal(button.size.bottomRight(Offset.zero) + offset),
        ),
      ),
      Offset.zero & overlay.size,
    );
    final picked = await HeaderMenu.show(
      anchor: ClientChooserButton,
      navigator: Navigator.of(listContext),
      showMenu: () => showMenu<Object>(
        context: listContext,
        position: position,
        items: _bundleMenuItems(context),
      ),
    );
    if (picked == null || !mounted || !controller.mounted) return;
    _clientSelected(picked, controller.context);
  }

  // The own profile is read once per active client and again whenever the
  // client reports that this user's profile changed. Reading it in build
  // would query the profile store on every rebuild of the chat list header.
  Client? _profileClient;
  String? _profileUserId;
  Future<Profile>? _profileFuture;
  StreamSubscription<String>? _profileUpdates;

  Future<Profile>? _ownProfile(Client? client) {
    if (client == null || !client.isLogged()) {
      _profileClient = null;
      _profileUserId = null;
      _profileUpdates?.cancel();
      _profileUpdates = null;
      return _profileFuture = null;
    }
    if (client != _profileClient ||
        client.userID != _profileUserId ||
        _profileFuture == null) {
      _profileClient = client;
      _profileUserId = client.userID;
      _profileFuture = client.fetchOwnProfile();
      _profileUpdates?.cancel();
      _profileUpdates = client.onUserProfileUpdate.stream
          .where((userId) => userId == client.userID)
          .listen((_) {
            if (!mounted) return;
            setState(() {
              _profileFuture = client.fetchOwnProfile();
            });
          });
    }
    return _profileFuture;
  }

  @override
  void dispose() {
    _profileUpdates?.cancel();
    super.dispose();
  }

  List<PopupMenuEntry<Object>> _bundleMenuItems(BuildContext context) {
    final matrix = Matrix.of(context);
    final features = MatrixFeatures.forClient(matrix.client);
    final bundles = matrix.accountBundles.keys.toList()
      ..sort(
        (a, b) => a!.isValidMatrixIdStrict() == b!.isValidMatrixIdStrict()
            ? 0
            : a.isValidMatrixIdStrict() && !b.isValidMatrixIdStrict()
            ? -1
            : 1,
      );
    return <PopupMenuEntry<Object>>[
      if (features.isRelevant(MatrixFeature.status))
        PopupMenuItem(
          value: SettingsAction.setStatus,
          child: Row(
            children: [
              const Icon(Icons.edit_outlined),
              const SizedBox(width: 18),
              Text(L10n.of(context).setStatus),
            ],
          ),
        ),
      PopupMenuItem(
        value: SettingsAction.snooze,
        child: Row(
          children: [
            Icon(
              notificationsSnoozedUntil == null
                  ? Icons.notifications_paused_outlined
                  : Icons.notifications_active_outlined,
            ),
            const SizedBox(width: 18),
            Text(
              notificationsSnoozedUntil == null
                  ? L10n.of(context).snoozeNotifications
                  : L10n.of(context).resumeNotifications,
            ),
          ],
        ),
      ),
      if (features.isRelevant(MatrixFeature.identity))
        PopupMenuItem(
          value: SettingsAction.invite,
          child: Row(
            children: [
              Icon(Icons.adaptive.share_outlined),
              const SizedBox(width: 18),
              Text(L10n.of(context).inviteContact),
            ],
          ),
        ),
      PopupMenuItem(
        value: SettingsAction.archive,
        child: Row(
          children: [
            const Icon(Icons.archive_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).archive),
          ],
        ),
      ),
      PopupMenuItem(
        value: SettingsAction.settings,
        child: Row(
          children: [
            const Icon(Icons.settings_outlined),
            const SizedBox(width: 18),
            Text(L10n.of(context).settings),
          ],
        ),
      ),
      const PopupMenuDivider(),
      for (final bundle in bundles) ...[
        if (matrix.accountBundles[bundle]!.length != 1 ||
            matrix.accountBundles[bundle]!.single!.userID != bundle)
          PopupMenuItem(
            value: null,
            child: Column(
              crossAxisAlignment: .start,
              mainAxisSize: .min,
              children: [
                Text(
                  bundle!,
                  style: TextStyle(
                    color: Theme.of(context).textTheme.titleMedium!.color,
                    fontSize: 14,
                  ),
                ),
                const Divider(height: 1),
              ],
            ),
          ),
        ...matrix.accountBundles[bundle]!
            .whereType<Client>()
            .where((client) => client.isLogged())
            .map(
              (client) => PopupMenuItem(
                value: client,
                child: FutureBuilder<Profile?>(
                  future: client.fetchOwnProfile(),
                  builder: (context, snapshot) {
                    final displayname =
                        snapshot.data?.displayName ?? client.userID!.localpart!;
                    return Row(
                      key: ValueKey('switch_account_$displayname'),
                      children: [
                        Avatar(
                          mxContent: snapshot.data?.avatarUrl,
                          name: displayname,
                          size: 32,
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Text(
                            displayname,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 12),
                        IconButton(
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => controller.editBundlesForAccount(
                            client.userID,
                            bundle,
                          ),
                        ),
                      ],
                    );
                  },
                ),
              ),
            ),
      ],
    ];
  }

  @override
  Widget build(BuildContext context) {
    final matrix = Matrix.of(context);
    final client = Result(() => matrix.client).asValue?.value;

    var clientCount = 0;
    matrix.accountBundles.forEach((key, value) => clientCount += value.length);
    return FutureBuilder<Profile>(
      future: _ownProfile(client),
      builder: (context, snapshot) => Material(
        clipBehavior: Clip.hardEdge,
        borderRadius: BorderRadius.circular(99),
        color: Colors.transparent,
        child: IconButton(
          key: Key('accounts_and_settings_buttons'),
          tooltip: L10n.of(context).accountsAndSettings,
          onPressed: _onPressed,
          // As tall as the search field it sits beside.
          padding: EdgeInsets.zero,
          icon: Avatar(
            mxContent: snapshot.data?.avatarUrl,
            name: snapshot.data?.displayName ?? client?.userID?.localpart,
            size: widget.size,
          ),
        ),
      ),
    );
  }

  Future<void> _clientSelected(Object object, BuildContext context) async {
    if (object is Client) {
      controller.setActiveClient(object);
    } else if (object is String) {
      controller.setActiveBundle(object);
    } else if (object is SettingsAction) {
      switch (object) {
        case SettingsAction.invite:
          FluffyShare.shareInviteLink(context);
          break;
        case SettingsAction.settings:
          context.go('/rooms/settings');
          break;
        case SettingsAction.archive:
          context.go('/rooms/archive');
          break;
        case SettingsAction.setStatus:
          controller.setStatus();
          break;
        case SettingsAction.snooze:
          controller.toggleNotificationSnooze();
          break;
      }
    }
  }
}

enum SettingsAction { setStatus, snooze, invite, settings, archive }
