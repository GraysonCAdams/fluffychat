// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/widgets/adaptive_dialogs/show_ok_cancel_alert_dialog.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'matrix.dart';

enum ChatPopupMenuActions {
  openInNewWindow,
  details,
  encryption,
  leave,
  search,
}

class ChatSettingsPopupMenu extends StatefulWidget {
  final Room room;
  final bool displayChatDetails;

  /// Opens the chat details in place of going to [room]'s details page, for
  /// a chat that shows more than [room] (a merged contact).
  final VoidCallback? onChatDetails;

  /// Moves the chat to a window of its own. The menu offers it only when
  /// set.
  final VoidCallback? onOpenInNewWindow;

  const ChatSettingsPopupMenu(
    this.room,
    this.displayChatDetails, {
    this.onChatDetails,
    this.onOpenInNewWindow,
    super.key,
  });

  @override
  ChatSettingsPopupMenuState createState() => ChatSettingsPopupMenuState();
}

class ChatSettingsPopupMenuState extends State<ChatSettingsPopupMenu> {
  StreamSubscription? notificationChangeSub;

  @override
  void dispose() {
    notificationChangeSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    notificationChangeSub ??= Matrix.of(context).client.onSync.stream
        .where(
          (syncUpdate) =>
              syncUpdate.accountData?.any(
                (accountData) => accountData.type == 'm.push_rules',
              ) ??
              false,
        )
        .listen((u) => setState(() {}));
    // A chat bridged to another network has no Matrix encryption settings
    // worth showing, and leaving it means deleting the conversation.
    final plumbing = MatrixFeatures.forClient(
      widget.room.client,
    ).isRelevant(MatrixFeature.roomPlumbing, room: widget.room);
    return Stack(
      alignment: Alignment.center,
      children: [
        const SizedBox.shrink(),
        PopupMenuButton<ChatPopupMenuActions>(
          useRootNavigator: true,
          onSelected: (choice) async {
            switch (choice) {
              case ChatPopupMenuActions.openInNewWindow:
                widget.onOpenInNewWindow?.call();
                break;
              case ChatPopupMenuActions.leave:
                final l10n = L10n.of(context);
                final router = GoRouter.of(context);
                final confirmed = await showOkCancelAlertDialog(
                  context: context,
                  title: l10n.areYouSure,
                  message: plumbing
                      ? l10n.archiveRoomDescription
                      : l10n.deleteConversationDescription,
                  okLabel: plumbing ? l10n.leave : l10n.deleteConversation,
                  cancelLabel: l10n.cancel,
                  isDestructive: true,
                );
                if (confirmed != OkCancelResult.ok) return;
                if (!context.mounted) return;
                final result = await showFutureLoadingDialog(
                  context: context,
                  future: () => widget.room.leave(),
                );
                if (result.error == null) {
                  router.go('/rooms');
                }

                break;
              case ChatPopupMenuActions.details:
                final onChatDetails = widget.onChatDetails;
                if (onChatDetails != null) {
                  onChatDetails();
                } else {
                  _showChatDetails();
                }
                break;
              case ChatPopupMenuActions.search:
                context.go('/rooms/${widget.room.id}/search');
                break;
              case ChatPopupMenuActions.encryption:
                context.go('/rooms/${widget.room.id}/encryption');
                break;
            }
          },
          itemBuilder: (BuildContext context) => [
            if (widget.onOpenInNewWindow != null)
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.openInNewWindow,
                child: Row(
                  children: [
                    const Icon(Icons.open_in_new_outlined),
                    const SizedBox(width: 12),
                    Flexible(child: Text(L10n.of(context).openInNewWindow)),
                  ],
                ),
              ),
            if (widget.displayChatDetails && widget.room.membership == .join)
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.details,
                child: Row(
                  children: [
                    const Icon(Icons.info_outline_rounded),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).chatDetails),
                  ],
                ),
              ),
            if (widget.room.membership case .join || .leave)
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.search,
                child: Row(
                  children: [
                    const Icon(Icons.search_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).search),
                  ],
                ),
              ),
            if (plumbing &&
                (widget.room.membership == Membership.join ||
                    widget.room.membership == Membership.leave))
              PopupMenuItem<ChatPopupMenuActions>(
                value: ChatPopupMenuActions.encryption,
                child: Row(
                  children: [
                    const Icon(Icons.lock_outlined),
                    const SizedBox(width: 12),
                    Text(L10n.of(context).encryption),
                  ],
                ),
              ),
            PopupMenuItem<ChatPopupMenuActions>(
              value: ChatPopupMenuActions.leave,
              child: Row(
                children: [
                  const Icon(Icons.delete_outlined),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      plumbing
                          ? L10n.of(context).leave
                          : L10n.of(context).deleteConversation,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ],
    );
  }

  void _showChatDetails() {
    if (GoRouterState.of(context).uri.path.endsWith('/details')) {
      context.go('/rooms/${widget.room.id}');
    } else {
      context.go('/rooms/${widget.room.id}/details');
    }
  }
}
