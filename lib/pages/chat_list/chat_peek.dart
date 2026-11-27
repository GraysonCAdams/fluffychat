// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list.dart';
import 'package:fluffychat/pages/chat_list/chat_list_selection.dart';
import 'package:fluffychat/utils/handoff_page.dart';
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
/// tap on the card opens the chat, and so does dragging it down far enough
/// or flinging it: it stretches over the whole window and the chat opens
/// under it. A tap beside it, back or Escape closes the peek. The finger that opened it, [pointer] at [pointerPosition], can
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
    with TickerProviderStateMixin {
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

  /// How far the card has grown toward the whole window, from 0 to 1. A
  /// drag down on the card pulls it; let go past [_commitAt], or flung
  /// down, it fills the window and the chat opens under it.
  late final AnimationController _expand = AnimationController(vsync: this);

  /// The share of the way to the whole window past which letting go opens
  /// the chat.
  static const double _commitAt = 0.35;

  /// A downward fling faster than this, in logical pixels a second, opens
  /// the chat however short the drag.
  static const double _commitVelocity = 700;

  /// How far the finger has dragged the card down, and how much the card
  /// can still grow: the drag stretches it with growing resistance, half
  /// way at a drag of that much (see [_expansionFor]).
  double _dragDistance = 0;
  double _room = 1;

  /// Fades the peek out over the chat it opened, once that is built.
  late final AnimationController _handoff = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
    value: 1,
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
    _expand.dispose();
    _handoff.dispose();
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

  /// The card's growth for a drag of [distance]: it follows the finger at
  /// first and resists more the further it goes, as a rubber band.
  double _expansionFor(double distance) => distance / (distance + _room);

  void _dragStarted(DragStartDetails details) {
    if (_closing) return;
    _expand.stop();
    final value = _expand.value;
    _dragDistance = value >= 1 ? 0 : value * _room / (1 - value);
  }

  void _dragged(DragUpdateDetails details) {
    if (_closing) return;
    _dragDistance = (_dragDistance + details.delta.dy).clamp(
      0,
      double.infinity,
    );
    final was = _expand.value;
    final now = _expansionFor(_dragDistance);
    // A tick where letting go starts to open the chat.
    if (was < _commitAt && now >= _commitAt) HapticFeedback.lightImpact();
    _expand.value = now;
  }

  void _dragEnded(DragEndDetails details) {
    if (_closing) return;
    final velocity = details.velocity.pixelsPerSecond.dy;
    if (_expand.value >= _commitAt || velocity >= _commitVelocity) {
      _expandIntoChat();
    } else {
      _expand.animateTo(
        0,
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOutBack,
      );
    }
  }

  /// Grows the card over the whole window, then opens the chat under it
  /// without a transition (see [PageHandoff]) and fades the peek away.
  Future<void> _expandIntoChat() async {
    if (_closing) return;
    _closing = true;
    if (ChatPeekGesture._open == this) ChatPeekGesture._open = null;
    final remaining = 1 - _expand.value;
    await _expand.animateTo(
      1,
      duration: Duration(milliseconds: (260 * remaining).round() + 1),
      curve: Curves.easeOutCubic,
    );
    if (!mounted) return;
    final peek = widget.peek;
    PageHandoff.expect();
    peek.listController.onListedChatTap(peek.room);
    // The chat's page is built in the next frame; a handoff it did not
    // take must not reach a later page.
    WidgetsBinding.instance.addPostFrameCallback((_) => PageHandoff.cancel());
    await _handoff.reverse();
    widget.onClosed();
  }

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
              Positioned.fill(
                child: LayoutBuilder(
                  builder: (context, constraints) =>
                      _layOut(context, constraints.biggest, lift, menuIn),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final fading = FadeTransition(opacity: _handoff, child: view);
    // Back closes the peek rather than leaving the chat list.
    return Router.maybeOf(context) == null
        ? fading
        : BackButtonListener(
            onBackButtonPressed: () async {
              _close();
              return true;
            },
            child: fading,
          );
  }

  /// Places the card and the menu in a window of [size]: the two centred
  /// together inside the safe area, the card as tall as it fits up to
  /// 560, and the card stretched toward the whole window by [_expand].
  Widget _layOut(
    BuildContext context,
    Size size,
    Animation<double> lift,
    Animation<double> menuIn,
  ) {
    final insets = MediaQuery.paddingOf(context);
    final area = (insets + const EdgeInsets.all(16)).deflateRect(
      Offset.zero & size,
    );
    final menuHeight = math.min(
      _entries.length * _PeekMenu.itemHeight + 2 * _PeekMenu.padding,
      area.height / 2,
    );
    var cardHeight = (area.height * 0.6).clamp(240.0, 560.0);
    if (cardHeight + _menuGap + menuHeight > area.height) {
      cardHeight = math.max(160, area.height - _menuGap - menuHeight);
    }
    final cardWidth = math.min(area.width, 560.0);
    final top =
        area.top +
        math.max(0, (area.height - cardHeight - _menuGap - menuHeight) / 2);
    final left = area.left + (area.width - cardWidth) / 2;
    final rest = Rect.fromLTWH(left, top, cardWidth, cardHeight);
    final whole = Offset.zero & size;
    _room = math.max(1, whole.height - rest.height);
    return AnimatedBuilder(
      animation: Listenable.merge([_expand, _animation]),
      builder: (context, _) {
        final expansion = _expand.value;
        // The menu is gone by the time the card is half way.
        final menuOpacity = menuIn.value * (1 - expansion * 2).clamp(0.0, 1.0);
        return Stack(
          children: [
            Positioned(
              left: left,
              top: rest.bottom + _menuGap,
              child: IgnorePointer(
                ignoring: expansion > 0,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: cardWidth,
                    maxHeight: menuHeight,
                  ),
                  child: Opacity(
                    opacity: menuOpacity,
                    child: Transform.scale(
                      scale: 0.85 + 0.15 * menuIn.value,
                      alignment: AlignmentDirectional.topStart.resolve(
                        Directionality.of(context),
                      ),
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
            Positioned.fromRect(
              rect: Rect.lerp(rest, whole, expansion)!,
              child: _Lift(
                origin: widget.peek.origin,
                progress: lift.value,
                child: Opacity(
                  opacity: _fade.value.clamp(0, 1),
                  child: GestureDetector(
                    onVerticalDragStart: _dragStarted,
                    onVerticalDragUpdate: _dragged,
                    onVerticalDragEnd: _dragEnded,
                    child: _PeekCard(
                      controller: widget.peek.listController,
                      room: widget.peek.room,
                      onOpen: _openChat,
                      expansion: expansion,
                      topInset: insets.top * expansion,
                    ),
                  ),
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  /// The space between the card and the menu.
  static const double _menuGap = 12;
}

/// The card of a peek: the chat's avatar, name and networks over its
/// newest messages, with a drag handle at the bottom edge. A tap anywhere
/// on it opens the chat. The messages do not scroll, as a drag down on the
/// card stretches it into the chat.
class _PeekCard extends StatelessWidget {
  final ChatListController controller;
  final Room room;
  final VoidCallback onOpen;

  /// How far the card has grown toward the whole window: its corners
  /// square off and the handle fades as it does.
  final double expansion;

  /// Space above the header, so that grown over the status bar the header
  /// sits where the chat's app bar will.
  final double topInset;

  const _PeekCard({
    required this.controller,
    required this.room,
    required this.onOpen,
    required this.expansion,
    required this.topInset,
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
            borderRadius: BorderRadius.circular(28 * (1 - expansion)),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ExcludeSemantics(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(16, 12 + topInset, 12, 12),
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
                  scrollable: false,
                ),
              ),
              // Material's drag handle, as sheets have, telling that the
              // card pulls down.
              Opacity(
                opacity: 1 - expansion,
                child: SizedBox(
                  height: 20,
                  child: Center(
                    child: Container(
                      key: const ValueKey('chat-peek-handle'),
                      width: 32,
                      height: 4,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.onSurfaceVariant.withValues(
                          alpha: 0.4,
                        ),
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
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

/// The menu under a peek's card, drawn as a Material menu with an icon
/// before each entry. [hovered] is the entry under a sliding finger.
class _PeekMenu extends StatelessWidget {
  /// The height of an entry and the space above and below them.
  static const double itemHeight = 48;
  static const double padding = 8;

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
            padding: const EdgeInsets.symmetric(vertical: padding),
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
        height: _PeekMenu.itemHeight,
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
