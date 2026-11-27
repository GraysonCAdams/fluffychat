// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/pages/chat_list/navigation_rail.dart';
import 'package:fluffychat/pages/chat_list/room_updates_builder.dart';
import 'package:fluffychat/pages/chat_list/start_chat_fab.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';

import 'chat_list_body.dart';

class ChatListView extends StatelessWidget {
  final ChatListController controller;

  const ChatListView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final selectionToolbar =
        controller.selectionMode && controller.titleBarSearch != null;
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
                  // Under the Windows title bar, which starts after the
                  // rail, the rail runs from the top of the window.
                  ? MediaQuery.removePadding(
                      context: context,
                      removeTop: controller.titleBarSearch != null,
                      child: SpacesNavigationRail(
                        controller: controller,
                        activeSpaceId: controller.activeSpaceId,
                        onGoToChats: controller.clearActiveSpace,
                        onGoToSpaceId: controller.setActiveSpace,
                      ),
                    )
                  : SizedBox(
                      width: 0,
                      height: MediaQuery.sizeOf(context).height,
                    ),
            ),
          ),
          Expanded(
            child: GestureDetector(
              onTap: FocusManager.instance.primaryFocus?.unfocus,
              excludeFromSemantics: true,
              behavior: HitTestBehavior.translucent,
              child: Scaffold(
                body: Material(child: ChatListViewBody(controller)),
                // Under the Windows title bar a selection's controls float
                // at the bottom middle of the list, in New chat's place.
                floatingActionButtonLocation: selectionToolbar
                    ? FloatingActionButtonLocation.centerFloat
                    : null,
                // Floats at the bottom right of the chat list in every layout.
                floatingActionButton: selectionToolbar
                    ? RoomUpdatesBuilder(
                        client: Matrix.of(context).client,
                        builder: (context) =>
                            ChatListSelectionToolbar(controller: controller),
                      )
                    : !controller.isSearchMode &&
                          controller.activeSpaceId == null
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
