// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/played_message_effects.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The small "Replay" link iMessage puts under a message sent with an
/// effect: a replay arrow and the word, in the theme's primary colour.
/// Tapping it plays the effect again exactly as the message menu's
/// "Replay effect" does (see [replayMessageEffect]).
///
/// It shows once the effect has played, for every effect that plays by
/// itself. Invisible ink has nothing to replay, since the ink covers the
/// bubble again by itself, and under reduced motion nothing plays, so
/// neither gets the link. Nothing is shown for a message without an effect.
///
/// The link looks small but takes taps over a full 48dp high target. A
/// touch, hover or focus lights only a slim pill around the arrow and the
/// word, in the middle of that target, as Material's state layer.
class MessageEffectReplayLink extends StatefulWidget {
  final Event event;

  /// Shadows for the label, to keep it legible over a wallpaper.
  final List<Shadow>? shadows;

  const MessageEffectReplayLink({required this.event, this.shadows, super.key});

  /// The height of the link, its touch target.
  static const height = 48.0;

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

  @override
  Widget build(BuildContext context) {
    final effect = effectOf(widget.event);
    if (effect == null ||
        effect == MessageEffect.invisibleInk ||
        MediaQuery.disableAnimationsOf(context) ||
        PlayedMessageEffects.shouldAutoPlay(widget.event)) {
      return const SizedBox.shrink();
    }
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final color = theme.colorScheme.primary;
    void replay() => replayMessageEffect(widget.event);
    return Semantics(
      button: true,
      label: l10n.replayNamedEffect(effect.localizedName(l10n)),
      onTap: replay,
      excludeSemantics: true,
      // The whole target takes the tap; the ink itself stays clear, and
      // the pill below shows the state instead.
      child: InkWell(
        key: const ValueKey('message_effect_replay'),
        onTap: replay,
        statesController: _states,
        splashFactory: NoSplash.splashFactory,
        overlayColor: const WidgetStatePropertyAll(Colors.transparent),
        child: ConstrainedBox(
          constraints: const BoxConstraints(
            minWidth: MessageEffectReplayLink.height,
            minHeight: MessageEffectReplayLink.height,
          ),
          child: Center(
            widthFactor: 1,
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
                // The arrow and the word sit 8dp in from the pill's
                // ends, as the status line's text sits in from the edge.
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.replay,
                      size: 16,
                      color: color,
                      shadows: widget.shadows,
                    ),
                    const SizedBox(width: 2),
                    Text(
                      l10n.replay,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: color,
                        fontWeight: FontWeight.w600,
                        shadows: widget.shadows,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
