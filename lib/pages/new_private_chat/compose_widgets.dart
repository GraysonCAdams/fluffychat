// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/utils/new_chat/compose.dart';
import 'package:fluffychat/utils/new_chat/new_chat_search.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The compose screen's To field: "To:", the people picked as removable
/// chips, and the text field that searches for more, all in one wrapping
/// row.
class RecipientField extends StatelessWidget {
  final NewPrivateChatController controller;

  const RecipientField(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final recipients = controller.recipients;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: controller.textFieldFocus.requestFocus,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            spacing: 8,
            children: [
              SizedBox(
                height: 40,
                child: Center(
                  child: Text(
                    l10n.composeTo,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
              Expanded(
                child: Wrap(
                  spacing: 8,
                  runSpacing: 4,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    for (final person in recipients)
                      InputChip(
                        key: ValueKey(
                          'recipient-chip-${groupMemberKey(person)}',
                        ),
                        avatar: Avatar(
                          mxContent: person.avatar,
                          name: person.name,
                          size: 24,
                        ),
                        label: Text(person.name),
                        deleteButtonTooltipMessage: l10n.remove,
                        onDeleted: () =>
                            controller.removeRecipient(groupMemberKey(person)),
                      ),
                    ConstrainedBox(
                      constraints: const BoxConstraints(minWidth: 96),
                      child: IntrinsicWidth(
                        child: TextField(
                          key: const ValueKey('compose-to'),
                          controller: controller.controller,
                          focusNode: controller.textFieldFocus,
                          autofocus: true,
                          onChanged: controller.searchUsers,
                          onSubmitted: controller.submitSearch,
                          // Keeps the focus here after Enter makes a chip.
                          onEditingComplete: () {},
                          textInputAction: TextInputAction.done,
                          keyboardType: TextInputType.text,
                          style: theme.textTheme.bodyLarge,
                          decoration: InputDecoration(
                            isDense: true,
                            filled: false,
                            border: InputBorder.none,
                            enabledBorder: InputBorder.none,
                            focusedBorder: InputBorder.none,
                            contentPadding: const EdgeInsets.symmetric(
                              vertical: 10,
                            ),
                            hintText: recipients.isEmpty
                                ? l10n.newChatSearchHint
                                : null,
                            hintStyle: theme.textTheme.bodyLarge?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The network the first message goes out on, under the To field: the
/// existing chat's network, the network a new group is created on, or for
/// one person with no chat yet a note that the network is picked on send.
class ComposeNetworkLine extends StatelessWidget {
  final NewPrivateChatController controller;

  const ComposeNetworkLine(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final conversation = controller.conversation;
    final bridge = controller.group.bridge;
    final Uri? icon;
    final String label;
    if (conversation != null) {
      final space = spacesByChild(
        Matrix.of(context).client,
      )[conversation.sendRoom.id];
      if (space != null) {
        icon = space.avatar;
        label = l10n.composeChatOn(
          space.getLocalizedDisplayname(MatrixLocals(l10n)),
        );
      } else if (bridge != null) {
        icon = bridge.icon;
        label = l10n.composeChatOn(bridge.displayName);
      } else {
        return const SizedBox.shrink();
      }
    } else if (bridge != null) {
      icon = bridge.icon;
      label = l10n.composeGroupOn(bridge.displayName);
    } else if (controller.recipients.length == 1 &&
        !isMatrixOnlyPerson(controller.recipients.single)) {
      icon = null;
      label = l10n.composeNetworkOnSend;
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      key: const ValueKey('compose-network'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        spacing: 8,
        children: [
          if (bridge != null || conversation != null)
            Avatar(
              key: bridge != null && conversation == null
                  ? const ValueKey('group-network')
                  : null,
              mxContent: icon,
              name: label,
              size: 20,
              borderRadius: BorderRadius.circular(6),
            )
          else
            Icon(
              Icons.swap_horiz_outlined,
              size: 20,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          Expanded(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// The name of a new group, under the To field while it holds two or more
/// people on a network that takes a name.
class GroupNameField extends StatelessWidget {
  final NewPrivateChatController controller;

  const GroupNameField(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final network = controller.group.network;
    final required = network?.type.nameRequired ?? false;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: TextField(
        key: const ValueKey('group-name'),
        controller: controller.groupName,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.next,
        onSubmitted: (_) => controller.messageFocus.requestFocus(),
        decoration: InputDecoration(
          prefixIcon: const Icon(Icons.group_outlined),
          labelText: required ? l10n.groupName : l10n.groupNameOptional,
          helperText: network?.bridge.name == 'gmessages'
              ? l10n.groupNameRcsOnly
              : null,
        ),
      ),
    );
  }
}

/// The messages of a chat the user already has, read-only and newest at
/// the bottom, drawn with the chat's own bubbles: what the compose screen
/// shows above the composer for the people in its To field.
class ComposeConversation extends StatefulWidget {
  final ExistingChat chat;
  final NewChatDelivery delivery;

  const ComposeConversation({
    required this.chat,
    required this.delivery,
    super.key,
  });

  @override
  State<ComposeConversation> createState() => _ComposeConversationState();
}

class _ComposeConversationState extends State<ComposeConversation> {
  final ScrollController _scrollController = ScrollController();
  Timeline? _timeline;
  bool _failed = false;

  /// Fewer messages than this in the cache asks the server for more once,
  /// so a short screen of history is not left half empty.
  static const int _fillCount = 20;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final timeline = await widget.delivery.openTimeline(
        widget.chat,
        onUpdate: _update,
      );
      if (!mounted) {
        timeline.cancelSubscriptions();
        return;
      }
      setState(() => _timeline = timeline);
      if (timeline.events.filterByVisibleInGui().length < _fillCount &&
          timeline.canRequestHistory) {
        await timeline.requestHistory();
      }
    } catch (e, s) {
      Logs().w('Unable to read the chat for the compose screen', e, s);
      if (mounted) setState(() => _failed = true);
    }
  }

  void _update() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _timeline?.cancelSubscriptions();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final timeline = _timeline;
    if (timeline == null) {
      return _failed
          ? const SizedBox.shrink()
          : const Center(child: CircularProgressIndicator.adaptive());
    }
    final events = timeline.events.filterByVisibleInGui();
    if (events.isEmpty) {
      return ComposeEmptyHistory(text: L10n.of(context).noMessagesYet);
    }
    final colors = [theme.secondaryBubbleColor, theme.bubbleColor];
    final now = DateTime.now();
    return ListView.builder(
      key: const ValueKey('compose-history'),
      controller: _scrollController,
      reverse: true,
      padding: const EdgeInsets.symmetric(vertical: 8),
      itemCount: events.length,
      itemBuilder: (context, i) {
        final event = events[i];
        final nextEvent = i + 1 < events.length ? events[i + 1] : null;
        final previousEvent = i > 0 ? events[i - 1] : null;
        // A separator names the time wherever the conversation paused for
        // an hour or crossed midnight, as in the chat.
        final displayDate =
            nextEvent == null ||
            !event.originServerTs.sameDay(nextEvent.originServerTs) ||
            event.originServerTs.difference(nextEvent.originServerTs).abs() >=
                const Duration(hours: 1);
        final time = event.originServerTs;
        return Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (displayDate)
              Padding(
                padding: const EdgeInsets.only(top: 22, bottom: 8),
                child: Center(
                  child: Text(
                    time.sameDay(now)
                        ? time.localizedTimeOfDay(context)
                        : '${time.localizedDate(context)} • '
                              '${time.localizedTimeOfDay(context)}',
                    style: TextStyle(
                      fontSize: 12,
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ),
            // Read-only: the history only shows what the first message
            // joins, so nothing in a bubble reacts to a tap.
            IgnorePointer(
              child: Message(
                event,
                nextEvent: nextEvent,
                previousEvent: previousEvent,
                bigEmojis: const {},
                onSelect: (_) {},
                onInfoTab: (_) {},
                scrollToEventId: (_) {},
                onSwipe: () {},
                onMention: () {},
                onEdit: () {},
                enterThread: null,
                singleSelected: false,
                hideReactionPicker: true,
                timeline: timeline,
                scrollController: _scrollController,
                colors: colors,
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The quiet line in the middle of an empty conversation.
class ComposeEmptyHistory extends StatelessWidget {
  final String text;

  const ComposeEmptyHistory({required this.text, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: theme.textTheme.bodyMedium?.copyWith(
            color: theme.colorScheme.onSurfaceVariant,
          ),
        ),
      ),
    );
  }
}

/// The compose screen's composer, drawn as the chat's: a pill with the
/// message field and the send button at its end. Sending needs someone in
/// the To field and some text.
class ComposeBar extends StatelessWidget {
  final NewPrivateChatController controller;

  /// What the field says while empty, such as the network the message
  /// goes out on.
  final String hintText;

  const ComposeBar(this.controller, {required this.hintText, super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(8, 4, 8, 8),
        child: Material(
          clipBehavior: Clip.hardEdge,
          color: theme.colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(ChatInputRow.height / 2),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const SizedBox(width: 18),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.symmetric(vertical: 2),
                  child: TextField(
                    key: const ValueKey('compose-message'),
                    controller: controller.messageController,
                    focusNode: controller.messageFocus,
                    minLines: 1,
                    maxLines: 8,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    textInputAction: PlatformInfos.isMobile
                        ? TextInputAction.newline
                        : null,
                    decoration: InputDecoration(
                      contentPadding: const EdgeInsets.only(
                        right: 6,
                        bottom: 15,
                        top: 15,
                      ),
                      isDense: true,
                      hintText: hintText,
                      hintMaxLines: 1,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      filled: false,
                    ),
                  ),
                ),
              ),
              ListenableBuilder(
                listenable: Listenable.merge([
                  controller.messageController,
                  controller.groupName,
                ]),
                builder: (context, _) {
                  final enabled = controller.canSend;
                  return Container(
                    height: ChatInputRow.height,
                    width: 48,
                    alignment: Alignment.center,
                    child: controller.sending
                        ? const SizedBox.square(
                            dimension: 24,
                            child: CircularProgressIndicator.adaptive(
                              strokeWidth: 2,
                            ),
                          )
                        : IconButton(
                            key: const ValueKey('compose-send'),
                            tooltip: l10n.send,
                            onPressed: enabled ? controller.send : null,
                            style: IconButton.styleFrom(
                              fixedSize: const Size.square(40),
                              minimumSize: const Size.square(40),
                              padding: EdgeInsets.zero,
                              backgroundColor: theme.bubbleColor,
                              foregroundColor: theme.onBubbleColor,
                              disabledBackgroundColor: theme
                                  .colorScheme
                                  .onSurface
                                  .withAlpha(0x1f),
                              disabledForegroundColor: theme
                                  .colorScheme
                                  .onSurface
                                  .withAlpha(0x61),
                            ),
                            icon: const Icon(Icons.send_outlined),
                          ),
                  );
                },
              ),
              const SizedBox(width: 4),
            ],
          ),
        ),
      ),
    );
  }
}
