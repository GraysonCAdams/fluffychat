// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/message.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/filtered_timeline_extension.dart';
import 'package:fluffychat/utils/merged_contacts/network_colors.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The messages of a chat, read-only and newest at the bottom, drawn with
/// the chat's own bubbles. Opening the timeline sends nothing: no read
/// marker or receipt moves while it is shown.
///
/// The compose screen shows one above its composer, and the chat list's
/// peek (see `showChatPeek`) shows one in its card.
class ReadOnlyConversation extends StatefulWidget {
  /// Opens the timeline to show, calling `onUpdate` when it changes: a
  /// room's own, or a merged contact's `MergedTimeline`.
  final Future<Timeline> Function(void Function() onUpdate) open;

  /// With fewer messages than this in the cache the server is asked for
  /// more, once. Zero shows what is cached and asks for nothing.
  final int fillCount;

  /// A key for the list, for tests to find it by.
  final Key? listKey;

  /// Padding around the messages inside the list.
  final EdgeInsetsGeometry padding;

  /// What a failed read logs, naming the screen.
  final String failureLog;

  /// Whether a drag scrolls the messages. Without it the newest that fit
  /// show, and drags are left to what holds the list.
  final bool scrollable;

  const ReadOnlyConversation({
    required this.open,
    this.fillCount = 0,
    this.listKey,
    this.padding = const EdgeInsets.symmetric(vertical: 8),
    this.failureLog = 'Unable to read the chat',
    this.scrollable = true,
    super.key,
  });

  @override
  State<ReadOnlyConversation> createState() => _ReadOnlyConversationState();
}

class _ReadOnlyConversationState extends State<ReadOnlyConversation> {
  final ScrollController _scrollController = ScrollController();
  Timeline? _timeline;
  bool _failed = false;

  @override
  void initState() {
    super.initState();
    _open();
  }

  Future<void> _open() async {
    try {
      final timeline = await widget.open(_update);
      if (!mounted) {
        timeline.cancelSubscriptions();
        return;
      }
      setState(() => _timeline = timeline);
      if (timeline.events.filterByVisibleInGui().length < widget.fillCount &&
          timeline.canRequestHistory) {
        await timeline.requestHistory();
      }
    } catch (e, s) {
      Logs().w(widget.failureLog, e, s);
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
      return ConversationEmptyHistory(text: L10n.of(context).noMessagesYet);
    }
    final now = DateTime.now();
    return ListView.builder(
      key: widget.listKey,
      controller: _scrollController,
      physics: widget.scrollable ? null : const NeverScrollableScrollPhysics(),
      reverse: true,
      padding: widget.padding,
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
            // Read-only, so nothing in a bubble reacts to a tap.
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
                // The user's bubbles take the colour they have in the chat.
                networkColor: NetworkColors.bubbleColorOf(event.room),
              ),
            ),
          ],
        );
      },
    );
  }
}

/// The quiet line in the middle of an empty conversation.
class ConversationEmptyHistory extends StatelessWidget {
  final String text;

  const ConversationEmptyHistory({required this.text, super.key});

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
