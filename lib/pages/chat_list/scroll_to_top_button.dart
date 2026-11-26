// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:material_ui/material_ui.dart';

/// A small tonal icon button with an up arrow that takes [controller]'s list
/// back to the top. It sits near the top of the list, away from New chat and
/// the unread chip at the bottom, and is there only while the list is
/// scrolled down by more than a screen.
///
/// It enters by expanding downwards, away from the top edge, in Material's
/// emphasized decelerate easing over 200 ms (short 4), and leaves by
/// collapsing upwards in emphasized accelerate over 150 ms (short 3).
class ScrollToTopButton extends StatefulWidget {
  final ScrollController controller;

  const ScrollToTopButton({required this.controller, super.key});

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _shown = AnimationController(
    vsync: this,
    duration: Durations.short4,
    reverseDuration: Durations.short3,
  );

  late final Animation<double> _reveal = CurvedAnimation(
    parent: _shown,
    curve: Easing.emphasizedDecelerate,
    reverseCurve: Easing.emphasizedAccelerate,
  );

  bool _show = false;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onScroll);
  }

  @override
  void didUpdateWidget(ScrollToTopButton oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onScroll);
      widget.controller.addListener(_onScroll);
    }
  }

  @override
  void dispose() {
    widget.controller.removeListener(_onScroll);
    _shown.dispose();
    super.dispose();
  }

  void _onScroll() {
    final controller = widget.controller;
    // One list at a time reads the controller; with none, or before the
    // first layout, there is nothing to go back up.
    if (controller.positions.length != 1) return;
    final position = controller.position;
    if (!position.hasViewportDimension || !position.hasPixels) return;
    final show = position.pixels > position.viewportDimension;
    if (show == _show) return;
    setState(() => _show = show);
    if (show) {
      _shown.forward();
    } else {
      _shown.reverse();
    }
  }

  void _toTop() => widget.controller.animateTo(
    0,
    duration: Durations.long2,
    curve: Easing.emphasizedDecelerate,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ExcludeSemantics(
      excluding: !_show,
      child: IgnorePointer(
        ignoring: !_show,
        child: ClipRect(
          child: SizeTransition(
            sizeFactor: _reveal,
            alignment: Alignment.topCenter,
            child: FadeTransition(
              opacity: _reveal,
              // Room around the button for its shadow inside the clip.
              child: Padding(
                padding: const EdgeInsets.all(4),
                child: IconButton.filledTonal(
                  tooltip: L10n.of(context).backToTop,
                  onPressed: _toTop,
                  icon: const Icon(Icons.arrow_upward),
                  // It floats over the rows, so it is raised to level 2
                  // like other controls that do.
                  style: IconButton.styleFrom(
                    elevation: 3,
                    shadowColor: theme.colorScheme.shadow,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
