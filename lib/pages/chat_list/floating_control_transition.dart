// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// Shows and hides a control that floats over the chat list, such as back
/// to top or the unread chip.
///
/// It enters by fading in and growing from 80% over 200 ms (short 4) in
/// Material's emphasized decelerate easing, and leaves by fading out and
/// shrinking back over 150 ms (short 3) in emphasized accelerate. With
/// animations turned off in the system it shows and hides at once. Its size
/// stays the same throughout, so nothing around it moves.
///
/// Hidden, it takes no taps and is left out of the semantics tree. Given a
/// null [child] while hidden, it keeps showing the last child it had for
/// the way out, so a chip keeps its count as it fades.
class FloatingControlTransition extends StatefulWidget {
  final bool visible;
  final Widget? child;

  const FloatingControlTransition({
    required this.visible,
    required this.child,
    super.key,
  });

  @override
  State<FloatingControlTransition> createState() =>
      _FloatingControlTransitionState();
}

class _FloatingControlTransitionState extends State<FloatingControlTransition>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: Durations.short4,
    reverseDuration: Durations.short3,
    value: widget.visible ? 1 : 0,
  );

  late final Animation<double> _curve = CurvedAnimation(
    parent: _shown,
    curve: Easing.emphasizedDecelerate,
    reverseCurve: Easing.emphasizedAccelerate,
  );

  late final Animation<double> _scale = Tween<double>(
    begin: 0.8,
    end: 1,
  ).animate(_curve);

  Widget? _lastChild;

  @override
  void didUpdateWidget(FloatingControlTransition oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.visible == oldWidget.visible) return;
    if (MediaQuery.disableAnimationsOf(context)) {
      _shown.value = widget.visible ? 1 : 0;
    } else if (widget.visible) {
      _shown.forward();
    } else {
      _shown.reverse();
    }
  }

  @override
  void dispose() {
    _shown.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.child ?? _lastChild;
    _lastChild = child;
    if (child == null) return const SizedBox.shrink();
    return ExcludeSemantics(
      excluding: !widget.visible,
      child: IgnorePointer(
        ignoring: !widget.visible,
        child: FadeTransition(
          opacity: _curve,
          child: ScaleTransition(scale: _scale, child: child),
        ),
      ),
    );
  }
}
