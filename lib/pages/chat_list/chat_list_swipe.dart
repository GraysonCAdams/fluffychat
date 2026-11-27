// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// What swiping a chat list row one way does, chosen per direction in
/// Settings > Chat > Swipe actions and stored by name.
enum ChatSwipeAction {
  markRead,
  lowPriority,
  pin,
  mute,
  leave,
  none;

  /// The action stored as [name], or [none] for a name it does not know.
  static ChatSwipeAction named(String name) => values.asNameMap()[name] ?? none;

  /// The action a swipe to the right does.
  static ChatSwipeAction get right =>
      named(AppSettings.chatListSwipeRight.value);

  /// The action a swipe to the left does.
  static ChatSwipeAction get left => named(AppSettings.chatListSwipeLeft.value);

  /// The action's name in the settings, covering both ways a toggle goes.
  String label(L10n l10n) => switch (this) {
    markRead => l10n.swipeMarkReadOrUnread,
    lowPriority => l10n.lowPriority,
    pin => l10n.swipePinOrUnpin,
    mute => l10n.swipeMuteOrUnmute,
    leave => l10n.leave,
    none => l10n.swipeNone,
  };

  IconData get icon => switch (this) {
    markRead => Icons.mark_email_read_outlined,
    lowPriority => Icons.low_priority,
    pin => Icons.push_pin_outlined,
    mute => Icons.notifications_off_outlined,
    leave => Icons.delete_outlined,
    none => Icons.do_not_disturb_on_outlined,
  };

  /// The background and its content colour once a swipe is past the
  /// threshold, from the scheme's roles so they follow the theme seed.
  (Color, Color) colors(ColorScheme scheme) => switch (this) {
    markRead => (scheme.primaryContainer, scheme.onPrimaryContainer),
    lowPriority => (scheme.tertiaryContainer, scheme.onTertiaryContainer),
    pin || mute => (scheme.secondaryContainer, scheme.onSecondaryContainer),
    leave => (scheme.errorContainer, scheme.onErrorContainer),
    none => (scheme.surfaceContainerHighest, scheme.onSurfaceVariant),
  };
}

/// Ticks whenever a swipe setting changes, so the chat list rows and the
/// Swipe actions row in chat settings, both open beside or under the
/// settings page, pick up the change.
final swipeActionsChanged = ValueNotifier(0);

/// A swipe action as it applies to one chat: the label and icon its row
/// shows (Pin or Unpin, say) and what releasing past the threshold does.
class SwipeAction {
  final ChatSwipeAction kind;
  final String label;
  final IconData icon;
  final VoidCallback onCommit;

  const SwipeAction(this.kind, this.label, this.icon, this.onCommit);
}

/// The swipe actions of [room]'s row in the chat list, one per direction,
/// each null where swiping that way does nothing. Rows do not swipe while
/// swiping is turned off, while chats are selected, and for spaces and
/// chats not joined (invites).
({SwipeAction? right, SwipeAction? left}) chatSwipeActions(
  ChatListController controller,
  Room room,
) {
  final chat = SelectedChat(room, controller.mergedContactFor(room));
  if (!AppSettings.chatListSwipe.value ||
      controller.selectionMode ||
      room.isSpace ||
      !chat.isJoined) {
    return (right: null, left: null);
  }
  return (
    right: _swipeAction(controller, chat, ChatSwipeAction.right),
    left: _swipeAction(controller, chat, ChatSwipeAction.left),
  );
}

/// What [action] does to [chat], or null when it does not apply to it. As
/// in the selection bar, a pinned chat is not made low priority, nor a low
/// priority one pinned. A merged contact acts on every one of its rooms.
SwipeAction? _swipeAction(
  ChatListController controller,
  SelectedChat chat,
  ChatSwipeAction action,
) {
  final l10n = L10n.of(controller.context);
  final chats = [chat];
  switch (action) {
    case ChatSwipeAction.markRead:
      final read = chat.isUnread;
      return SwipeAction(
        action,
        read ? l10n.markAsRead : l10n.markAsUnread,
        read
            ? Icons.mark_email_read_outlined
            : Icons.mark_email_unread_outlined,
        () => setSelectedRead(controller, chats, read),
      );
    case ChatSwipeAction.lowPriority:
      if (chat.isPinned) return null;
      final set = !chat.isLowPriority;
      return SwipeAction(
        action,
        set ? l10n.lowPriority : l10n.unsetLowPriority,
        Icons.low_priority,
        () => _swipeLowPriority(controller, chat, set),
      );
    case ChatSwipeAction.pin:
      if (chat.isLowPriority) return null;
      final pin = !chat.isPinned;
      return SwipeAction(
        action,
        pin ? l10n.pin : l10n.unpin,
        pin ? Icons.push_pin_outlined : Icons.push_pin,
        () => setSelectedPinned(controller, chats, pin),
      );
    case ChatSwipeAction.mute:
      final mute = !chat.isMuted;
      return SwipeAction(
        action,
        mute ? l10n.muteChat : l10n.unmuteChat,
        mute ? Icons.notifications_off_outlined : Icons.notifications_outlined,
        () => setSelectedMuted(controller, chats, mute),
      );
    case ChatSwipeAction.leave:
      return SwipeAction(
        action,
        l10n.leave,
        Icons.delete_outlined,
        () => leaveSelected(controller, chats),
      );
    case ChatSwipeAction.none:
      return null;
  }
}

/// Makes [chat] low priority when [set], else takes it out, and offers to
/// undo that. Undo restores only the rooms the swipe changed, so a merged
/// contact's room that already was low priority stays so.
Future<void> _swipeLowPriority(
  ChatListController controller,
  SelectedChat chat,
  bool set,
) async {
  final context = controller.context;
  final l10n = L10n.of(context);
  final messenger = ScaffoldMessenger.of(context);
  final name =
      chat.contact?.displayName(MatrixLocals(l10n)) ??
      chat.room.chatDisplayname(MatrixLocals(l10n));
  final changed = await setSelectedLowPriority(controller, [chat], set);
  if (changed.isEmpty) return;
  messenger.showSnackBar(
    SnackBar(
      content: Text(
        set
            ? l10n.chatMovedToLowPriority(name)
            : l10n.chatNoLongerLowPriority(name),
      ),
      action: SnackBarAction(
        label: l10n.undo,
        onPressed: () {
          if (!controller.mounted) return;
          showFutureLoadingDialog(
            context: controller.context,
            future: () =>
                Future.wait(changed.map((room) => room.setLowPriority(!set))),
          );
        },
      ),
    ),
  );
}

/// A chat list row that can be swiped right or left to act on its chat.
///
/// The row slides over a background shaped like its highlight. Below the
/// threshold the background is neutral and shows only the action's icon;
/// past it, the background takes the action's colours, the label shows,
/// and a light haptic marks the crossing, either way. Releasing past the
/// threshold runs the action; the row always slides back, and a chat the
/// action moves or removes leaves the list on its own.
///
/// Only touch swipes: a mouse drag does nothing, and a swipe that starts
/// in the system's gesture inset at the screen's edge is left to the back
/// gesture. The actions are also screen reader custom actions on the row
/// (see [ChatListSwipeSemantics]).
class ChatListSwipe extends StatefulWidget {
  final Widget child;

  /// What a swipe to the right does, null for nothing.
  final SwipeAction? right;

  /// What a swipe to the left does, null for nothing.
  final SwipeAction? left;

  const ChatListSwipe({required this.child, this.right, this.left, super.key});

  /// How far a row [width] wide must move for a release to act: 30% of
  /// the row, but at least 96 so a narrow column needs a real swipe.
  static double thresholdFor(double width) => max(96, width * 0.3);

  @override
  State<ChatListSwipe> createState() => _ChatListSwipeState();
}

class _ChatListSwipeState extends State<ChatListSwipe>
    with SingleTickerProviderStateMixin {
  late final AnimationController _offset = AnimationController.unbounded(
    vsync: this,
  );

  double _width = 0;

  /// Whether the swipe under way started in the back gesture's inset.
  bool _ignored = false;

  /// Whether the swipe under way is past the threshold, for the haptic on
  /// each crossing.
  bool _armed = false;

  @override
  void dispose() {
    _offset.dispose();
    super.dispose();
  }

  void _onStart(DragStartDetails details) {
    final insets = MediaQuery.systemGestureInsetsOf(context);
    final screenWidth = MediaQuery.sizeOf(context).width;
    final x = details.globalPosition.dx;
    _ignored = x < insets.left || x > screenWidth - insets.right;
    _offset.stop();
  }

  void _onUpdate(DragUpdateDetails details) {
    if (_ignored) return;
    var offset = (_offset.value + details.primaryDelta!).clamp(-_width, _width);
    if ((offset > 0 && widget.right == null) ||
        (offset < 0 && widget.left == null)) {
      offset = 0;
    }
    _offset.value = offset;
    final armed = offset.abs() >= ChatListSwipe.thresholdFor(_width);
    if (armed != _armed) HapticFeedback.lightImpact();
    _armed = armed;
  }

  void _onEnd([DragEndDetails? _]) {
    final action = !_armed
        ? null
        : _offset.value > 0
        ? widget.right
        : widget.left;
    _armed = false;
    _ignored = false;
    _offset.animateTo(
      0,
      duration: const Duration(milliseconds: 200),
      curve: Curves.easeOut,
    );
    action?.onCommit();
  }

  @override
  Widget build(BuildContext context) {
    final right = widget.right;
    final left = widget.left;
    final swipes = right != null || left != null;
    // The detector and its callbacks stay in the tree when nothing swipes,
    // so the row's own state survives entering and leaving selection.
    return ChatListSwipeSemantics(
      actions: {
        if (right != null)
          CustomSemanticsAction(label: right.label): right.onCommit,
        if (left != null)
          CustomSemanticsAction(label: left.label): left.onCommit,
      },
      child: GestureDetector(
        supportedDevices: const {PointerDeviceKind.touch},
        // Where the finger went down, to tell a swipe from the back gesture.
        dragStartBehavior: DragStartBehavior.down,
        onHorizontalDragStart: swipes ? _onStart : null,
        onHorizontalDragUpdate: swipes ? _onUpdate : null,
        onHorizontalDragEnd: swipes ? _onEnd : null,
        onHorizontalDragCancel: swipes ? _onEnd : null,
        child: LayoutBuilder(
          builder: (context, constraints) {
            _width = constraints.maxWidth;
            return AnimatedBuilder(
              animation: _offset,
              child: widget.child,
              builder: (context, child) {
                final offset = _offset.value;
                return SwipeRowFrame(
                  offset: offset,
                  action: offset > 0
                      ? right
                      : offset < 0
                      ? left
                      : null,
                  armed: offset.abs() >= ChatListSwipe.thresholdFor(_width),
                  child: child!,
                );
              },
            );
          },
        ),
      ),
    );
  }
}

/// Hands a swiped row's actions to the tile inside it, which adds them to
/// its own screen reader node as custom actions: a node of their own
/// around the tile would not be where the screen reader's focus lands.
class ChatListSwipeSemantics extends InheritedWidget {
  final Map<CustomSemanticsAction, VoidCallback> actions;

  const ChatListSwipeSemantics({
    required this.actions,
    required super.child,
    super.key,
  });

  /// The actions of the swiped row around [context], empty outside one.
  static Map<CustomSemanticsAction, VoidCallback> of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<ChatListSwipeSemantics>()
          ?.actions ??
      const {};

  // The callbacks are made anew on every build; only a change in which
  // actions the row offers needs the tile rebuilt.
  @override
  bool updateShouldNotify(ChatListSwipeSemantics oldWidget) =>
      !setEquals(oldWidget.actions.keys.toSet(), actions.keys.toSet());
}

/// A row moved [offset] sideways (right is positive) over the background
/// of [action], in its colours when [armed] and neutral before. The moved
/// row is painted on [background] (the surface by default) so the action
/// does not show through it.
class SwipeRowFrame extends StatelessWidget {
  final double offset;
  final SwipeAction? action;
  final bool armed;
  final Color? background;
  final Widget child;

  const SwipeRowFrame({
    required this.offset,
    required this.action,
    required this.armed,
    required this.child,
    this.background,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final action = this.action;
    final shown = action != null && offset != 0;
    final (fill, content) = shown && armed
        ? action.kind.colors(scheme)
        : (scheme.surfaceContainerHighest, scheme.onSurfaceVariant);
    // The uncovered strip, less the row's 8 side padding.
    final reveal = offset.abs() - 8;
    // The same children every frame, so the row keeps its state.
    return Stack(
      children: [
        Positioned.fill(
          child: !shown
              ? const SizedBox.shrink()
              : Stack(
                  children: [
                    // Shaped like the row's highlight (see ChatListItem).
                    Positioned.fill(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 3,
                        ),
                        child: DecoratedBox(
                          decoration: BoxDecoration(
                            color: fill,
                            borderRadius: BorderRadius.circular(
                              AppConfig.borderRadius,
                            ),
                          ),
                        ),
                      ),
                    ),
                    if (reveal >= 32)
                      Positioned(
                        top: 0,
                        bottom: 0,
                        left: offset > 0 ? 8 : null,
                        right: offset < 0 ? 8 : null,
                        width: reveal,
                        child: Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              AnimatedScale(
                                scale: armed ? 1.15 : 0.9,
                                duration: const Duration(milliseconds: 150),
                                child: Icon(action.icon, color: content),
                              ),
                              if (armed) ...[
                                const SizedBox(height: 4),
                                Text(
                                  action.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.fade,
                                  softWrap: false,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: content,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
        ),
        Transform.translate(
          offset: Offset(offset, 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              color: shown ? background ?? scheme.surface : null,
            ),
            child: child,
          ),
        ),
      ],
    );
  }
}
