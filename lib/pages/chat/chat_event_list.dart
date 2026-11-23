// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:cupertino_ui/cupertino_ui.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/encryption_info.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/merged_network_menu.dart';
import 'package:fluffychat/pages/chat/message_context_menu.dart';
import 'package:fluffychat/pages/chat/seen_by_row.dart';
import 'package:fluffychat/pages/chat/typing_indicators.dart';
import 'package:fluffychat/utils/account_config.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/mxc_image_viewer.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:scroll_to_index/scroll_to_index.dart';

import '../../config/app_config.dart';
import '../../utils/date_time_extension.dart';

class ChatEventList extends StatelessWidget {
  final ChatController controller;

  const ChatEventList({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    final timeline = controller.timeline;
    final theme = Theme.of(context);

    if (controller.room.membership == .invite) {
      final room = controller.room;
      final inviteState = room.unsafeGetUserFromMemoryOrFallback(
        room.client.userID!,
      );
      final sender = room
          .unsafeGetUserFromMemoryOrFallback(inviteState.senderId)
          .calcDisplayname();
      final nameOrAlias = room.name.isNotEmpty
          ? room.name
          : room.canonicalAlias.isNotEmpty
          ? room.canonicalAlias
          : null;
      final roomAvatar = room.avatar;

      return Center(
        child: Container(
          padding: const EdgeInsets.all(32.0),
          alignment: .center,
          constraints: BoxConstraints(maxWidth: 320),
          child: Column(
            mainAxisAlignment: .center,
            crossAxisAlignment: .center,
            spacing: 16,
            children: [
              Avatar(
                mxContent: roomAvatar,
                name: room.getLocalizedDisplayname(),
                size: Avatar.defaultSize * 2.5,
                onTap: roomAvatar != null
                    ? () => showDialog(
                        context: context,
                        builder: (_) => MxcImageViewer(roomAvatar),
                      )
                    : null,
                borderRadius: room.isSpace
                    ? BorderRadius.circular(AppConfig.spaceBorderRadius * 2.5)
                    : null,
              ),
              Text(
                nameOrAlias == null
                    ? L10n.of(context).youInvitedBy(sender)
                    : room.isSpace
                    ? L10n.of(
                        context,
                      ).senderHasInvitedYouToTheSpace(sender, nameOrAlias)
                    : L10n.of(
                        context,
                      ).senderHasInvitedYouToTheChat(sender, nameOrAlias),
                textAlign: .center,
              ),
            ],
          ),
        ),
      );
    }

    if (timeline == null) {
      return const Center(child: CupertinoActivityIndicator());
    }

    final colors = [theme.secondaryBubbleColor, theme.bubbleColor];

    final horizontalPadding = FluffyThemes.isColumnMode(context) ? 8.0 : 0.0;

    final events = timeline.events.filterByVisibleInGui(
      threadId: controller.activeThreadId,
    );

    // create a map of item key --> index to greatly improve performance of
    // ListView's findChildIndexCallback. It must use the same value as the
    // ValueKey of each item below, or messages still carrying a transaction
    // id (our own) are never found and get rebuilt from scratch.
    final thisEventsKeyMap = <String, int>{};
    for (var i = 0; i < events.length; i++) {
      thisEventsKeyMap[events[i].transactionId ?? events[i].eventId] = i;
    }

    // In a merged contact's chat a message names its network when it is on
    // another network than the message before it.
    final networks = controller.isMerged
        ? {
            for (final network
                in controller.mergedNetworks(MatrixLocals(L10n.of(context))) ??
                    const <MergedNetwork>[])
              network.room.id: network,
          }
        : const <String, MergedNetwork>{};
    final colorByNetwork = AppSettings.networkBubbleColors.value;

    final hasWallpaper =
        controller.room.client.applicationAccountConfig.wallpaperUrl != null;

    final topPadding = 8 + MediaQuery.paddingOf(context).top;
    final defaultInputBarHeight =
        72.0 + (FluffyThemes.isColumnMode(context) ? 16.0 : 0.0);

    return SelectionArea(
      child: _ChatTextScale(
        // The same layout ListView.custom builds from a delegate and padding,
        // spelled out so that only the padding listens to the composer
        // height, which changes on every frame of its animations.
        child: CustomScrollView(
          reverse: true,
          controller: controller.scrollController,
          keyboardDismissBehavior: PlatformInfos.isIOS
              ? ScrollViewKeyboardDismissBehavior.onDrag
              : ScrollViewKeyboardDismissBehavior.manual,
          slivers: [
            ValueListenableBuilder<double?>(
              valueListenable: controller.inputBarHeight,
              builder: (context, inputBarHeight, list) => SliverPadding(
                padding: EdgeInsets.only(
                  top: topPadding,
                  bottom: 8.0 + (inputBarHeight ?? defaultInputBarHeight),
                  left: horizontalPadding,
                  right: horizontalPadding,
                ),
                sliver: list,
              ),
              child: SliverList(
                delegate: SliverChildBuilderDelegate(
                  (BuildContext context, int i) {
                    // Footer to display typing indicator and read receipts:
                    if (i == 0) {
                      if (timeline.canRequestFuture) {
                        return Center(
                          child: TextButton.icon(
                            onPressed: timeline.isRequestingFuture
                                ? null
                                : controller.requestFuture,
                            icon: timeline.isRequestingFuture
                                ? CircularProgressIndicator.adaptive(
                                    strokeWidth: 2,
                                  )
                                : const Icon(Icons.arrow_downward_outlined),
                            label: Text(L10n.of(context).loadMore),
                          ),
                        );
                      }
                      return Column(
                        mainAxisSize: .min,
                        children: [
                          if (events.isNotEmpty)
                            SeenByRow(event: events.first, timeline: timeline),
                          TypingIndicators(controller),
                          EncryptionInfo(room: controller.room),
                        ],
                      );
                    }

                    // Request history button or progress indicator:
                    if (i == events.length + 1) {
                      if (controller.activeThreadId != null ||
                          !timeline.canRequestHistory) {
                        return const SizedBox.shrink();
                      }
                      return Builder(
                        builder: (context) {
                          final visibleIndex = timeline.events.lastIndexWhere(
                            (event) =>
                                !event.isCollapsedState && event.isVisibleInGui,
                          );
                          if (visibleIndex > timeline.events.length - 50) {
                            WidgetsBinding.instance.addPostFrameCallback(
                              controller.requestHistory,
                            );
                          }
                          return Center(
                            child: TextButton.icon(
                              onPressed: timeline.isRequestingHistory
                                  ? null
                                  : controller.requestHistory,
                              icon: timeline.isRequestingHistory
                                  ? CircularProgressIndicator.adaptive(
                                      strokeWidth: 2,
                                    )
                                  : const Icon(Icons.arrow_upward_outlined),
                              label: Text(L10n.of(context).loadMore),
                            ),
                          );
                        },
                      );
                    }
                    i--;

                    // The message at this index:
                    final event = events[i];
                    final animateIn =
                        (event.transactionId ?? event.eventId) ==
                        controller.animateInEventId;

                    final nextEvent = i + 1 < events.length
                        ? events[i + 1]
                        : null;
                    final previousEvent = i > 0 ? events[i - 1] : null;

                    // Collapsed state event
                    final canExpand =
                        event.isCollapsedState &&
                        nextEvent?.isCollapsedState == true &&
                        previousEvent?.isCollapsedState != true;
                    final isCollapsed =
                        event.isCollapsedState &&
                        previousEvent?.isCollapsedState == true &&
                        !controller.expandedEventIds.contains(event.eventId);

                    final displayDate =
                        event.type == EventTypes.RoomCreate ||
                        nextEvent == null ||
                        !event.originServerTs.sameDay(nextEvent.originServerTs);

                    return AutoScrollTag(
                      key: ValueKey(event.transactionId ?? event.eventId),
                      index: i,
                      controller: controller.scrollController,
                      child: Column(
                        mainAxisSize: .min,
                        children: [
                          if (!isCollapsed && displayDate)
                            Padding(
                              padding: const EdgeInsets.only(
                                top: 8.0,
                                bottom: 16.0,
                              ),
                              child: Center(
                                child: Padding(
                                  padding: const EdgeInsets.only(top: 4.0),
                                  child: Material(
                                    borderRadius: BorderRadius.circular(
                                      AppConfig.borderRadius * 2,
                                    ),
                                    color: theme.colorScheme.inverseSurface
                                        .withAlpha(200),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8.0,
                                        vertical: 2.0,
                                      ),
                                      child: Text(
                                        event.originServerTs.localizedDate(
                                          context,
                                        ),
                                        style: TextStyle(
                                          fontWeight: FontWeight.bold,
                                          color: theme
                                              .colorScheme
                                              .onInverseSurface,
                                        ),
                                      ),
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          Message(
                            event,
                            bigEmojis: controller.bigEmojis,
                            animateIn: animateIn,
                            onSwipe: () =>
                                controller.replyAction(replyTo: event),
                            onInfoTab: controller.showEventInfo,
                            onMention: () => controller.sendController.text +=
                                '${event.senderFromMemoryOrFallback.mention} ',
                            highlightMarker:
                                controller.scrollToEventIdMarker ==
                                event.eventId,
                            onSelect: controller.onSelectMessage,
                            onContextMenu: (event, position) =>
                                showMessageContextMenu(
                                  controller,
                                  event,
                                  position,
                                ),
                            scrollToEventId: controller.scrollToEventId,
                            longPressSelect:
                                controller.selectedEvents.isNotEmpty,
                            selected: controller.selectedEvents.any(
                              (e) => e.eventId == event.eventId,
                            ),
                            singleSelected:
                                controller
                                    .selectedEvents
                                    .singleOrNull
                                    ?.eventId ==
                                event.eventId,
                            hideReactionPicker: controller.messageMenuOpen,
                            onEdit: controller.editSelectedEventAction,
                            timeline: timeline,
                            displayReadMarker:
                                i > 0 &&
                                controller.readMarkerEventId == event.eventId,
                            nextEvent: nextEvent,
                            previousEvent: previousEvent,
                            wallpaperMode: hasWallpaper,
                            scrollController: controller.scrollController,
                            colors: colors,
                            isCollapsed: isCollapsed,
                            networkBadge:
                                networks.isEmpty ||
                                    nextEvent?.roomId == event.roomId
                                ? null
                                : _NetworkBadge(networks[event.roomId]),
                            networkColor: colorByNetwork
                                ? networks[event.roomId]?.brandColor
                                : null,
                            enterThread: controller.activeThreadId == null
                                ? controller.enterThread
                                : null,
                            onExpand: canExpand
                                ? () => controller.expandEventsFrom(
                                    event,
                                    !controller.expandedEventIds.contains(
                                      event.eventId,
                                    ),
                                  )
                                : null,
                          ),
                        ],
                      ),
                    );
                  },
                  childCount: events.length + 2,
                  findChildIndexCallback: (key) =>
                      controller.findChildIndexCallback(key, thisEventsKeyMap),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Applies the chat font size setting to the timeline.
///
/// Copying the whole [MediaQueryData] depends on all of it, keyboard insets
/// included. Doing that here rather than in [ChatEventList] means a keyboard
/// animation rebuilds only this widget, and the timeline passed in as
/// [child] is reused as is.
class _ChatTextScale extends StatelessWidget {
  final Widget child;

  const _ChatTextScale({required this.child});

  @override
  Widget build(BuildContext context) => MediaQuery(
    data: MediaQuery.of(
      context,
    ).copyWith(textScaler: TextScaler.linear(AppSettings.fontSizeFactor.value)),
    child: child,
  );
}

/// The network a message in a merged contact's chat came over: its icon and
/// name, small, beside the message's time.
class _NetworkBadge extends StatelessWidget {
  final MergedNetwork? network;

  const _NetworkBadge(this.network);

  @override
  Widget build(BuildContext context) {
    final network = this.network;
    if (network == null) return const SizedBox.shrink();
    final color = Theme.of(context).colorScheme.onSurfaceVariant;
    return Padding(
      padding: const EdgeInsets.only(left: 4),
      child: Text(network.name, style: TextStyle(fontSize: 11, color: color)),
    );
  }
}
