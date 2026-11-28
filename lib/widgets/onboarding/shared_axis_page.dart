// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

/// A page that enters and leaves with Material's shared axis X pattern,
/// the motion between the steps of the sign-in flow.
///
/// Going forward, the page underneath slides [SharedAxisTransition.shift]
/// dp to the left as it fades out in the first 35% of the transition, and
/// this page slides in the same distance from the right and fades in over
/// the rest. Going back plays it in reverse.
class SharedAxisPage<T> extends CustomTransitionPage<T> {
  SharedAxisPage({required super.child, super.key, super.restorationId})
    : super(
        transitionDuration: SharedAxisTransition.duration,
        reverseTransitionDuration: SharedAxisTransition.duration,
        transitionsBuilder: (context, animation, secondaryAnimation, child) =>
            SharedAxisTransition(
              animation: animation,
              secondaryAnimation: secondaryAnimation,
              child: child,
            ),
      );
}

class SharedAxisTransition extends StatelessWidget {
  final Animation<double> animation;
  final Animation<double> secondaryAnimation;
  final Widget child;

  const SharedAxisTransition({
    super.key,
    required this.animation,
    required this.secondaryAnimation,
    required this.child,
  });

  static const Duration duration = Duration(milliseconds: 400);
  static const double shift = 30;

  /// How far through the transition the outgoing page is gone and the
  /// incoming one starts to appear.
  static const double crossover = .35;

  @override
  Widget build(BuildContext context) {
    final surface = Theme.of(context).colorScheme.surface;
    return AnimatedBuilder(
      animation: Listenable.merge([animation, secondaryAnimation]),
      child: child,
      builder: (context, child) {
        final t = animation.value;
        final out = secondaryAnimation.value;
        final slideIn = Curves.easeInOutCubicEmphasized.transform(t);
        final slideOut = Curves.easeInOutCubicEmphasized.transform(out);
        final fadeIn = ((t - crossover) / (1 - crossover)).clamp(0.0, 1.0);
        final fadeOut = 1 - (out / crossover).clamp(0.0, 1.0);
        final direction = Directionality.of(context) == TextDirection.rtl
            ? -1.0
            : 1.0;
        // The incoming page's surface covers the outgoing page as that
        // fades, so nothing but surface shows between the two.
        final cover = (t / crossover).clamp(0.0, 1.0);
        return ColoredBox(
          color: surface.withValues(alpha: t >= 1 ? 1 : cover),
          child: Opacity(
            opacity: fadeIn * fadeOut,
            child: Transform.translate(
              offset: Offset(direction * shift * ((1 - slideIn) - slideOut), 0),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
