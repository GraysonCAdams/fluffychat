// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/navi_rail_item.dart';
import 'package:fluffychat/pages/chat_list/rail_menus.dart';
import 'package:fluffychat/pages/chat_list/room_updates_builder.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The rail beside the chat list: All chats (the app tile), one tile per
/// space the user is in except those hidden from it (see
/// [AppSettings.railHiddenSpaces]), and New space. A right click or long
/// press on All chats or a space opens its menu (see `rail_menus.dart`),
/// which acts through [controller].
class SpacesNavigationRail extends StatelessWidget {
  final ChatListController controller;
  final String? activeSpaceId;
  final void Function() onGoToChats;
  final void Function(String) onGoToSpaceId;

  const SpacesNavigationRail({
    required this.controller,
    required this.activeSpaceId,
    required this.onGoToChats,
    required this.onGoToSpaceId,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final client = Matrix.of(context).client;
    final coloredMode = !FluffyThemes.isColumnMode(context);
    final theme = Theme.of(context);
    return Material(
      color: coloredMode ? theme.colorScheme.surfaceContainer : null,
      child: SafeArea(
        child: RoomUpdatesBuilder(
          key: ValueKey(client.userID.toString()),
          client: client,
          builder: (context) {
            final hidden = AppSettings.railHiddenSpaces.value.toSet();
            final allSpaces = client.rooms
                .where(
                  (room) =>
                      room.isSpace &&
                      room.membership == .join &&
                      !hidden.contains(room.id),
                )
                .toList();
            // Each badge counts the unread chats it covers. Collecting the
            // unread ids once keeps that to one pass over the rooms instead
            // of one pass per space.
            final canCreateSpace = MatrixFeatures.forClient(
              client,
            ).isRelevant(MatrixFeature.spaces);
            final unreadRoomIds = <String>{
              for (final room in client.rooms)
                if (room.isUnread || room.membership == Membership.invite)
                  room.id,
            };

            return SizedBox(
              width: FluffyThemes.isColumnMode(context)
                  ? FluffyThemes.navRailWidth
                  : FluffyThemes.navRailWidth - 8,
              child: Column(
                children: [
                  Expanded(
                    child: ListView.builder(
                      padding: EdgeInsets.symmetric(vertical: 4),
                      scrollDirection: Axis.vertical,
                      itemCount: allSpaces.length + (canCreateSpace ? 2 : 1),
                      itemBuilder: (context, i) {
                        if (i == 0) {
                          return NaviRailItem(
                            isSelected: activeSpaceId == null,
                            onTap: onGoToChats,
                            onContextMenu: (position) => showAllChatsRailMenu(
                              context,
                              controller,
                              position,
                            ),
                            // All chats is Seam itself, so its tab is the app
                            // tile, sized, shaped and outlined like the network
                            // tiles below it.
                            icon: Container(
                              clipBehavior: Clip.antiAlias,
                              foregroundDecoration: ShapeDecoration(
                                shape: RoundedSuperellipseBorder(
                                  side: BorderSide(
                                    width: 1,
                                    color: Theme.of(context).dividerColor,
                                  ),
                                  borderRadius: BorderRadius.circular(
                                    AppConfig.spaceBorderRadius,
                                  ),
                                ),
                              ),
                              decoration: ShapeDecoration(
                                shape: RoundedSuperellipseBorder(
                                  borderRadius: BorderRadius.circular(
                                    AppConfig.spaceBorderRadius,
                                  ),
                                ),
                              ),
                              child: Image.asset(
                                'assets/seam/seam_app_icon.png',
                                width: Avatar.defaultSize,
                                height: Avatar.defaultSize,
                                filterQuality: FilterQuality.medium,
                              ),
                            ),
                            toolTip: L10n.of(context).chats,
                            unreadCount: unreadRoomIds.length,
                          );
                        }
                        i--;
                        if (i == allSpaces.length) {
                          return NaviRailItem(
                            isSelected: false,
                            onTap: () => context.go('/rooms/newspace'),
                            icon: const Padding(
                              padding: EdgeInsets.all(12.0),
                              child: Icon(Icons.add),
                            ),
                            toolTip: L10n.of(context).createNewSpace,
                          );
                        }
                        final space = allSpaces[i];
                        final displayname = allSpaces[i].chatDisplayname(
                          MatrixLocals(L10n.of(context)),
                        );
                        final unreadCount = space.spaceChildren
                            .map((c) => c.roomId)
                            .toSet()
                            .where(unreadRoomIds.contains)
                            .length;
                        return NaviRailItem(
                          toolTip: displayname,
                          isSelected: activeSpaceId == space.id,
                          onTap: () => onGoToSpaceId(allSpaces[i].id),
                          onContextMenu: (position) => showSpaceRailMenu(
                            context,
                            controller,
                            space,
                            position,
                          ),
                          unreadCount: unreadCount,
                          icon: Avatar(
                            mxContent: allSpaces[i].avatar,
                            name: displayname,
                            //size: 36,
                            shapeBorder: RoundedSuperellipseBorder(
                              side: BorderSide(
                                width: 1,
                                color: Theme.of(context).dividerColor,
                              ),
                              borderRadius: BorderRadius.circular(
                                AppConfig.spaceBorderRadius,
                              ),
                            ),
                            borderRadius: BorderRadius.circular(
                              AppConfig.spaceBorderRadius,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}
