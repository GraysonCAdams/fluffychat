// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:ui' as ui;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/merged_timeline.dart';
import 'package:fluffychat/utils/merged_contacts/networks.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:fluffychat/widgets/read_only_conversation.dart';
import 'package:flutter/gestures.dart' show kTouchSlop;
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Opens the peek of [room]'s row: the chat's recent messages in a card
/// over the blurred list, with the chat's menu (see [chatMenuEntries])
/// under it. A touch long press on a row opens it, see `ChatListItem`.
///
/// The card grows out of the row, whose [rowContext] gives its place. A
/// tap on the card opens the chat; a tap beside it, back or Escape closes
/// the peek. The finger that opened it, [pointer] at [pointerPosition], can
/// slide onto an entry of the menu and lift to pick it, or lift anywhere
/// else and tap later.
///
/// Peeking reads only what is cached and moves no read marker, so an
/// unread chat stays unread until it is opened.
Future<void> showChatPeek(
  ChatListController controller,
  Room room,
  BuildContext rowContext, {
  int? pointer,
  Offset? pointerPosition,
}) {
  final box = rowContext.findRenderObject() as RenderBox?;
  final origin = box == null || !box.hasSize
      ? null
      : box.localToGlobal(Offset.zero) & box.size;
  final closed = Completer<void>();
  late final OverlayEntry entry;
  entry = OverlayEntry(
    builder: (context) => _ChatPeekView(
      peek: _ChatPeek(
        listController: controller,
        room: room,
        origin: origin,
        pointer: pointer,
        pointerPosition: pointerPosition,
        dismissLabel: L10n.of(rowContext).close,
      ),
      onClosed: () {
        entry.remove();
        entry.dispose();
        closed.complete();
      },
    ),
  );
  // An overlay entry rather than a route: pushing a route cancels the
  // pointers that are down, and the finger that opened the peek has to
  // stay down to slide onto the menu.
  Overlay.of(rowContext, rootOverlay: true).insert(entry);
  return closed.future;
}

/// Passes the moves of the finger that opened a peek on to it. The row the
/// finger went down on keeps receiving them, as pointers stay with what
/// they first touched, so the row hands them over.
abstract final class ChatPeekGesture {
  static _ChatPeekViewState? _open;

  static void move(PointerEvent event) =>
      _open?._fingerMoved(event.pointer, event.position);

  static void up(PointerEvent event) =>
      _open?._fingerLifted(event.pointer, event.position);

  static void cancel(PointerEvent event) =>
      _open?._fingerCancelled(event.pointer);
}

/// What a peek shows and where it came from.
class _ChatPeek {
  final ChatListController listController;
  final Room room;

  /// The row, in global coordinates, that the card grows out of.
  final Rect? origin;
  final int? pointer;
  final Offset? pointerPosition;
  final String dismissLabel;

  const _ChatPeek({
    required this.listController,
    required this.room,
    required this.origin,
    required this.pointer,
    required this.pointerPosition,
    required this.dismissLabel,
  });
}

class _ChatPeekView extends StatefulWidget {
  final _ChatPeek peek;

  /// Called once the closing animation has run.
  final VoidCallback onClosed;

  const _ChatPeekView({required this.peek, required this.onClosed});

  @override
  State<_ChatPeekView> createState() => _ChatPeekViewState();
}

class _ChatPeekViewState extends State<_ChatPeekView>
    with SingleTickerProviderStateMixin {
  /// Lifts the card out of the row and blurs the list behind, for about as
  /// long as iOS's context menus take.
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 320),
    reverseDuration: const Duration(milliseconds: 200),
  )..forward();

  /// The blur and scrim behind, and the card's opacity.
  late final CurvedAnimation _fade = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutCubic,
    reverseCurve: Curves.easeInCubic,
  );

  /// The card's way from the row: it overshoots its place a little and
  /// settles, as iOS's lift springs.
  late final CurvedAnimation _lift = CurvedAnimation(
    parent: _animation,
    curve: Curves.easeOutBack,
    reverseCurve: Curves.easeInCubic,
  );

  /// The menu, which follows the card.
  late final CurvedAnimation _menuIn = CurvedAnimation(
    parent: _animation,
    curve: const Interval(0.25, 1, curve: Curves.easeOutCubic),
    reverseCurve: Curves.easeInCubic,
  );

  /// The menu as it was when the peek opened.
  late final List<ChatMenuEntry> _entries = chatMenuEntries(
    widget.peek.listController,
    widget.peek.room,
  );
  late final List<GlobalKey> _entryKeys = [
    for (final _ in _entries) GlobalKey(),
  ];

  /// The finger that opened the peek while it is still down, and where it
  /// was when the peek opened.
  int? _pointer;
  Offset? _start;

  /// Whether that finger has moved far enough to pick from the menu by
  /// sliding: lifting it where it went down picks nothing, even with an
  /// entry under it.
  bool _sliding = false;

  /// The entry under the sliding finger.
  int? _hovered;

  bool _closing = false;

  final FocusNode _focus = FocusNode(debugLabel: 'chat peek');

  @override
  void initState() {
    super.initState();
    _pointer = widget.peek.pointer;
    _start = widget.peek.pointerPosition;
    ChatPeekGesture._open = this;
  }

  @override
  void dispose() {
    if (ChatPeekGesture._open == this) ChatPeekGesture._open = null;
    _fade.dispose();
    _lift.dispose();
    _menuIn.dispose();
    _animation.dispose();
    _focus.dispose();
    super.dispose();
  }

  int? _entryAt(Offset position) {
    for (var i = 0; i < _entryKeys.length; i++) {
      final box = _entryKeys[i].currentContext?.findRenderObject();
      if (box is! RenderBox || !box.hasSize) continue;
      final rect = box.localToGlobal(Offset.zero) & box.size;
      if (rect.contains(position)) return i;
    }
    return null;
  }

  void _fingerMoved(int pointer, Offset position) {
    if (pointer != _pointer || _closing) return;
    final start = _start ??= position;
    if (!_sliding && (position - start).distance < kTouchSlop) return;
    _sliding = true;
    final hovered = _entryAt(position);
    if (hovered == _hovered) return;
    // A tick for each entry the finger reaches, as a picker's detents.
    if (hovered != null) HapticFeedback.selectionClick();
    setState(() => _hovered = hovered);
  }

  void _fingerLifted(int pointer, Offset position) {
    if (pointer != _pointer) return;
    _pointer = null;
    final picked = _sliding ? _entryAt(position) : null;
    if (picked != null) {
      _pick(_entries[picked]);
    } else if (_hovered != null) {
      setState(() => _hovered = null);
    }
  }

  void _fingerCancelled(int pointer) {
    if (pointer != _pointer) return;
    _pointer = null;
    if (_hovered != null) setState(() => _hovered = null);
  }

  /// Closes the peek, then runs [then] while the peek fades out.
  void _close([VoidCallback? then]) {
    if (_closing) return;
    _closing = true;
    if (ChatPeekGesture._open == this) ChatPeekGesture._open = null;
    _animation.reverse().whenComplete(widget.onClosed);
    then?.call();
  }

  void _pick(ChatMenuEntry entry) => _close(entry.onSelected);

  void _openChat() {
    final peek = widget.peek;
    _close(() => peek.listController.onListedChatTap(peek.room));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final animation = _fade;
    final lift = _lift;
    final menuIn = _menuIn;
    final view = BlockSemantics(
      child: CallbackShortcuts(
        bindings: {const SingleActivator(LogicalKeyboardKey.escape): _close},
        child: Focus(
          focusNode: _focus,
          autofocus: true,
          child: Stack(
            children: [
              Positioned.fill(
                child: Semantics(
                  label: widget.peek.dismissLabel,
                  button: true,
                  onTap: _close,
                  child: GestureDetector(
                    behavior: HitTestBehavior.opaque,
                    onTap: _close,
                    child: AnimatedBuilder(
                      animation: animation,
                      builder: (context, _) => BackdropFilter(
                        filter: ui.ImageFilter.blur(
                          sigmaX: 16 * animation.value,
                          sigmaY: 16 * animation.value,
                        ),
                        child: ColoredBox(
                          color: theme.colorScheme.scrim.withValues(
                            alpha: 0.32 * animation.value,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              SafeArea(
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final cardHeight = (constraints.maxHeight * 0.6).clamp(
                        240.0,
                        560.0,
                      );
                      return Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Flexible(
                            child: Center(
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  maxWidth: 560,
                                  maxHeight: cardHeight,
                                ),
                                child: AnimatedBuilder(
                                  animation: lift,
                                  builder: (context, child) => _Lift(
                                    origin: widget.peek.origin,
                                    progress: lift.value,
                                    child: Opacity(
                                      opacity: animation.value.clamp(0, 1),
                                      child: child,
                                    ),
                                  ),
                                  child: SizedBox(
                                    height: cardHeight,
                                    child: _PeekCard(
                                      controller: widget.peek.listController,
                                      room: widget.peek.room,
                                      onOpen: _openChat,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 560),
                              child: Align(
                                alignment: AlignmentDirectional.centerStart,
                                child: FadeTransition(
                                  opacity: menuIn,
                                  child: ScaleTransition(
                                    scale: Tween(
                                      begin: 0.85,
                                      end: 1.0,
                                    ).animate(menuIn),
                                    alignment: AlignmentDirectional.topStart
                                        .resolve(Directionality.of(context)),
                                    child: _PeekMenu(
                                      entries: _entries,
                                      entryKeys: _entryKeys,
                                      hovered: _hovered,
                                      onPick: _pick,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    // Back closes the peek rather than leaving the chat list.
    return Router.maybeOf(context) == null
        ? view
        : BackButtonListener(
            onBackButtonPressed: () async {
              _close();
              return true;
            },
            child: view,
          );
  }
}

/// The card of a peek: the chat's avatar, name and networks over its
/// recent messages. A tap anywhere on it opens the chat; the messages
/// scroll.
class _PeekCard extends StatelessWidget {
  final ChatListController controller;
  final Room room;
  final VoidCallback onOpen;

  const _PeekCard({
    required this.controller,
    required this.room,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final locals = MatrixLocals(l10n);
    final contact = controller.mergedContactFor(room);
    final name =
        contact?.displayName(locals) ?? room.getLocalizedDisplayname(locals);
    final avatarRoom = contact?.sendViaRoom ?? room;
    final spaces = spacesByChild(room.client);
    final networks = {
      for (final room in contact?.rooms ?? [room])
        if (spaces[room.id] case final space?)
          space.getLocalizedDisplayname(locals),
    };
    return Semantics(
      button: true,
      label: name,
      hint: l10n.open,
      onTap: onOpen,
      child: GestureDetector(
        onTap: onOpen,
        child: Material(
          key: const ValueKey('chat-peek-card'),
          color: theme.scaffoldBackgroundColor,
          elevation: 2,
          shadowColor: theme.colorScheme.shadow,
          clipBehavior: Clip.antiAlias,
          // Material's extra-large corner, as dialogs and sheets have.
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(28),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 12, 12),
                  child: Row(
                    children: [
                      if (GroupAvatar.shows(avatarRoom))
                        GroupAvatar(room: avatarRoom, name: name, size: 40)
                      else
                        Avatar(
                          mxContent: contact?.avatar ?? room.avatar,
                          name: name,
                          size: 40,
                          borderRadius: room.isSpace
                              ? BorderRadius.circular(
                                  AppConfig.spaceBorderRadius,
                                )
                              : null,
                        ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              name,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.titleMedium?.copyWith(
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            if (networks.isNotEmpty)
                              Text(
                                networks.join(' · '),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                              ),
                          ],
                        ),
                      ),
                      Icon(
                        Icons.open_in_full,
                        size: 20,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ],
                  ),
                ),
              ),
              Divider(height: 1, color: theme.colorScheme.outlineVariant),
              Expanded(
                child: ReadOnlyConversation(
                  key: const ValueKey('chat-peek-history'),
                  // Only what is cached: a peek asks the server for nothing.
                  open: (onUpdate) => contact == null
                      ? room.getTimeline(onUpdate: onUpdate)
                      : MergedTimeline.open(contact.rooms, onUpdate: onUpdate),
                  failureLog: 'Unable to read the chat for its peek',
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// The menu under a peek's card, drawn as a Material menu with an icon
/// before each entry. [hovered] is the entry under a sliding finger.
class _PeekMenu extends StatelessWidget {
  final List<ChatMenuEntry> entries;
  final List<GlobalKey> entryKeys;
  final int? hovered;
  final void Function(ChatMenuEntry entry) onPick;

  const _PeekMenu({
    required this.entries,
    required this.entryKeys,
    required this.hovered,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      key: const ValueKey('chat-peek-menu'),
      color: theme.colorScheme.surfaceContainer,
      elevation: 2,
      shadowColor: theme.colorScheme.shadow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: ConstrainedBox(
        constraints: const BoxConstraints(minWidth: 200, maxWidth: 280),
        child: IntrinsicWidth(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < entries.length; i++)
                  _PeekMenuItem(
                    key: entryKeys[i],
                    entry: entries[i],
                    hovered: hovered == i,
                    onTap: () => onPick(entries[i]),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _PeekMenuItem extends StatelessWidget {
  final ChatMenuEntry entry;
  final bool hovered;
  final VoidCallback onTap;

  const _PeekMenuItem({
    required this.entry,
    required this.hovered,
    required this.onTap,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = entry.destructive
        ? theme.colorScheme.error
        : theme.colorScheme.onSurface;
    return InkWell(
      onTap: onTap,
      child: Ink(
        // Material's pressed state layer while a finger slides over it.
        color: hovered ? color.withValues(alpha: 0.1) : null,
        height: 48,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        child: Row(
          children: [
            Icon(
              entry.icon,
              size: 24,
              color: entry.destructive
                  ? color
                  : theme.colorScheme.onSurfaceVariant,
            ),
            const SizedBox(width: 12),
            Flexible(
              child: Text(
                entry.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.bodyLarge?.copyWith(color: color),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }
}

/// Draws its child moved and scaled from [origin] (the row, in global
/// coordinates) to its own place as [progress] goes from 0 to 1. Layout
/// and hit testing use its own place.
class _Lift extends SingleChildRenderObjectWidget {
  final Rect? origin;
  final double progress;

  const _Lift({required this.origin, required this.progress, super.child});

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderLift(origin, progress);

  @override
  void updateRenderObject(BuildContext context, _RenderLift renderObject) =>
      renderObject
        ..origin = origin
        ..progress = progress;
}

class _RenderLift extends RenderProxyBox {
  _RenderLift(this._origin, this._progress);

  Rect? _origin;
  set origin(Rect? value) {
    if (value == _origin) return;
    _origin = value;
    markNeedsPaint();
  }

  double _progress;
  set progress(double value) {
    if (value == _progress) return;
    _progress = value;
    markNeedsPaint();
  }

  /// How far the card starts below its full size.
  static const double _startScale = 0.92;

  Matrix4 _transform() {
    final origin = _origin;
    final t = _progress;
    if (origin == null || t >= 1) return Matrix4.identity();
    final own = localToGlobal(Offset.zero) & size;
    final shift = (origin.center - own.center) * (1 - t);
    final scale = ui.lerpDouble(_startScale, 1, t)!;
    final center = size.center(Offset.zero);
    return Matrix4.identity()
      ..translateByDouble(shift.dx + center.dx, shift.dy + center.dy, 0, 1)
      ..scaleByDouble(scale, scale, 1, 1)
      ..translateByDouble(-center.dx, -center.dy, 0, 1);
  }

  @override
  void paint(PaintingContext context, Offset offset) {
    final child = this.child;
    if (child == null) return;
    if (_origin == null || _progress >= 1) {
      layer = null;
      context.paintChild(child, offset);
      return;
    }
    layer = context.pushTransform(
      needsCompositing,
      offset,
      _transform(),
      (context, offset) => context.paintChild(child, offset),
      oldLayer: layer is TransformLayer ? layer as TransformLayer? : null,
    );
  }

  @override
  void applyPaintTransform(RenderBox child, Matrix4 transform) =>
      transform.multiply(_transform());
}
