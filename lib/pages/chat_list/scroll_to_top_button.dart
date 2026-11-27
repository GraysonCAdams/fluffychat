// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/floating_control_transition.dart';
import 'package:material_ui/material_ui.dart';

/// A small tonal icon button with an up arrow that takes [controller]'s list
/// back to the top. It sits near the top of the list, away from New chat and
/// the unread chip at the bottom, and is there only while the list is
/// scrolled down by more than a screen.
///
/// It comes and goes with [FloatingControlTransition].
class ScrollToTopButton extends StatefulWidget {
  final ScrollController controller;

  const ScrollToTopButton({required this.controller, super.key});

  @override
  State<ScrollToTopButton> createState() => _ScrollToTopButtonState();
}

class _ScrollToTopButtonState extends State<ScrollToTopButton> {
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
  }

  void _toTop() => widget.controller.animateTo(
    0,
    duration: Durations.long2,
    curve: Easing.emphasizedDecelerate,
  );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return FloatingControlTransition(
      visible: _show,
      // Room around the button for its shadow.
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: IconButton.filledTonal(
          tooltip: L10n.of(context).backToTop,
          onPressed: _toTop,
          icon: const Icon(Icons.arrow_upward),
          // It floats over the rows, so it is raised to level 2 like other
          // controls that do.
          style: IconButton.styleFrom(
            elevation: 3,
            shadowColor: theme.colorScheme.shadow,
          ),
        ),
      ),
    );
  }
}
