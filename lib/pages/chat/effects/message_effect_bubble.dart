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
  static const loudDuration = Duration(milliseconds: 1500);
  static const gentleDuration = Duration(milliseconds: 2400);

  /// The part of [slamDuration] before the bubble lands.
  static const slamImpact = 0.3;

  /// The part of [loudDuration] the bubble takes to swell to full size.
  static const loudGrown = 0.12;

  /// The part of [gentleDuration] the bubble waits, small, before it grows.
  static const gentleSmall = 0.12;

  /// How strong the swell a gentle bubble is felt as gets, of full
  /// strength: enough to notice, well short of a buzz.
  static const gentleSwell = 0.45;

  /// The part of [loudDuration] after which the bubble shrinks back.
  static const loudHeld = 0.6;

  /// How many times a second a loud bubble shakes from side to side.
  static const loudShakeHz = 11.0;

  static double _secondsOf(Duration duration, double part) =>
      duration.inMicroseconds * part / 1e6;

  /// What a bubble effect is felt as, from the start of the play. Slam's
  /// thud belongs to its `SlamScene`, which starts as the bubble lands.
  static HapticPattern hapticsOf(MessageEffect effect) {
    switch (effect) {
      case MessageEffect.loud:
        final grown = _secondsOf(loudDuration, loudGrown);
        final held = _secondsOf(loudDuration, loudHeld);
        // The thud is still ringing for the first shakes (it lasts 300 ms
        // on a Pixel), so the ticks start with the first shake after it.
        final firstShake = ((grown + 0.3) * loudShakeHz - 0.25).ceil();
        return HapticPattern([
          // A quick rise as the bubble swells, a thud as it reaches full
          // size.
          HapticBeat.after(
            HapticPrimitive.quickRise,
            grown,
            scale: 0.7,
            endsAt: true,
          ),
          HapticBeat.after(HapticPrimitive.thud, grown, scale: 0.9),
          // A tick each time the shaking bubble is thrown to the right,
          // weaker as the shout dies down.
          for (var k = firstShake; (k + 0.25) / loudShakeHz < held; k++)
            HapticBeat.after(
              HapticPrimitive.tick,
              (k + 0.25) / loudShakeHz,
              scale:
                  0.5 -
                  0.3 * ((k + 0.25) / loudShakeHz - grown) / (held - grown),
            ),
        ]);
      case MessageEffect.gentle:
        // A swell that grows as the bubble starts to grow, is strongest
        // when it grows fastest, halfway, and has faded to nothing when
        // the bubble is full size. A vibrator that cannot vary its
        // strength but has the primitives gets a slow rise to the halfway
        // point and a fall from it.
        final start = _secondsOf(gentleDuration, gentleSmall);
        final end = _secondsOf(gentleDuration, 1);
        final middle = (start + end) / 2;
        return HapticPattern(
          [
            HapticBeat.after(
              HapticPrimitive.slowRise,
              middle,
              scale: 0.3,
              endsAt: true,
            ),
            HapticBeat.after(HapticPrimitive.quickFall, middle, scale: 0.3),
          ],
          envelope: HapticEnvelope.swell(
            start,
            middle,
            end,
            level: gentleSwell,
          ),
          continuous: true,
        );
      default:
        return HapticPattern.none;
    }
  }

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

  /// The host's count of plays when it started this bubble's scene, so a
  /// replay can tell whether that scene is still the one on screen.
  int? _hostPlay;

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

  void _playOnHost(MessageEffect effect) {
    final host = ScreenEffectHost.maybeOf(context);
    if (host == null) return;
    final started = host.play(
      effect,
      globalRect: _globalRect,
      globalRectOf: () => mounted ? _globalRect : null,
      text: widget.text,
      borderRadius: widget.borderRadius,
      bubbleColor: widget.bubbleColor,
      onBubbleColor: widget.onBubbleColor,
    );
    if (started) _hostPlay = host.plays;
  }

  /// Takes this bubble's scene off the host if it is still running, so a
  /// play that starts over does not leave the last one's scene behind.
  void _stopOwnScene() {
    final host = ScreenEffectHost.maybeOf(context);
    if (host == null || host.playing == null) return;
    if (_hostPlay == host.plays) host.stop();
  }

  void _onTick() {
    // The slam's ring and shake start the moment the bubble lands.
    if (widget.effect == MessageEffect.slam &&
        !_landed &&
        _controller.value >= EffectBubble.slamImpact) {
      _landed = true;
      _playOnHost(MessageEffect.slam);
    }
  }

  /// Plays the effect from the start, in place of a play of it still
  /// running. Does nothing under reduced motion.
  void play() {
    if (MediaQuery.disableAnimationsOf(context)) {
      if (_moving) setState(() => _moving = false);
      return;
    }
    _stopOwnScene();
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

  /// How long a replay takes to scroll its bubble into view.
  static const _revealDuration = Duration(milliseconds: 300);

  /// Plays the effect again, as the message menu or the Replay link under
  /// the bubble asks. A bubble that is partly off screen is first scrolled
  /// to the middle of the conversation, so the whole effect is seen.
  Future<void> replay() async {
    if (!MediaQuery.disableAnimationsOf(context) && !_fullyVisible) {
      await Scrollable.ensureVisible(
        context,
        alignment: 0.5,
        duration: _revealDuration,
        curve: Easing.standard,
      );
      if (!mounted) return;
    }
    play();
  }

  /// Whether the whole bubble is inside the conversation it scrolls in.
  /// True when it is not in a scrolling list at all.
  bool get _fullyVisible {
    final bubble = _globalRect;
    final viewport = Scrollable.maybeOf(context)?.context.findRenderObject();
    if (bubble == null || viewport is! RenderBox || !viewport.hasSize) {
      return true;
    }
    final visible = viewport.localToGlobal(Offset.zero) & viewport.size;
    return visible.inflate(0.5).contains(bubble.topLeft) &&
        visible.inflate(0.5).contains(bubble.bottomRight);
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
        const grown = EffectBubble.loudGrown, held = EffectBubble.loudHeld;
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
        scale = 1 + 0.9 * swell;
        // Shaking with its own noise while it is large.
        final seconds = v * EffectBubble.loudDuration.inMilliseconds / 1000;
        final shake = swell * (v < held ? 1 : 0.4);
        angle = math.sin(seconds * math.pi * 2 * 8.5) * 0.045 * shake;
        offset = Offset(
          math.sin(seconds * math.pi * 2 * EffectBubble.loudShakeHz) *
              3 *
              shake,
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
/// on screen, and again when the message menu or the Replay link under the
/// bubble asks for a replay (see [replayMessageEffect]). A message without
/// an effect is passed through untouched.
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
    _bubbleKey.currentState?.replay();
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
