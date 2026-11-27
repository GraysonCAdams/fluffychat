// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_details/chat_details.dart';
import 'package:fluffychat/pages/chat_details/participant_list_item.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/utils/matrix_features.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/network_identity.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/new_chat/add_people.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/room_features.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:fluffychat/utils/verified_room_extension.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/chat_settings_popup_menu.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:fluffychat/widgets/layouts/max_width_body.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_linkify/flutter_linkify.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import '../../utils/url_launcher.dart';
import '../../widgets/mxc_image_viewer.dart';
import '../../widgets/qr_code_viewer.dart';

class ChatDetailsView extends StatelessWidget {
  final ChatDetailsController controller;

  const ChatDetailsView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final room = Matrix.of(context).client.getRoomById(controller.roomId!);
    if (room == null) {
      return Scaffold(
        appBar: AppBar(title: Text(L10n.of(context).oopsSomethingWentWrong)),
        body: Center(
          child: Text(L10n.of(context).youAreNoLongerParticipatingInThisChat),
        ),
      );
    }

    final directChatMatrixID = room.directChatMatrixID;
    final roomAvatar = room.chatAvatar;
    final features = MatrixFeatures.forClient(room.client);
    // A chat bridged to another network shows the person, not the Matrix
    // plumbing: no room address, permissions or member list for a direct
    // chat, and name and photo only where the network takes them.
    final plumbing = features.isRelevant(
      MatrixFeature.roomPlumbing,
      room: room,
    );
    final bridgedDirectChat = !plumbing && room.isOneToOne;
    bool canChange(String type) =>
        room.canChangeStateEvent(type) &&
        (plumbing || RoomFeatures.of(room).allowsState(type));
    // A group lists its people, each with their network and number, and
    // ends with its notifications and a way to leave. Its bridge bot is
    // plumbing and is left out of both the list and the count.
    final isGroup = room.isGroupChat;
    final ownId = room.client.userID;
    final networkSpace = spacesByChild(room.client)[room.id];
    final networkLabel =
        features.bridgeOf(room)?.network ??
        networkSpace?.chatDisplayname(MatrixLocals(L10n.of(context)));
    final hiddenBot = isGroup && !plumbing
        ? features.bridgeOf(room)?.bot
        : null;

    return StreamBuilder(
      stream: controller.roomStateUpdates(room),
      builder: (context, snapshot) {
        var members = room.getParticipants().toList()
          ..sort((b, a) => a.powerLevel.level.compareTo(b.powerLevel.level));
        if (isGroup) {
          // The others by name, then the user.
          final others =
              members.where((m) => m.id != ownId && m.id != hiddenBot).toList()
                ..sort(
                  (a, b) => a.calcDisplayname().toLowerCase().compareTo(
                    b.calcDisplayname().toLowerCase(),
                  ),
                );
          members = [
            ...others.take(10),
            ...members.where((m) => m.id == ownId),
          ];
        } else {
          members = members.take(10).toList();
        }
        if (bridgedDirectChat) members = [];
        final avatarActions = [
          if (PlatformInfos.isMobile) AvatarAction.camera,
          AvatarAction.file,
          if (room.chatAvatar != null || room.toString().isEmpty)
            AvatarAction.remove,
        ];

        final avatarButtonStyle = IconButton.styleFrom(
          backgroundColor: theme.colorScheme.primaryContainer,
          foregroundColor: theme.colorScheme.onPrimaryContainer,
          shadowColor: theme.colorScheme.shadow,
          elevation: 2,
        );
        final actualMembersCount =
            (room.summary.mInvitedMemberCount ?? 0) +
            (room.summary.mJoinedMemberCount ?? 0) -
            (hiddenBot != null &&
                    room
                            .getState(EventTypes.RoomMember, hiddenBot)
                            ?.asUser(room)
                            .membership ==
                        Membership.join
                ? 1
                : 0);
        final canRequestMoreMembers = members.length < actualMembersCount;
        final iconColor = theme.textTheme.bodyLarge!.color;
        final displayname = room.chatDisplayname(
          MatrixLocals(L10n.of(context)),
        );
        return Scaffold(
          appBar: AppBar(
            leading:
                controller.widget.embeddedCloseButton ??
                const Center(child: BackButton()),
            elevation: theme.appBarTheme.elevation,
            actions: <Widget>[
              if (plumbing && room.canonicalAlias.isNotEmpty)
                IconButton(
                  tooltip: L10n.of(context).share,
                  icon: const Icon(Icons.qr_code_rounded),
                  onPressed: () =>
                      showQrCodeViewer(context, room.canonicalAlias),
                )
              else if (plumbing && directChatMatrixID != null)
                IconButton(
                  tooltip: L10n.of(context).share,
                  icon: const Icon(Icons.qr_code_rounded),
                  onPressed: () =>
                      showQrCodeViewer(context, directChatMatrixID),
                ),
              if (controller.widget.embeddedCloseButton == null)
                ChatSettingsPopupMenu(room, false),
            ],
            title: Text(L10n.of(context).chatDetails),
            backgroundColor: theme.appBarTheme.backgroundColor,
          ),
          body: MaxWidthBody(
            child: ListView.builder(
              physics: const NeverScrollableScrollPhysics(),
              shrinkWrap: true,
              itemCount:
                  members.length +
                  1 +
                  (canRequestMoreMembers && !bridgedDirectChat ? 1 : 0) +
                  (isGroup ? 1 : 0),
              itemBuilder: (BuildContext context, int i) => i == 0
                  ? Column(
                      crossAxisAlignment: .stretch,
                      children: <Widget>[
                        Center(
                          child: Stack(
                            children: [
                              Hero(
                                tag:
                                    controller.widget.embeddedCloseButton !=
                                        null
                                    ? 'embedded_content_banner'
                                    : 'content_banner',
                                child: GroupAvatar.shows(room)
                                    ? GroupAvatar(
                                        room: room,
                                        name: displayname,
                                        size: Avatar.defaultSize * 2.5,
                                      )
                                    : Avatar(
                                        mxContent: room.chatAvatar,
                                        name: displayname,
                                        size: Avatar.defaultSize * 2.5,
                                        animated: true,
                                        onTap: roomAvatar != null
                                            ? () => showDialog(
                                                context: context,
                                                builder: (_) =>
                                                    MxcImageViewer(roomAvatar),
                                              )
                                            : null,
                                      ),
                              ),
                              if (!room.isOneToOne &&
                                  canChange(EventTypes.RoomAvatar))
                                Positioned(
                                  bottom: 0,
                                  right: 0,
                                  child: avatarActions.length == 1
                                      ? IconButton(
                                          style: avatarButtonStyle,
                                          tooltip: L10n.of(
                                            context,
                                          ).editRoomAvatar,
                                          onPressed: () =>
                                              controller.setAvatarAction(
                                                avatarActions.single,
                                              ),
                                          icon: const Icon(
                                            Icons.camera_alt_outlined,
                                          ),
                                        )
                                      : PopupMenuButton<AvatarAction>(
                                          style: avatarButtonStyle,
                                          tooltip: L10n.of(
                                            context,
                                          ).editRoomAvatar,
                                          onSelected:
                                              controller.setAvatarAction,
                                          icon: const Icon(
                                            Icons.camera_alt_outlined,
                                          ),
                                          itemBuilder: (context) => [
                                            for (final action in avatarActions)
                                              PopupMenuItem(
                                                value: action,
                                                child: Row(
                                                  mainAxisSize: .min,
                                                  spacing: 12,
                                                  children: [
                                                    Icon(switch (action) {
                                                      AvatarAction.camera =>
                                                        Icons
                                                            .camera_alt_outlined,
                                                      AvatarAction.file =>
                                                        Icons.photo_outlined,
                                                      AvatarAction.remove =>
                                                        Icons.delete_outlined,
                                                    }),
                                                    Text(switch (action) {
                                                      AvatarAction.camera =>
                                                        L10n.of(
                                                          context,
                                                        ).openCamera,
                                                      AvatarAction.file =>
                                                        L10n.of(
                                                          context,
                                                        ).openGallery,
                                                      AvatarAction.remove =>
                                                        L10n.of(context).delete,
                                                    }),
                                                  ],
                                                ),
                                              ),
                                          ],
                                        ),
                                ),
                            ],
                          ),
                        ),
                        Padding(
                          padding: const EdgeInsets.all(8.0),
                          child: Center(
                            child: TextButton.icon(
                              onPressed:
                                  room.isOneToOne ||
                                      !canChange(EventTypes.RoomName)
                                  ? null
                                  : controller.setDisplaynameAction,
                              icon:
                                  room.isOneToOne ||
                                      !canChange(EventTypes.RoomName)
                                  ? null
                                  : Icon(Icons.edit_outlined, size: 16),

                              style: TextButton.styleFrom(
                                foregroundColor: theme.colorScheme.onSurface,
                                iconColor: theme.colorScheme.onSurface,
                                disabledForegroundColor:
                                    theme.colorScheme.onSurface,
                              ),
                              label: Row(
                                mainAxisSize: .min,
                                spacing: 4,
                                children: [
                                  if (room.allUsersVerified)
                                    Icon(
                                      Icons.verified,
                                      color: Theme.of(
                                        context,
                                      ).colorScheme.primary,
                                      size: 18,
                                    ),
                                  Text(
                                    displayname,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      fontSize: 18,
                                      fontWeight: FontWeight.normal,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),
                        if (isGroup)
                          Padding(
                            padding: const EdgeInsets.only(bottom: 16),
                            child: Text(
                              [
                                if (networkLabel != null)
                                  L10n.of(context).networkGroup(networkLabel),
                                L10n.of(
                                  context,
                                ).countPeople(actualMembersCount),
                              ].join(' · '),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                fontSize: 13,
                                color: theme.colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ),
                        StreamBuilder(
                          stream: controller.pushRuleUpdates(room),
                          builder: (context, _) => Wrap(
                            alignment: .center,
                            spacing: 16,
                            runSpacing: 16,
                            children: [
                              _MainChatDetailsButton(
                                onPressed: () =>
                                    context.go('/rooms/${room.id}/search'),
                                label: L10n.of(context).search,
                                icon: Icons.search,
                              ),
                              if (features.isRelevant(
                                MatrixFeature.customEmotes,
                                room: room,
                              ))
                                _MainChatDetailsButton(
                                  onPressed: () => context.push(
                                    '/rooms/${room.id}/details/emotes',
                                  ),
                                  label: L10n.of(context).stickers,
                                  icon: Icons.emoji_emotions_outlined,
                                ),
                              // A group has its notifications switch
                              // under Options.
                              if (isGroup)
                                const SizedBox.shrink()
                              else if (room.pushRuleState ==
                                  PushRuleState.notify)
                                _MainChatDetailsButton(
                                  onPressed: () => showFutureLoadingDialog(
                                    context: context,
                                    future: () => room.setPushRuleState(
                                      PushRuleState.mentionsOnly,
                                    ),
                                  ),
                                  label: L10n.of(context).mute,
                                  icon: Icons.notifications_on_outlined,
                                )
                              else
                                _MainChatDetailsButton(
                                  onPressed: () => showFutureLoadingDialog(
                                    context: context,
                                    future: () => room.setPushRuleState(
                                      PushRuleState.notify,
                                    ),
                                  ),
                                  label: L10n.of(context).unmuteChat,
                                  icon: Icons.notifications_off_outlined,
                                ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 16),
                        if (bridgedDirectChat)
                          for (final identity in NetworkIdentity.ofChat(
                            room,
                            MatrixLocals(L10n.of(context)),
                          ))
                            ListTile(
                              title: Text(
                                identity.network,
                                style: TextStyle(
                                  color: theme.colorScheme.secondary,
                                  fontSize: 12,
                                ),
                              ),
                              subtitle: SelectableText(
                                identity.identifier,
                                style: theme.textTheme.bodyLarge,
                              ),
                            ),
                        if (room.canChangeStateEvent(EventTypes.RoomTopic) ||
                            room.topic.isNotEmpty) ...[
                          ListTile(
                            title: Text(
                              L10n.of(context).chatDescription,
                              style: TextStyle(
                                color: theme.colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing:
                                room.canChangeStateEvent(EventTypes.RoomTopic)
                                ? IconButton(
                                    onPressed: controller.setTopicAction,
                                    tooltip: L10n.of(
                                      context,
                                    ).setChatDescription,
                                    icon: const Icon(Icons.edit_outlined),
                                  )
                                : null,
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16.0,
                            ),
                            child: SelectableLinkify(
                              text: room.topic.isEmpty
                                  ? L10n.of(context).noChatDescriptionYet
                                  : room.topic,
                              textScaleFactor: MediaQuery.textScalerOf(
                                context,
                              ).scale(1),
                              options: const LinkifyOptions(humanize: false),
                              linkStyle: const TextStyle(
                                color: Colors.blueAccent,
                                decorationColor: Colors.blueAccent,
                              ),
                              style: TextStyle(
                                fontSize: 14,
                                fontStyle: room.topic.isEmpty
                                    ? FontStyle.italic
                                    : FontStyle.normal,
                                color: theme.textTheme.bodyMedium!.color,
                                decorationColor:
                                    theme.textTheme.bodyMedium!.color,
                              ),
                              onOpen: (url) =>
                                  UrlLauncher(context, url.url).launchUrl(),
                            ),
                          ),
                          const SizedBox(height: 16),
                        ],
                        if (!room.isOneToOne && plumbing) ...[
                          Divider(color: theme.dividerColor),
                          ListTile(
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.surfaceContainer,
                              foregroundColor: iconColor,
                              child: const Icon(
                                Icons.admin_panel_settings_outlined,
                              ),
                            ),
                            title: Text(L10n.of(context).accessAndVisibility),
                            subtitle: Text(
                              L10n.of(context).accessAndVisibilityDescription,
                            ),
                            onTap: () => context.push(
                              '/rooms/${room.id}/details/access',
                            ),
                            trailing: const Icon(Icons.chevron_right_outlined),
                          ),
                          ListTile(
                            title: Text(L10n.of(context).chatPermissions),
                            subtitle: Text(
                              L10n.of(context).whoCanPerformWhichAction,
                            ),
                            leading: CircleAvatar(
                              backgroundColor:
                                  theme.colorScheme.surfaceContainer,
                              foregroundColor: iconColor,
                              child: const Icon(Icons.tune_outlined),
                            ),
                            trailing: const Icon(Icons.chevron_right_outlined),
                            onTap: () => context.push(
                              '/rooms/${room.id}/details/permissions',
                            ),
                          ),
                        ],
                        if (!bridgedDirectChat) ...[
                          Divider(color: theme.dividerColor),
                          ListTile(
                            title: Text(
                              isGroup
                                  ? L10n.of(
                                      context,
                                    ).countMembers(actualMembersCount)
                                  : L10n.of(
                                      context,
                                    ).countParticipants(actualMembersCount),
                              style: TextStyle(
                                color: theme.colorScheme.secondary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            trailing: room.isOneToOne
                                ? null
                                : switch (addMembersEntryOf(room)) {
                                    AddMembersEntry.invite => TextButton.icon(
                                      icon: Icon(Icons.add),
                                      label: Text(L10n.of(context).invite),
                                      onPressed: () => context.go(
                                        '/rooms/${room.id}/invite',
                                      ),
                                    ),
                                    AddMembersEntry.addPeople =>
                                      TextButton.icon(
                                        icon: Icon(Icons.add),
                                        label: Text(L10n.of(context).addPeople),
                                        onPressed: () => context.go(
                                          '/rooms/${room.id}/add-people',
                                        ),
                                      ),
                                    null => null,
                                  },
                          ),
                        ],
                      ],
                    )
                  : i < members.length + 1
                  ? isGroup
                        ? _groupMember(
                            context,
                            members[i - 1],
                            plumbing: plumbing,
                            networkSpace: networkSpace,
                            networkLabel: networkLabel,
                          )
                        : ParticipantListItem(members[i - 1])
                  : isGroup &&
                        i ==
                            members.length + 1 + (canRequestMoreMembers ? 1 : 0)
                  ? _GroupOptions(controller: controller, room: room)
                  : ListTile(
                      title: Text(
                        L10n.of(context).loadCountMoreParticipants(
                          (actualMembersCount - members.length),
                        ),
                      ),
                      onTap: () => context.push(
                        '/rooms/${controller.roomId!}/details/members',
                      ),
                      trailing: const Icon(Icons.chevron_right_outlined),
                    ),
            ),
          ),
        );
      },
    );
  }
}

/// A member of a group: "You" with the network for the user; for anyone
/// else their name with their network's badge, and their number or address
/// under it. A plain Matrix group shows names and user IDs as elsewhere.
Widget _groupMember(
  BuildContext context,
  User user, {
  required bool plumbing,
  required Room? networkSpace,
  required String? networkLabel,
}) {
  if (user.id == user.room.client.userID) {
    return ParticipantListItem(
      user,
      name: L10n.of(context).you,
      label: plumbing ? null : networkLabel,
    );
  }
  if (plumbing) return ParticipantListItem(user);
  return ParticipantListItem(
    user,
    label: MatrixFeatures.handleOf(user.id),
    badge: networkSpace == null
        ? null
        : Tooltip(
            message: networkLabel ?? '',
            child: Avatar(
              mxContent: networkSpace.avatar,
              name: networkLabel,
              size: 16,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
  );
}

/// The end of a group's details: its notifications switch and Leave group.
class _GroupOptions extends StatelessWidget {
  final ChatDetailsController controller;
  final Room room;

  const _GroupOptions({required this.controller, required this.room});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: .stretch,
      children: [
        Divider(color: theme.dividerColor),
        ListTile(
          title: Text(
            l10n.chatOptions,
            style: TextStyle(
              color: theme.colorScheme.secondary,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
        StreamBuilder(
          stream: controller.pushRuleUpdates(room),
          builder: (context, _) => SwitchListTile.adaptive(
            secondary: const Icon(Icons.notifications_outlined),
            title: Text(l10n.notifications),
            value: room.pushRuleState == PushRuleState.notify,
            onChanged: (on) => showFutureLoadingDialog(
              context: context,
              future: () => room.setPushRuleState(
                on ? PushRuleState.notify : PushRuleState.mentionsOnly,
              ),
            ),
          ),
        ),
        ListTile(
          leading: Icon(Icons.logout_outlined, color: theme.colorScheme.error),
          title: Text(
            l10n.leaveGroup,
            style: TextStyle(color: theme.colorScheme.error),
          ),
          onTap: controller.leaveGroupAction,
        ),
        const SizedBox(height: 16),
      ],
    );
  }
}

class _MainChatDetailsButton extends StatelessWidget {
  final VoidCallback onPressed;
  final String label;
  final IconData icon;

  const _MainChatDetailsButton({
    required this.onPressed,
    required this.label,
    required this.icon,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      color: theme.colorScheme.surfaceContainerHigh,
      borderRadius: BorderRadius.circular(AppConfig.borderRadius),
      child: InkWell(
        onTap: onPressed,
        borderRadius: BorderRadius.circular(AppConfig.borderRadius),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
          child: Column(
            crossAxisAlignment: .center,
            mainAxisSize: .min,
            children: [
              Icon(icon, color: theme.colorScheme.secondary),
              SizedBox(
                width: 64,
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  textAlign: .center,
                  style: TextStyle(color: theme.colorScheme.secondary),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
