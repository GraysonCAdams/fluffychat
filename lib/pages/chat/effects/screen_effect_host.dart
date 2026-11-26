// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/pages/chat/effects/screen_effect_scenes.dart';
import 'package:fluffychat/utils/effect_haptics.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:material_ui/material_ui.dart';

/// The area a screen effect plays over: it lays the running scene on top
/// of [child] and lets the scene shake it. Message bubbles under it find
/// it with [maybeOf] and ask it to [ScreenEffectHostState.play].
class ScreenEffectHost extends StatefulWidget {
  final Widget child;

  const ScreenEffectHost({required this.child, super.key});

  static ScreenEffectHostState? maybeOf(BuildContext context) =>
      context.findAncestorStateOfType<ScreenEffectHostState>();

  @override
  State<ScreenEffectHost> createState() => ScreenEffectHostState();
}

class ScreenEffectHostState extends State<ScreenEffectHost>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(vsync: this)
    ..addStatusListener((status) {
      if (status != AnimationStatus.completed) return;
      _scene?.dispose();
      setState(() => _scene = null);
    });

  EffectScene? _scene;
  MessageEffect? _playing;
  int _plays = 0;

  /// The effect on screen now, or null.
  MessageEffect? get playing => _scene == null ? null : _playing;

  /// How many scenes have started here.
  int get plays => _plays;

  @override
  void initState() {
    super.initState();
    EffectHaptics.instance.prepare();
  }

  /// Starts [effect]'s scene for the bubble at [globalRect] (in global
  /// coordinates), in place of any scene still running, with the scene's
  /// haptics. Returns whether the effect has a scene.
  bool play(
    MessageEffect effect, {
    Rect? globalRect,
    String text = '',
    BorderRadius? borderRadius,
    Color? bubbleColor,
    Color? onBubbleColor,
  }) {
    final box = context.findRenderObject();
    Rect? rect;
    if (globalRect != null && box is RenderBox && box.hasSize) {
      rect = box.globalToLocal(globalRect.topLeft) & globalRect.size;
    }
    final scene = EffectScene.of(
      effect,
      EffectPalette.of(
        Theme.of(context),
        bubble: bubbleColor,
        onBubble: onBubbleColor,
      ),
      borderRadius == null
          ? EffectOrigin(rect: rect, text: text)
          : EffectOrigin(rect: rect, text: text, borderRadius: borderRadius),
      seed: _plays + 7,
    );
    if (scene == null) return false;
    _scene?.dispose();
    setState(() {
      _scene = scene;
      _playing = effect;
      _plays++;
    });
    _controller
      ..duration = scene.duration
      ..forward(from: 0);
    EffectHaptics.instance.playFor(context, scene.haptics);
    return true;
  }

  @override
  void dispose() {
    _scene?.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scene = _scene;
    // The child keeps its place in the tree whether or not a scene runs,
    // so starting one does not rebuild the conversation's state.
    return Stack(
      fit: StackFit.passthrough,
      children: [
        AnimatedBuilder(
          animation: _controller,
          builder: (context, child) => Transform.translate(
            offset:
                scene?.shake(_controller.value * scene.seconds) ?? Offset.zero,
            child: child,
          ),
          child: widget.child,
        ),
        if (scene != null)
          Positioned.fill(
            child: IgnorePointer(
              child: RepaintBoundary(
                child: CustomPaint(
                  key: const ValueKey('screen_effect_scene'),
                  painter: _ScenePainter(scene, _controller),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _ScenePainter extends CustomPainter {
  final EffectScene scene;
  final Animation<double> progress;

  _ScenePainter(this.scene, this.progress) : super(repaint: progress);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.clipRect(Offset.zero & size);
    scene.paint(canvas, size, progress.value * scene.seconds);
  }

  @override
  bool shouldRepaint(_ScenePainter oldDelegate) => oldDelegate.scene != scene;
}
