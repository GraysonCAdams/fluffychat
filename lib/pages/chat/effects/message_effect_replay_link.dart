// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/played_message_effects.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The line under a message sent with an effect: the small "Replay" link
/// iMessage puts there, a replay arrow and the word in the theme's primary
/// colour, right under the bubble. Tapping it plays the effect again
/// exactly as the message menu's "Replay effect" does (see
/// [replayMessageEffect]).
///
/// The message's status goes on the same line: when the message's time is
/// shown (its bubble was tapped, or it is selected) the line reads
/// "time · arrow", the time sliding in from the bubble's side while the
/// word folds away into the arrow, and back; the rest of the status (the
/// network, the edit mark, the delivery state) follows the arrow.
///
/// The link shows once the effect has played, for every effect that plays
/// by itself. Invisible ink has nothing to replay, since the ink covers the
/// bubble again by itself, and under reduced motion nothing plays, so
/// neither gets it; the message then has its usual [statusLine], if any.
///
/// The link looks small but takes taps over a full 48dp target that runs
/// down from the bubble's edge, so it never covers the bubble. A touch,
/// hover or focus lights only a slim pill around the arrow and the word,
/// as Material's state layer.
class MessageEffectReplayLink extends StatefulWidget {
  final Event event;

  /// Whether the message is the user's own, whose line sits at the end.
  final bool ownMessage;

  /// How far the bubble sits in from the start of the row.
  final double indent;

  /// The message's time while it is shown, else null.
  final String? time;

  /// The rest of the message's status, after the time.
  final List<Widget> status;

  /// The message's own status line, for when there is no link to show.
  final Widget? statusLine;

  /// The style of the time, the status line's.
  final TextStyle? timeStyle;

  /// Shadows for the label, to keep it legible over a wallpaper.
  final List<Shadow>? shadows;

  const MessageEffectReplayLink({
    required this.event,
    this.ownMessage = false,
    this.indent = 0,
    this.time,
    this.status = const [],
    this.statusLine,
    this.timeStyle,
    this.shadows,
    super.key,
  });

  /// The least height and width of the link's touch target.
  static const height = 48.0;

  /// How long the time takes to come in or go.
  static const duration = Duration(milliseconds: 220);

  @override
  State<MessageEffectReplayLink> createState() =>
      _MessageEffectReplayLinkState();
}

class _MessageEffectReplayLinkState extends State<MessageEffectReplayLink> {
  /// Whether the link is pressed, hovered or focused, which the pill shows.
  final _states = WidgetStatesController();

  @override
  void initState() {
    super.initState();
    PlayedMessageEffects.changes.addListener(_onPlayed);
  }

  @override
  void dispose() {
    PlayedMessageEffects.changes.removeListener(_onPlayed);
    _states.dispose();
    super.dispose();
  }

  /// Material's state layer over [color]: its opacity for the strongest of
  /// [states].
  static Color _stateLayer(Color color, Set<WidgetState> states) {
    if (states.contains(WidgetState.pressed) ||
        states.contains(WidgetState.focused)) {
      return color.withValues(alpha: 0.10);
    }
    if (states.contains(WidgetState.hovered)) {
      return color.withValues(alpha: 0.08);
    }
    return color.withValues(alpha: 0);
  }

  /// A message is marked played as its bubble is first built, which may be
  /// in the middle of a build: the link then catches up after the frame.
  void _onPlayed() {
    if (!mounted) return;
    if (SchedulerBinding.instance.schedulerPhase ==
        SchedulerPhase.persistentCallbacks) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
    } else {
      setState(() {});
    }
  }

  /// The time shown last, kept while it goes away.
  String? _lastTime;

  @override
  Widget build(BuildContext context) {
    final effect = effectOf(widget.event);
    if (effect == null ||
        effect == MessageEffect.invisibleInk ||
        MediaQuery.disableAnimationsOf(context) ||
        PlayedMessageEffects.shouldAutoPlay(widget.event)) {
      return widget.statusLine ?? const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final color = theme.colorScheme.primary;
    final own = widget.ownMessage;
    if (widget.time case final time?) _lastTime = time;
    void replay() => replayMessageEffect(widget.event);

    // The arrow and the word, which folds away by [folded] (0 to 1).
    Widget link(double folded) => _TouchTarget(
      child: Semantics(
        button: true,
        label: l10n.replayNamedEffect(effect.localizedName(l10n)),
        onTap: replay,
        excludeSemantics: true,
        // The whole target takes the tap; the ink itself stays clear, and
        // the pill shows the state instead.
        child: InkWell(
          key: const ValueKey('message_effect_replay'),
          onTap: replay,
          statesController: _states,
          splashFactory: NoSplash.splashFactory,
          overlayColor: const WidgetStatePropertyAll(Colors.transparent),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              minHeight: MessageEffectReplayLink.height,
            ),
            child: Align(
              alignment: Alignment.topCenter,
              widthFactor: 1,
              heightFactor: 1,
              child: ValueListenableBuilder<Set<WidgetState>>(
                valueListenable: _states,
                builder: (context, states, child) => DecoratedBox(
                  key: const ValueKey('message_effect_replay_pill'),
                  decoration: ShapeDecoration(
                    shape: const StadiumBorder(),
                    color: _stateLayer(color, states),
                  ),
                  child: child,
                ),
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 6,
                    vertical: 1,
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.replay,
                        size: 16,
                        color: color,
                        shadows: widget.shadows,
                      ),
                      if (folded < 1)
                        ClipRect(
                          child: Align(
                            alignment: Alignment.centerLeft,
                            widthFactor: 1 - folded,
                            child: Opacity(
                              opacity: 1 - folded,
                              child: Padding(
                                padding: const EdgeInsets.only(left: 2),
                                child: Text(
                                  l10n.replay,
                                  style: theme.textTheme.labelMedium?.copyWith(
                                    color: color,
                                    fontWeight: FontWeight.w600,
                                    shadows: widget.shadows,
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    // The time and its dot, coming in by [shown] (0 to 1) from the side
    // the bubble is on.
    Widget time(double shown) => ClipRect(
      child: Align(
        alignment: own ? Alignment.centerRight : Alignment.centerLeft,
        widthFactor: shown,
        child: Opacity(
          opacity: shown,
          child: Padding(
            padding: const EdgeInsets.only(top: 1),
            child: Text('${_lastTime ?? ''} \u00b7', style: widget.timeStyle),
          ),
        ),
      ),
    );

    return Padding(
      // The arrow lines up with the text inside the bubble.
      padding: EdgeInsets.only(left: 10 + widget.indent, right: 10),
      child: TweenAnimationBuilder<double>(
        tween: Tween(end: widget.time == null ? 0 : 1),
        duration: MessageEffectReplayLink.duration,
        curve: Easing.standard,
        // One row the whole width of the message, so the link's touch
        // target can reach past the arrow on either side.
        builder: (context, shown, _) => Row(
          mainAxisAlignment: own
              ? MainAxisAlignment.end
              : MainAxisAlignment.start,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (shown > 0)
              KeyedSubtree(key: const ValueKey('time'), child: time(shown)),
            KeyedSubtree(key: const ValueKey('link'), child: link(shown)),
            if (widget.status.isNotEmpty) const SizedBox(width: 2),
            for (final item in widget.status)
              Padding(padding: const EdgeInsets.only(top: 1), child: item),
          ],
        ),
      ),
    );
  }
}

/// Takes taps over at least [MessageEffectReplayLink.height] across, around
/// its [child], without taking that room in the layout: a tap beside the
/// child is passed to it as if on its middle, as Material's own touch
/// targets do. The row it sits in must reach that far: a parent that is
/// only as wide as the child turns the taps beside it away.
class _TouchTarget extends SingleChildRenderObjectWidget {
  const _TouchTarget({required super.child});

  @override
  RenderObject createRenderObject(BuildContext context) => _RenderTouchTarget();
}

class _RenderTouchTarget extends RenderProxyBox {
  @override
  bool hitTest(BoxHitTestResult result, {required Offset position}) {
    final width = size.width < MessageEffectReplayLink.height
        ? MessageEffectReplayLink.height
        : size.width;
    final target = Rect.fromCenter(
      center: size.center(Offset.zero),
      width: width,
      height: size.height,
    );
    if (!target.contains(position)) return false;
    final inside = (Offset.zero & size).contains(position)
        ? position
        : Offset(size.width / 2, position.dy);
    return super.hitTest(result, position: inside);
  }
}
