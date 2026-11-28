// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:collection/collection.dart' show IterableExtension;
import 'package:fluffychat/utils/merged_contacts/routed_event.dart';
import 'package:fluffychat/utils/merged_contacts/send_router.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/future_loading_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

// Reaction motion follows the Material 3 easing and duration tokens
// (m3.material.io/styles/motion/easing-and-duration): what appears or grows
// takes medium2 (300ms), what leaves takes short4 (200ms) with emphasized
// accelerate. A CurvedAnimation applies its reverseCurve to the controller
// value as it runs from 1 back to 0, so an exit that starts slowly and
// leaves at full speed is the flipped accelerate curve.
const Duration _enterDuration = Durations.medium2;
const Duration _exitDuration = Durations.short4;
final Curve _exitCurve = Easing.emphasizedAccelerate.flipped;

String? _reactionKey(Event event) => event.content
    .tryGetMap<String, Object?>('m.relates_to')
    ?.tryGet<String>('key');

class MessageReactions extends StatelessWidget {
  final Event event;
  final Timeline timeline;

  const MessageReactions(this.event, this.timeline, {super.key});

  /// Whether [event] has a reaction to show. The timeline keeps an empty set
  /// for a message whose last reaction was removed, so the set existing is
  /// not enough.
  static bool any(Event event, Timeline timeline) => event
      .aggregatedEvents(timeline, RelationshipTypes.reaction)
      .any((e) => _reactionKey(e) != null);

  @override
  Widget build(BuildContext context) {
    final allReactionEvents = event.aggregatedEvents(
      timeline,
      RelationshipTypes.reaction,
    );
    final reactionMap = <String, _ReactionEntry>{};
    final client = Matrix.of(context).client;

    for (final e in allReactionEvents) {
      final key = _reactionKey(e);
      if (key != null) {
        if (!reactionMap.containsKey(key)) {
          reactionMap[key] = _ReactionEntry(
            key: key,
            count: 0,
            reacted: false,
            reactors: [],
          );
        }
        reactionMap[key]!.count++;
        reactionMap[key]!.reactors!.add(e.senderFromMemoryOrFallback);
        reactionMap[key]!.reacted |= e.senderId == e.room.client.userID;
      }
    }

    final reactionList = reactionMap.values.toList();
    reactionList.sort((a, b) => b.count - a.count > 0 ? 1 : -1);
    final ownMessage = event.senderId == event.room.client.userID;
    return _ReactionChips(
      alignEnd: ownMessage,
      chips: [
        for (final r in reactionList)
          _ChipData(
            entry: r,
            onTap: () {
              if (r.reacted) {
                final evt = allReactionEvents.firstWhereOrNull(
                  (e) =>
                      e.senderId == e.room.client.userID &&
                      e.content.tryGetMap('m.relates_to')?['key'] == r.key,
                );
                if (evt != null) {
                  showFutureLoadingDialog(
                    context: context,
                    future: evt.status.isSent
                        ? evt.redactEvent
                        : evt.cancelSend,
                  );
                }
              } else {
                event
                    .roomFor(SendAction.reaction)
                    .sendReaction(event.eventId, r.key);
              }
            },
            onLongPress: () async => await _AdaptableReactorsDialog(
              client: client,
              reactionEntry: r,
            ).show(context),
          ),
      ],
    );
  }
}

class _ChipData {
  final _ReactionEntry entry;
  final void Function() onTap;
  final void Function() onLongPress;

  const _ChipData({
    required this.entry,
    required this.onTap,
    required this.onLongPress,
  });
}

/// One chip on screen and the animation that grows it in or shrinks it out.
class _ChipSlot {
  _ChipData data;
  final AnimationController controller;
  late final CurvedAnimation animation = CurvedAnimation(
    parent: controller,
    curve: Easing.emphasizedDecelerate,
    reverseCurve: _exitCurve,
  );

  /// Set while the chip's reaction is gone and the chip shrinks away.
  bool leaving = false;

  _ChipSlot(this.data, this.controller);

  void dispose() {
    animation.dispose();
    controller.dispose();
  }
}

/// The row of reaction chips. Chips shown when the row is built appear at
/// once; a reaction key added later grows in and fades up, and a key that
/// goes shrinks out from where it stood before it is dropped.
class _ReactionChips extends StatefulWidget {
  final List<_ChipData> chips;
  final bool alignEnd;

  const _ReactionChips({required this.chips, required this.alignEnd});

  @override
  State<_ReactionChips> createState() => _ReactionChipsState();
}

class _ReactionChipsState extends State<_ReactionChips>
    with TickerProviderStateMixin {
  late List<_ChipSlot> _slots = [
    for (final chip in widget.chips) _slot(chip, shown: true),
  ];

  /// Read from the last build; didUpdateWidget runs before the next one.
  bool _reduceMotion = false;

  _ChipSlot _slot(_ChipData data, {required bool shown}) => _ChipSlot(
    data,
    AnimationController(
      vsync: this,
      duration: _enterDuration,
      reverseDuration: _exitDuration,
      value: shown ? 1 : 0,
    ),
  );

  @override
  void didUpdateWidget(covariant _ReactionChips oldWidget) {
    super.didUpdateWidget(oldWidget);
    final previous = {for (final slot in _slots) slot.data.entry.key: slot};
    final next = <_ChipSlot>[];
    for (final chip in widget.chips) {
      var slot = previous.remove(chip.entry.key);
      if (slot == null) {
        slot = _slot(chip, shown: _reduceMotion);
        slot.controller.forward();
      } else {
        slot.data = chip;
        if (slot.leaving) {
          slot.leaving = false;
          slot.controller.forward();
        }
      }
      next.add(slot);
    }
    for (final slot in previous.values) {
      if (_reduceMotion) {
        slot.dispose();
        continue;
      }
      next.insert(min(_slots.indexOf(slot), next.length), slot);
      if (slot.leaving) continue;
      slot.leaving = true;
      // The future only completes when the exit runs to its end, not when
      // the reaction comes back and forward() interrupts it.
      slot.controller.reverse().then((_) {
        if (!mounted || !slot.leaving) return;
        setState(() => _slots.remove(slot));
        slot.dispose();
      });
    }
    _slots = next;
  }

  @override
  void dispose() {
    for (final slot in _slots) {
      slot.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    return Wrap(
      spacing: 4.0,
      runSpacing: 4.0,
      alignment: widget.alignEnd ? WrapAlignment.end : WrapAlignment.start,
      children: [
        for (final slot in _slots)
          SizeTransition(
            key: ValueKey(slot.data.entry.key),
            axis: Axis.horizontal,
            sizeFactor: slot.animation,
            child: ScaleTransition(
              scale: slot.animation,
              child: FadeTransition(
                opacity: slot.animation,
                child: IgnorePointer(
                  ignoring: slot.leaving,
                  child: _Reaction(
                    reactionKey: slot.data.entry.key,
                    count: slot.data.entry.count,
                    reacted: slot.data.entry.reacted,
                    onTap: slot.data.onTap,
                    onLongPress: slot.data.onLongPress,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Reaction extends StatelessWidget {
  final String reactionKey;
  final int count;
  final bool? reacted;
  final void Function()? onTap;
  final void Function()? onLongPress;

  const _Reaction({
    required this.reactionKey,
    required this.count,
    required this.reacted,
    required this.onTap,
    required this.onLongPress,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final reduceMotion = MediaQuery.disableAnimationsOf(context);

    Widget content;
    if (reactionKey.startsWith('mxc://')) {
      content = MxcImage(
        uri: Uri.parse(reactionKey),
        width: 20,
        height: 20,
        animated: false,
        isThumbnail: false,
      );
    } else {
      var renderKey = Characters(reactionKey);
      if (renderKey.length > 10) {
        renderKey = renderKey.getRange(0, 9) + Characters('…');
      }
      content = Text(renderKey.toString(), style: TextStyle(fontSize: 14));
    }
    // A pill as tall as [reactionChipHeight], ringed in the page colour so it
    // stands apart from the bubble it overlaps. The user's own reactions fill
    // with the secondary container colour.
    final borderRadius = BorderRadius.circular(reactionChipHeight / 2);
    final foreground = reacted == true
        ? theme.colorScheme.onSecondaryContainer
        : theme.colorScheme.onSurface;
    return Material(
      color: reacted == true
          ? theme.colorScheme.secondaryContainer
          : theme.colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(
        borderRadius: borderRadius,
        side: BorderSide(color: theme.colorScheme.surface, width: 2),
      ),
      child: InkWell(
        onTap: () => onTap != null ? onTap!() : null,
        onLongPress: () => onLongPress != null ? onLongPress!() : null,
        customBorder: RoundedRectangleBorder(borderRadius: borderRadius),
        child: Container(
          constraints: const BoxConstraints(
            minWidth: reactionChipHeight,
            minHeight: reactionChipHeight,
            maxHeight: reactionChipHeight,
          ),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          // The count shows from two up. A new number fades and scales in
          // over the old one while the chip resizes to fit it.
          child: AnimatedSize(
            duration: reduceMotion ? Duration.zero : _enterDuration,
            curve: Easing.emphasizedDecelerate,
            child: Row(
              mainAxisSize: .min,
              mainAxisAlignment: .center,
              children: [
                content,
                AnimatedSwitcher(
                  duration: reduceMotion ? Duration.zero : _exitDuration,
                  switchInCurve: Easing.emphasizedDecelerate,
                  switchOutCurve: _exitCurve,
                  transitionBuilder: (child, animation) => FadeTransition(
                    opacity: animation,
                    child: ScaleTransition(scale: animation, child: child),
                  ),
                  child: count > 1
                      ? Padding(
                          key: ValueKey(count),
                          padding: const EdgeInsetsDirectional.only(start: 4),
                          child: Text(
                            count.toString(),
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w500,
                              color: foreground,
                            ),
                          ),
                        )
                      : const SizedBox.shrink(),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Height of one reaction chip.
const double reactionChipHeight = 28;

/// How far a reaction chip reaches up over the bubble's bottom edge.
const double reactionChipOverlap = 8;

/// Lays a message bubble out with its reaction chips hanging off the
/// bubble's bottom corner: the chips overlap the bubble by
/// [reactionChipOverlap] and the rest of their height is added below the
/// bubble, so they never cover the next message.
///
/// With [reactionsAtEnd] the chips line up with the bubble's right edge,
/// otherwise with its left edge. Chips wider than the bubble start at the
/// bubble's edge and run past its other side, and the bubble keeps its own
/// alignment: left for another sender's message, right for the user's own.
///
/// The row opens when [reactions] turns non-null and closes when it turns
/// null: the space under the bubble grows or shrinks, revealed from the
/// top, while the chips scale and fade in or out. The chips of a row that
/// opens are new to its chip list too, which shows what it is first built
/// with at once, so the row grows them in itself. A row present when this
/// widget is first built shows at once, so opening a chat or scrolling a
/// message into view does not animate it. The bubble keeps the same place
/// in the tree either way, so it is never rebuilt from scratch when
/// reactions come or go.
///
/// [assist] is the row of data detector assist chips, which hangs
/// [assistGap] under the bubble on the bubble's own side, the corner the
/// reaction chips leave free. When the bubble is too narrow for both side
/// by side, it drops to its own line [assistGap] under the reaction chips.
/// It opens and closes the way the reaction row does.
class BubbleWithReactions extends StatefulWidget {
  final Widget bubble;
  final Widget? reactions;
  final bool reactionsAtEnd;
  final Widget? assist;

  const BubbleWithReactions({
    required this.bubble,
    required this.reactions,
    required this.reactionsAtEnd,
    this.assist,
    super.key,
  });

  /// Space between the bubble, or the reaction chips, and the assist row.
  static const double assistGap = 4;

  @override
  State<BubbleWithReactions> createState() => _BubbleWithReactionsState();
}

class _BubbleWithReactionsState extends State<BubbleWithReactions>
    with TickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: _enterDuration,
    reverseDuration: _exitDuration,
    value: widget.reactions == null ? 0 : 1,
  )..addStatusListener(_onStatus);

  late final CurvedAnimation _reveal = CurvedAnimation(
    parent: _controller,
    curve: Curves.easeInOutCubicEmphasized,
    reverseCurve: _exitCurve,
  );

  /// Scales and fades the chips with the same curves a chip added to an
  /// open row uses.
  late final CurvedAnimation _grow = CurvedAnimation(
    parent: _controller,
    curve: Easing.emphasizedDecelerate,
    reverseCurve: _exitCurve,
  );

  late final AnimationController _assistController = AnimationController(
    vsync: this,
    duration: _enterDuration,
    reverseDuration: _exitDuration,
    value: widget.assist == null ? 0 : 1,
  )..addStatusListener(_onAssistStatus);

  late final CurvedAnimation _assistReveal = CurvedAnimation(
    parent: _assistController,
    curve: Curves.easeInOutCubicEmphasized,
    reverseCurve: _exitCurve,
  );

  /// The chips on screen, kept while the row closes.
  late Widget? _reactions = widget.reactions;

  /// The assist row on screen, kept while it closes.
  late Widget? _assist = widget.assist;

  /// Read from the last build; didUpdateWidget runs before the next one.
  bool _reduceMotion = false;

  void _onStatus(AnimationStatus status) {
    if (status.isDismissed && widget.reactions == null && mounted) {
      setState(() => _reactions = null);
    }
  }

  void _onAssistStatus(AnimationStatus status) {
    if (status.isDismissed && widget.assist == null && mounted) {
      setState(() => _assist = null);
    }
  }

  @override
  void didUpdateWidget(covariant BubbleWithReactions oldWidget) {
    super.didUpdateWidget(oldWidget);
    final reactions = widget.reactions;
    if (reactions != null) {
      _reactions = reactions;
      if (_reduceMotion) {
        _controller.value = 1;
      } else {
        _controller.forward();
      }
    } else if (oldWidget.reactions != null) {
      if (_reduceMotion) {
        _controller.value = 0;
        _reactions = null;
      } else {
        _controller.reverse();
      }
    }
    final assist = widget.assist;
    if (assist != null) {
      _assist = assist;
      if (_reduceMotion) {
        _assistController.value = 1;
      } else {
        _assistController.forward();
      }
    } else if (oldWidget.assist != null) {
      if (_reduceMotion) {
        _assistController.value = 0;
        _assist = null;
      } else {
        _assistController.reverse();
      }
    }
  }

  @override
  void dispose() {
    _reveal.dispose();
    _grow.dispose();
    _controller.dispose();
    _assistReveal.dispose();
    _assistController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    _reduceMotion = MediaQuery.disableAnimationsOf(context);
    final reactions = _reactions;
    final assist = _assist;
    return _BubbleWithReactionsLayout(
      reactionsAtEnd: widget.reactionsAtEnd,
      reveal: _reveal,
      assistReveal: _assistReveal,
      children: [
        widget.bubble,
        reactions == null
            ? const SizedBox.shrink()
            : ScaleTransition(
                scale: _grow,
                child: FadeTransition(opacity: _grow, child: reactions),
              ),
        assist == null
            ? const SizedBox.shrink()
            : FadeTransition(opacity: _assistReveal, child: assist),
      ],
    );
  }
}

class _BubbleWithReactionsLayout extends MultiChildRenderObjectWidget {
  final bool reactionsAtEnd;
  final Animation<double> reveal;
  final Animation<double> assistReveal;

  const _BubbleWithReactionsLayout({
    required this.reactionsAtEnd,
    required this.reveal,
    required this.assistReveal,
    required super.children,
  });

  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderBubbleWithReactions(reactionsAtEnd, reveal, assistReveal);

  @override
  void updateRenderObject(
    BuildContext context,
    _RenderBubbleWithReactions renderObject,
  ) => renderObject
    ..reactionsAtEnd = reactionsAtEnd
    ..reveal = reveal
    ..assistReveal = assistReveal;
}

class _BubbleWithReactionsParentData
    extends ContainerBoxParentData<RenderBox> {}

class _RenderBubbleWithReactions extends RenderBox
    with
        ContainerRenderObjectMixin<RenderBox, _BubbleWithReactionsParentData>,
        RenderBoxContainerDefaultsMixin<
          RenderBox,
          _BubbleWithReactionsParentData
        > {
  _RenderBubbleWithReactions(
    this._reactionsAtEnd,
    this._reveal,
    this._assistReveal,
  );

  bool _reactionsAtEnd;
  set reactionsAtEnd(bool value) {
    if (value == _reactionsAtEnd) return;
    _reactionsAtEnd = value;
    markNeedsLayout();
  }

  /// How much of the space the chips add under the bubble is open, from 0
  /// to 1. Below 1 the chips are clipped to the row's bottom edge.
  Animation<double> _reveal;
  set reveal(Animation<double> value) {
    if (value == _reveal) return;
    if (attached) {
      _reveal.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _reveal = value;
    markNeedsLayout();
  }

  /// How much of the space the assist row adds is open, from 0 to 1.
  Animation<double> _assistReveal;
  set assistReveal(Animation<double> value) {
    if (value == _assistReveal) return;
    if (attached) {
      _assistReveal.removeListener(markNeedsLayout);
      value.addListener(markNeedsLayout);
    }
    _assistReveal = value;
    markNeedsLayout();
  }

  final _clipLayer = LayerHandle<ClipRectLayer>();

  @override
  void attach(PipelineOwner owner) {
    super.attach(owner);
    _reveal.addListener(markNeedsLayout);
    _assistReveal.addListener(markNeedsLayout);
  }

  @override
  void detach() {
    _reveal.removeListener(markNeedsLayout);
    _assistReveal.removeListener(markNeedsLayout);
    super.detach();
  }

  @override
  void dispose() {
    _clipLayer.layer = null;
    super.dispose();
  }

  @override
  void setupParentData(RenderBox child) {
    if (child.parentData is! _BubbleWithReactionsParentData) {
      child.parentData = _BubbleWithReactionsParentData();
    }
  }

  RenderBox get _bubble => firstChild!;
  RenderBox get _reactions => childAfter(_bubble)!;
  RenderBox get _assist => lastChild!;

  /// Where the assist row's top edge goes, and whether it shares the band
  /// under the bubble with the reaction chips.
  static (double top, bool beside) _assistPlace(
    Size bubble,
    Size reactions,
    Size assist,
  ) {
    const gap = BubbleWithReactions.assistGap;
    if (reactions.height <= 0) return (bubble.height + gap, false);
    final beside = assist.width + 2 * gap + reactions.width <= bubble.width;
    if (beside) return (bubble.height + gap, true);
    final overlap = min(reactionChipOverlap, bubble.height);
    return (bubble.height - overlap + reactions.height + gap, false);
  }

  double _height(Size bubble, Size reactions, Size assist) {
    final overlap = min(reactionChipOverlap, bubble.height);
    final withReactions =
        bubble.height +
        max(0.0, reactions.height - overlap) * _reveal.value.clamp(0.0, 1.0);
    if (assist.height <= 0) return withReactions;
    final (top, _) = _assistPlace(bubble, reactions, assist);
    final assistBottom = top + assist.height;
    return withReactions +
        max(0.0, assistBottom - withReactions) *
            _assistReveal.value.clamp(0.0, 1.0);
  }

  @override
  double computeMinIntrinsicWidth(double height) => max(
    _bubble.getMinIntrinsicWidth(height),
    max(
      _reactions.getMinIntrinsicWidth(double.infinity),
      _assist.getMinIntrinsicWidth(double.infinity),
    ),
  );

  @override
  double computeMaxIntrinsicWidth(double height) => max(
    _bubble.getMaxIntrinsicWidth(height),
    max(
      _reactions.getMaxIntrinsicWidth(double.infinity),
      _assist.getMaxIntrinsicWidth(double.infinity),
    ),
  );

  @override
  double computeMinIntrinsicHeight(double width) => _height(
    Size(width, _bubble.getMinIntrinsicHeight(width)),
    Size(0, _reactions.getMinIntrinsicHeight(width)),
    Size(0, _assist.getMinIntrinsicHeight(width)),
  );

  @override
  double computeMaxIntrinsicHeight(double width) => _height(
    Size(width, _bubble.getMaxIntrinsicHeight(width)),
    Size(0, _reactions.getMaxIntrinsicHeight(width)),
    Size(0, _assist.getMaxIntrinsicHeight(width)),
  );

  @override
  void performLayout() {
    final bubble = _bubble;
    final reactions = _reactions;
    final assist = _assist;
    final loose = constraints.loosen();
    bubble.layout(loose, parentUsesSize: true);
    reactions.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    assist.layout(
      BoxConstraints(maxWidth: constraints.maxWidth),
      parentUsesSize: true,
    );
    final double width = max(
      bubble.size.width,
      max(reactions.size.width, assist.size.width),
    );
    final overlap = min(reactionChipOverlap, bubble.size.height);
    size = constraints.constrain(
      Size(width, _height(bubble.size, reactions.size, assist.size)),
    );

    // The bubble keeps the side it would have without reactions: another
    // sender's (chips at the end) on the left, the user's own on the right.
    final bubbleX = _reactionsAtEnd ? 0.0 : size.width - bubble.size.width;
    final reactionsX = _reactionsAtEnd
        ? max(0.0, bubbleX + bubble.size.width - reactions.size.width)
        : min(bubbleX, size.width - reactions.size.width);
    // The assist row takes the bubble's own side, the corner the reaction
    // chips leave free.
    final assistX = _reactionsAtEnd
        ? bubbleX
        : max(0.0, bubbleX + bubble.size.width - assist.size.width);
    (bubble.parentData! as _BubbleWithReactionsParentData).offset = Offset(
      bubbleX,
      0,
    );
    (reactions.parentData! as _BubbleWithReactionsParentData).offset = Offset(
      reactionsX,
      bubble.size.height - overlap,
    );
    (assist.parentData! as _BubbleWithReactionsParentData).offset = Offset(
      assistX,
      _assistPlace(bubble.size, reactions.size, assist.size).$1,
    );
  }

  @override
  double? computeDistanceToActualBaseline(TextBaseline baseline) =>
      defaultComputeDistanceToFirstActualBaseline(baseline);

  @override
  void paint(PaintingContext context, Offset offset) {
    var bottom = 0.0;
    for (final child in [_reactions, _assist]) {
      bottom = max(
        bottom,
        (child.parentData! as _BubbleWithReactionsParentData).offset.dy +
            child.size.height,
      );
    }
    if (bottom <= size.height) {
      _clipLayer.layer = null;
      defaultPaint(context, offset);
      return;
    }
    _clipLayer.layer = context.pushClipRect(
      needsCompositing,
      offset,
      Offset.zero & size,
      defaultPaint,
      oldLayer: _clipLayer.layer,
    );
  }

  @override
  bool hitTestChildren(BoxHitTestResult result, {required Offset position}) =>
      defaultHitTestChildren(result, position: position);
}

class _ReactionEntry {
  String key;
  int count;
  bool reacted;
  List<User>? reactors;

  _ReactionEntry({
    required this.key,
    required this.count,
    required this.reacted,
    this.reactors,
  });
}

class _AdaptableReactorsDialog extends StatelessWidget {
  final Client? client;
  final _ReactionEntry? reactionEntry;

  const _AdaptableReactorsDialog({this.client, this.reactionEntry});

  Future<bool?> show(BuildContext context) => showDialog(
    context: context,
    builder: (context) => this,
    barrierDismissible: true,
    useRootNavigator: false,
  );

  @override
  Widget build(BuildContext context) {
    final body = SingleChildScrollView(
      child: Wrap(
        spacing: 8.0,
        runSpacing: 4.0,
        alignment: WrapAlignment.center,
        children: <Widget>[
          for (final reactor in reactionEntry!.reactors!)
            Chip(
              avatar: Avatar(
                mxContent: reactor.avatarUrl,
                name: reactor.displayName,
                client: client,
                presenceUserId: reactor.stateKey,
              ),
              label: Text(reactor.displayName!),
            ),
        ],
      ),
    );

    final title = Center(child: Text(reactionEntry!.key));

    return AlertDialog(title: title, content: body);
  }
}
