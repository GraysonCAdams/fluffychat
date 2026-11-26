// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/pages/chat/network_toggle_group.dart';
import 'package:fluffychat/pages/new_private_chat/new_private_chat.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
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
/// row. With chips, "To:" is the row's first item, so it sits on the
/// centre line of the chips beside it, and the field is only as wide as
/// its text, so it stays on the chips' line until the text needs a line of
/// its own. With none, the field fills the line beside "To:".
class RecipientField extends StatelessWidget {
  final NewPrivateChatController controller;

  const RecipientField(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final recipients = controller.recipients;
    final label = Text(
      key: const ValueKey('compose-to-label'),
      l10n.composeTo,
      style: theme.textTheme.bodyLarge?.copyWith(
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
    final field = TextField(
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
        contentPadding: const EdgeInsets.symmetric(vertical: 10),
        hintText: recipients.isEmpty ? l10n.newChatSearchHint : null,
        hintStyle: theme.textTheme.bodyLarge?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: controller.textFieldFocus.requestFocus,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: 56),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 12, 8),
          // The field keeps its place in the tree whichever way "To:" is
          // laid out, so it keeps its focus as the first chip comes and the
          // last one goes.
          child: Row(
            spacing: 8,
            children: [
              if (recipients.isEmpty) label,
              Expanded(
                child: Align(
                  alignment: AlignmentDirectional.centerStart,
                  child: Wrap(
                    spacing: 8,
                    runSpacing: 4,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    children: [
                      if (recipients.isNotEmpty) label,
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
                          onDeleted: () => controller.removeRecipient(
                            groupMemberKey(person),
                          ),
                        ),
                      ConstrainedBox(
                        constraints: BoxConstraints(
                          minWidth: recipients.isEmpty ? double.infinity : 24,
                        ),
                        child: IntrinsicWidth(child: field),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Where the compose screen's network switcher sits. PROTOTYPE: a flag to
/// render both placements from the same code for review.
enum ComposeSwitcherPlacement {
  /// In the app bar's actions, as the chat page shows a merged contact's
  /// networks.
  appBar,

  /// Inside the composer, before the message field.
  composer,
}

ComposeSwitcherPlacement composeSwitcherPlacement =
    ComposeSwitcherPlacement.appBar;

/// The networks of the first person in the To field, when they are on two
/// or more: the chat page's [NetworkToggleGroup], the selected one the
/// network the message goes out on. For one person it ends with the
/// dashed plus that starts them on another network; in a group the
/// networks the later people are not on are faded and do not respond.
/// [compact] draws it narrower, for the composer.
class ComposeNetworkSwitcher extends StatelessWidget {
  final NewPrivateChatController controller;
  final bool compact;

  const ComposeNetworkSwitcher(
    this.controller, {
    this.compact = false,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final width = compact ? 34.0 : NetworkToggleGroup.defaultWidth;
    const height = NetworkToggleGroup.defaultHeight;
    return NetworkToggleGroup(
      key: const ValueKey('compose-network-switcher'),
      networks: [
        for (final option in controller.networkOptions)
          NetworkToggle(
            id: option.id,
            name: option.name,
            avatar: option.avatar,
            enabled: controller.networkEnabled(option),
          ),
      ],
      selectedId: controller.selectedNetworkId,
      onSelect: controller.sending ? null : controller.selectNetwork,
      width: width,
      trailing: controller.recipients.length == 1
          ? DashedAddSegment(
              tooltip: L10n.of(context).startChatOn,
              onTap: controller.addNetwork,
              width: width,
              height: height,
            )
          : null,
    );
  }
}

/// The network the first message goes out on, under the To field: the
/// existing direct chat's bridge space, or for one person with no chat yet
/// a note that the network is picked on send. A group shows none, as the
/// composer's hint names its network.
class ComposeNetworkLine extends StatelessWidget {
  final NewPrivateChatController controller;

  const ComposeNetworkLine(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    if (controller.group.isGroup) return const SizedBox.shrink();
    // The switcher names the network.
    if (controller.showNetworkSwitcher) return const SizedBox.shrink();
    final conversation = controller.conversation;
    final Widget leading;
    final String label;
    if (conversation != null) {
      final space = spacesByChild(
        Matrix.of(context).client,
      )[conversation.sendRoom.id];
      if (space == null) return const SizedBox.shrink();
      label = l10n.composeChatOn(
        space.getLocalizedDisplayname(MatrixLocals(l10n)),
      );
      leading = Avatar(
        mxContent: space.avatar,
        name: label,
        size: 20,
        borderRadius: BorderRadius.circular(6),
      );
    } else if (controller.recipients.length == 1 &&
        !isMatrixOnlyPerson(controller.recipients.single)) {
      label = l10n.composeNetworkOnSend;
      leading = Icon(
        Icons.swap_horiz_outlined,
        size: 20,
        color: theme.colorScheme.onSurfaceVariant,
      );
    } else {
      return const SizedBox.shrink();
    }
    return Padding(
      key: const ValueKey('compose-network'),
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
      child: Row(
        spacing: 8,
        children: [
          leading,
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

/// The compose screen's title while it makes a new group on a network
/// that takes a name: "New group chat", or the name once one is set, with
/// a pencil. A tap opens [showGroupNameDialog].
class GroupTitleButton extends StatelessWidget {
  final NewPrivateChatController controller;

  const GroupTitleButton(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return ListenableBuilder(
      listenable: controller.groupName,
      builder: (context, _) {
        final name = controller.groupName.text.trim();
        return InkWell(
          key: const ValueKey('group-title'),
          borderRadius: BorderRadius.circular(8),
          onTap: () => showGroupNameDialog(context, controller),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              spacing: 8,
              children: [
                Flexible(
                  child: Text(
                    name.isEmpty ? l10n.newGroupChat : name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                Icon(
                  Icons.edit_outlined,
                  size: 18,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

/// Asks for the new group's name and puts it in the controller's
/// `groupName`. Save stays off while the field is empty on a network that
/// needs a name; an empty name elsewhere leaves the group unnamed.
Future<void> showGroupNameDialog(
  BuildContext context,
  NewPrivateChatController controller,
) async {
  final name = await showDialog<String>(
    context: context,
    builder: (_) => _GroupNameDialog(
      initial: controller.groupName.text,
      required: controller.group.network?.type.nameRequired ?? false,
      rcsOnly: controller.group.network?.bridge.name == 'gmessages',
    ),
  );
  if (name != null) controller.groupName.text = name;
}

class _GroupNameDialog extends StatefulWidget {
  final String initial;
  final bool required;

  /// Whether to say that only an RCS group keeps the name.
  final bool rcsOnly;

  const _GroupNameDialog({
    required this.initial,
    required this.required,
    required this.rcsOnly,
  });

  @override
  State<_GroupNameDialog> createState() => _GroupNameDialogState();
}

class _GroupNameDialogState extends State<_GroupNameDialog> {
  late final TextEditingController _name = TextEditingController(
    text: widget.initial,
  );

  bool get _canSave => !widget.required || _name.text.trim().isNotEmpty;

  void _save() {
    if (_canSave) Navigator.of(context).pop(_name.text.trim());
  }

  @override
  void dispose() {
    _name.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(widget.required ? l10n.groupName : l10n.groupNameOptional),
      content: TextField(
        key: const ValueKey('group-name'),
        controller: _name,
        autofocus: true,
        textCapitalization: TextCapitalization.sentences,
        textInputAction: TextInputAction.done,
        onChanged: (_) => setState(() {}),
        onSubmitted: (_) => _save(),
        decoration: InputDecoration(
          labelText: l10n.name,
          helperText: widget.rcsOnly ? l10n.groupNameRcsOnly : null,
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(l10n.cancel),
        ),
        TextButton(
          key: const ValueKey('group-name-save'),
          onPressed: _canSave ? _save : null,
          child: Text(l10n.save),
        ),
      ],
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

  /// Before the message field, such as the network switcher.
  final Widget? leading;

  const ComposeBar(
    this.controller, {
    required this.hintText,
    this.leading,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final leading = this.leading;
    // The send button takes the colour of the network the message goes
    // out on, as in a merged chat.
    final networkColor = AppSettings.networkBubbleColors.value
        ? controller.selectedNetwork?.color
        : null;
    final sendBackground = networkColor ?? theme.bubbleColor;
    final sendForeground = networkColor == null
        ? theme.onBubbleColor
        : NetworkColors.foregroundOn(networkColor);
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
              if (leading != null)
                Container(
                  height: ChatInputRow.height,
                  alignment: Alignment.center,
                  padding: const EdgeInsetsDirectional.only(start: 12, end: 8),
                  child: leading,
                )
              else
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
                              backgroundColor: sendBackground,
                              foregroundColor: sendForeground,
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
