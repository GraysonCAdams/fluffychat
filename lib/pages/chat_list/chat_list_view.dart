// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/navigation_rail.dart';
import 'package:fluffychat/pages/chat_list/start_chat_fab.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list_body.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop:
          !controller.selectionMode &&
          !controller.isSearchMode &&
          controller.activeSpaceId == null,
      onPopInvokedWithResult: (pop, _) {
        if (pop) return;
        if (controller.selectionMode) {
          controller.clearSelection();
          return;
        }
        if (controller.activeSpaceId != null) {
          controller.clearActiveSpace();
          return;
        }
        if (controller.isSearchMode) {
          controller.cancelSearch();
          return;
        }
      },
      child: Row(
        children: [
          Material(
            color: Theme.of(context).colorScheme.surface,
            child: AnimatedSize(
              duration: FluffyThemes.animationDuration,
              curve: FluffyThemes.animationCurve,
              child: FluffyThemes.isColumnMode(context)
                  ? SpacesNavigationRail(
                      activeSpaceId: controller.activeSpaceId,
                      onGoToChats: controller.clearActiveSpace,
                      onGoToSpaceId: controller.setActiveSpace,
                    )
                  : SizedBox(
                      width: 0,
                      height: MediaQuery.sizeOf(context).height,
                    ),
            ),
          ),
          if (FluffyThemes.isColumnMode(context) ||
              AppSettings.displayNavigationRail.value)
            if (FluffyThemes.isColumnMode(context))
              Container(width: 1, color: Theme.of(context).dividerColor),

          Expanded(
            child: GestureDetector(
              onTap: FocusManager.instance.primaryFocus?.unfocus,
              excludeFromSemantics: true,
              behavior: HitTestBehavior.translucent,
              child: Scaffold(
                body: Material(child: ChatListViewBody(controller)),
                floatingActionButton:
                    !controller.isSearchMode &&
                        controller.activeSpaceId == null &&
                        !FluffyThemes.isColumnMode(context)
                    // Always the compact button, so it stays clear of the
                    // unread chip in the middle of the bottom edge.
                    ? const StartChatFab()
                    : const SizedBox.shrink(),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
