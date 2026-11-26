// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/invisible_ink.dart';
import 'package:fluffychat/pages/chat/effects/played_message_effects.dart';
import 'package:fluffychat/pages/chat/effects/screen_effect_host.dart';
import 'package:fluffychat/utils/effect_haptics.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// A bubble that performs [effect].
///
/// A bubble effect moves the bubble itself: slam throws it down, loud
/// swells and shakes it, gentle lets it grow in slowly, invisible ink
/// covers it until touched. A screen effect leaves the bubble alone and
/// plays on the [ScreenEffectHost] above it.
///
/// Each play is felt too, on phones with haptics (see [EffectHaptics]).
/// Under reduced motion nothing moves and nothing is felt; a line under the
/// bubble names the effect it was sent with.
class EffectBubble extends StatefulWidget {
  final MessageEffect effect;
  final Widget child;

  /// Which side the bubble sits on, the side it grows from.
  final bool ownMessage;
  final Color bubbleColor;
  final Color onBubbleColor;
  final BorderRadius borderRadius;

  /// The bubble's text, which the echo effect repeats.
  final String text;

  /// Whether the effect plays as soon as the bubble is on screen.
  final bool autoPlay;

  const EffectBubble({
    required this.effect,
    required this.child,
    required this.ownMessage,
    required this.bubbleColor,
    required this.onBubbleColor,
    required this.borderRadius,
    this.text = '',
    this.autoPlay = false,
    super.key,
  });

  /// How long each bubble effect moves the bubble.
  static const slamDuration = Duration(milliseconds: 900);
  static const loudDuration = Duration(milliseconds: 1900);
  static const gentleDuration = Duration(milliseconds: 2400);

  /// The part of [slamDuration] before the bubble lands.
  static const slamImpact = 0.3;

  /// The part of [loudDuration] the bubble takes to swell to full size.
  static const loudGrown = 0.16;

  /// The part of [gentleDuration] the bubble waits, small, before it grows.
  static const gentleSmall = 0.12;

  /// What a bubble effect is felt as, from the start of the play. Slam's
  /// thud belongs to its `SlamScene`, which starts as the bubble lands.
  static List<HapticBeat> hapticsOf(MessageEffect effect) => switch (effect) {
    // A quick rise as the bubble swells, a thud as it reaches full size.
    MessageEffect.loud => [
      const HapticBeat(HapticPrimitive.quickRise, Duration.zero, scale: 0.7),
      HapticBeat(HapticPrimitive.thud, loudDuration * loudGrown, scale: 0.9),
    ],
    // One soft tick as it starts to grow.
    MessageEffect.gentle => [
      HapticBeat(
        HapticPrimitive.tick,
        gentleDuration * gentleSmall,
        scale: 0.4,
      ),
    ],
    _ => const [],
  };

  @override
  State<EffectBubble> createState() => EffectBubbleState();
}

class EffectBubbleState extends State<EffectBubble>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status == AnimationStatus.completed) setState(() => _moving = false);
    });
  final _inkKey = GlobalKey<InvisibleInkState>();

  /// Whether the bubble is being moved by its effect, or is about to be.
  late bool _moving = widget.autoPlay && _duration != null;
  bool _landed = false;
  int _plays = 0;

  /// How many times the effect has played here.
  int get plays => _plays;

  Duration? get _duration => switch (widget.effect) {
    MessageEffect.slam => EffectBubble.slamDuration,
    MessageEffect.loud => EffectBubble.loudDuration,
    MessageEffect.gentle => EffectBubble.gentleDuration,
    _ => null,
  };

  @override
  void initState() {
    super.initState();
    _controller.addListener(_onTick);
    if (widget.autoPlay) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) play();
      });
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Rect? get _globalRect {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.hasSize) return null;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  void _playOnHost(MessageEffect effect) =>
      ScreenEffectHost.maybeOf(context)?.play(
        effect,
        globalRect: _globalRect,
        text: widget.text,
        bubbleColor: widget.bubbleColor,
        onBubbleColor: widget.onBubbleColor,
      );

  void _onTick() {
    // The slam's ring and shake start the moment the bubble lands.
    if (widget.effect == MessageEffect.slam &&
        !_landed &&
        _controller.value >= EffectBubble.slamImpact) {
      _landed = true;
      _playOnHost(MessageEffect.slam);
    }
  }

  /// Plays the effect from the start. Does nothing under reduced motion.
  void play() {
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_moving) setState(() => _moving = false);
      return;
    }
    _plays++;
    final effect = widget.effect;
    if (effect == MessageEffect.invisibleInk) {
      _inkKey.currentState?.conceal();
      return;
    }
    final duration = _duration;
    if (duration == null) {
      _playOnHost(effect);
      return;
    }
    _landed = false;
    setState(() => _moving = true);
    _controller
      ..duration = duration
      ..forward(from: 0);
    EffectHaptics.instance.playFor(context, EffectBubble.hapticsOf(effect));
  }

  /// [child] where the effect has it at this moment; in place when
  /// [active] is false.
  Widget _moved(Widget child, {required bool active}) {
    final v = _controller.value;
    final side = widget.ownMessage ? 1.0 : -1.0;
    var scale = 1.0;
    var angle = 0.0;
    var offset = Offset.zero;
    var opacity = 1.0;
    switch (active ? widget.effect : null) {
      case MessageEffect.slam:
        const impact = EffectBubble.slamImpact;
        if (v < impact) {
          // Held high and tilted, then thrown at the page.
          final fall = Easing.emphasizedAccelerate.transform(v / impact);
          scale = 2.6 - 1.6 * fall;
          angle = -0.16 * side * (1 - fall);
          offset = Offset(0, -46 * (1 - fall));
          opacity = math.min(1, v / impact * 3);
        } else {
          // Flattened by the landing, springing back.
          final after = (v - impact) / (1 - impact);
          scale =
              1 - 0.08 * math.exp(-5 * after) * math.sin(after * math.pi * 3);
        }
      case MessageEffect.loud:
        const grown = EffectBubble.loudGrown, held = 0.68;
        final double swell;
        if (v < grown) {
          swell = Easing.emphasizedDecelerate.transform(v / grown);
        } else if (v < held) {
          swell = 1;
        } else {
          swell =
              1 -
              Curves.easeInOutCubicEmphasized.transform(
                (v - held) / (1 - held),
              );
        }
        scale = 1 + 0.8 * swell;
        // Shaking with its own noise while it is large.
        final seconds = v * EffectBubble.loudDuration.inMilliseconds / 1000;
        final shake = swell * (v < held ? 1 : 0.4);
        angle = math.sin(seconds * math.pi * 2 * 8.5) * 0.045 * shake;
        offset = Offset(
          math.sin(seconds * math.pi * 2 * 11) * 3 * shake,
          math.cos(seconds * math.pi * 2 * 7) * 2 * shake,
        );
      case MessageEffect.gentle:
        // Arrives small and takes its time growing up.
        const small = EffectBubble.gentleSmall;
        final grow = v < small
            ? 0.0
            : Curves.easeInOutSine.transform((v - small) / (1 - small));
        scale = 0.5 + 0.5 * grow;
        opacity = math.min(1, v / 0.15);
      default:
    }
    return Opacity(
      opacity: opacity,
      child: Transform.translate(
        offset: offset,
        child: Transform.rotate(
          angle: angle,
          child: Transform.scale(
            scale: scale,
            alignment: widget.ownMessage
                ? Alignment.bottomRight
                : Alignment.bottomLeft,
            child: child,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.disableAnimationsOf(context);
    var bubble = widget.child;
    if (widget.effect == MessageEffect.invisibleInk) {
      bubble = InvisibleInk(
        key: _inkKey,
        bubbleColor: widget.bubbleColor,
        dustColor: widget.onBubbleColor,
        borderRadius: widget.borderRadius,
        animate: !reduced,
        child: bubble,
      );
    } else if (_duration != null) {
      // The transforms stay in the tree between plays, so the bubble
      // under them keeps its state when a play starts or ends.
      bubble = AnimatedBuilder(
        animation: _controller,
        builder: (context, child) =>
            _moved(child!, active: _moving && !reduced),
        child: bubble,
      );
    }
    if (!reduced) return bubble;
    final l10n = L10n.of(context);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: widget.ownMessage
          ? CrossAxisAlignment.end
          : CrossAxisAlignment.start,
      children: [
        bubble,
        Padding(
          padding: const EdgeInsets.only(top: 2, left: 4, right: 4),
          child: Text(
            l10n.sentWithEffect(widget.effect.localizedName(l10n)),
            key: const ValueKey('message_effect_badge'),
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ],
    );
  }
}

/// The hook between a message in the timeline and its effect: wraps the
/// bubble of [event] so its effect plays once when the message first comes
/// on screen, and again when the message menu asks for a replay. A message
/// without an effect is passed through untouched.
class MessageEffectBubble extends StatefulWidget {
  final Event event;
  final Widget child;
  final bool ownMessage;
  final Color bubbleColor;
  final Color onBubbleColor;
  final BorderRadius borderRadius;

  const MessageEffectBubble({
    required this.event,
    required this.child,
    required this.ownMessage,
    required this.bubbleColor,
    required this.onBubbleColor,
    required this.borderRadius,
    super.key,
  });

  /// Whether [event]'s effect brings the bubble in itself, in which case
  /// the timeline's own entrance animation stays out of its way.
  static bool ownsEntrance(Event event) => switch (effectOf(event)) {
    MessageEffect.slam || MessageEffect.loud || MessageEffect.gentle => true,
    _ => false,
  };

  @override
  State<MessageEffectBubble> createState() => _MessageEffectBubbleState();
}

class _MessageEffectBubbleState extends State<MessageEffectBubble>
    with WidgetsBindingObserver {
  final _bubbleKey = GlobalKey<EffectBubbleState>();
  bool _autoPlay = false;
  bool _waitingForResume = false;

  static bool get _appVisible {
    final state = WidgetsBinding.instance.lifecycleState;
    return state == null || state == AppLifecycleState.resumed;
  }

  @override
  void initState() {
    super.initState();
    messageEffectReplays.addListener(_onReplay);
    final effect = effectOf(widget.event);
    // Invisible ink has nothing to play: it is simply always on.
    if (effect == null || effect == MessageEffect.invisibleInk) return;
    if (!PlayedMessageEffects.shouldAutoPlay(widget.event)) return;
    if (_appVisible) {
      PlayedMessageEffects.markPlayed(widget.event);
      _autoPlay = true;
    } else {
      // Nobody is looking: keep the effect for when the app comes back.
      _waitingForResume = true;
      WidgetsBinding.instance.addObserver(this);
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed || !_waitingForResume) return;
    _waitingForResume = false;
    WidgetsBinding.instance.removeObserver(this);
    if (!PlayedMessageEffects.shouldAutoPlay(widget.event)) return;
    PlayedMessageEffects.markPlayed(widget.event);
    _bubbleKey.currentState?.play();
  }

  void _onReplay() {
    if (messageEffectReplays.value?.$1 != widget.event.eventId) return;
    _bubbleKey.currentState?.play();
  }

  @override
  void dispose() {
    messageEffectReplays.removeListener(_onReplay);
    if (_waitingForResume) WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final effect = effectOf(widget.event);
    if (effect == null) return widget.child;
    return EffectBubble(
      key: _bubbleKey,
      effect: effect,
      ownMessage: widget.ownMessage,
      bubbleColor: widget.bubbleColor,
      onBubbleColor: widget.onBubbleColor,
      borderRadius: widget.borderRadius,
      text: widget.event.body,
      autoPlay: _autoPlay,
      child: widget.child,
    );
  }
}
