// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/optical_line.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/state_event_summary.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// A run of two or more consecutive system events in the timeline.
///
/// Folded, it shows the run's headline event (see
/// [StateEventSummary.headlineIndex]) and one faint, more distant line
/// behind it: "+N more" for the rest, or, for a pair whose other event is
/// the older one, that event itself. A tap anywhere brings the whole run
/// forward as a list, oldest first, one centred line per event: the faint
/// line fades as the real rows unfold in its place. In the list a tap on a
/// row shows its time beneath it, and a tap on the headline folds the run.
class StateEventGroup extends StatefulWidget {
  /// The run's events, oldest first.
  final List<Event> run;

  /// Whether the run starts unfolded, as the chat remembers it.
  final bool expanded;

  /// Called when a tap folds or unfolds the run.
  final ValueChanged<bool>? onExpandedChanged;

  const StateEventGroup({
    required this.run,
    this.expanded = false,
    this.onExpandedChanged,
    super.key,
  });

  /// The faint line behind the headline: its scale, opacity, backward tilt
  /// in degrees, blur sigma and gap below it in dp.
  static const faintScale = 0.75;
  static const faintOpacity = 0.40;
  static const faintTilt = 10.0;
  static const faintBlur = 0.3;
  static const faintGap = 3.0;

  /// Space above and below the group, the date separator's rhythm.
  static const rhythm = 8.0;

  /// Space between rows of the unfolded list.
  static const rowGap = 4.0;

  /// The widest an unfolded line gets on a wide window.
  static const wideMaxWidth = 480.0;

  @override
  State<StateEventGroup> createState() => _StateEventGroupState();
}

class _StateEventGroupState extends State<StateEventGroup>
    with SingleTickerProviderStateMixin {
  late final _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
    reverseDuration: const Duration(milliseconds: 300),
    value: widget.expanded ? 1 : 0,
  );
  late final _progress = CurvedAnimation(
    parent: _controller,
    curve: Easing.emphasizedDecelerate,
    reverseCurve: Easing.emphasizedAccelerate,
  );

  /// Indices into the run whose time is shown beneath their row.
  final _times = <int>{};

  bool get _open => _controller.status == AnimationStatus.completed;

  bool get _opening =>
      _controller.status == AnimationStatus.completed ||
      _controller.status == AnimationStatus.forward;

  @override
  void didUpdateWidget(StateEventGroup oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.expanded != oldWidget.expanded && widget.expanded != _opening) {
      _controller.value = widget.expanded ? 1 : 0;
    }
  }

  @override
  void dispose() {
    _progress.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _toggle() {
    final open = !_opening;
    if (!open) setState(_times.clear);
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = open ? 1 : 0;
    } else if (open) {
      _controller.forward();
    } else {
      _controller.reverse();
    }
    widget.onExpandedChanged?.call(open);
  }

  /// Places [child] at a depth: scaled and tipped back about its own
  /// bottom centre (so it never moves sideways), faded, softened, and
  /// taking [height] of its natural height in the column.
  Widget _atDepth(
    Widget child, {
    required double scale,
    required double opacity,
    required double tilt,
    required double blur,
    required double gap,
    required double height,
  }) {
    if (blur > 0.01) {
      child = ImageFiltered(
        imageFilter: ui.ImageFilter.blur(sigmaX: blur, sigmaY: blur),
        child: child,
      );
    }
    return ClipRect(
      child: Align(
        alignment: Alignment.bottomCenter,
        heightFactor: height,
        child: Padding(
          padding: EdgeInsets.only(bottom: gap),
          child: Opacity(
            opacity: opacity.clamp(0, 1),
            child: Transform(
              alignment: Alignment.bottomCenter,
              transform: Matrix4.identity()
                ..setEntry(3, 2, 0.002)
                ..rotateX(-tilt * math.pi / 180)
                ..scaleByDouble(scale, scale, 1, 1),
              child: child,
            ),
          ),
        ),
      ),
    );
  }

  /// One event's line. Once the list is open a tap shows its time beneath
  /// it; on the headline a tap folds the run instead.
  Widget _row(
    BuildContext context,
    int index, {
    required bool headline,
    required TextStyle style,
    required double maxWidth,
    double? opticalWidth,
  }) {
    final theme = Theme.of(context);
    final event = widget.run[index];
    final showTime = _times.contains(index);
    final still = MediaQuery.disableAnimationsOf(context);
    final time = Padding(
      padding: const EdgeInsets.only(top: 1, bottom: 2),
      child: Text(
        event.originServerTs.localizedTimeOfDay(context),
        style: theme.textTheme.labelSmall?.copyWith(
          color: style.color?.withValues(alpha: 0.6),
          fontFeatures: const [ui.FontFeature.tabularFigures()],
        ),
      ),
    );
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: !_open
          ? null
          : headline
          ? _toggle
          : () => setState(
              () => showTime ? _times.remove(index) : _times.add(index),
            ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          OpticalLine(
            StateEventSummary.line(event, L10n.of(context)),
            style: style,
            maxWidth: maxWidth,
            opticalWidth: opticalWidth,
          ),
          AnimatedSize(
            duration: still ? Duration.zero : const Duration(milliseconds: 200),
            curve: Easing.emphasizedDecelerate,
            child: !showTime
                ? const SizedBox(width: double.infinity)
                : still
                ? time
                : TweenAnimationBuilder<double>(
                    tween: Tween(begin: 0, end: 1),
                    duration: const Duration(milliseconds: 200),
                    builder: (context, value, child) =>
                        Opacity(opacity: value, child: child),
                    child: time,
                  ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final style = theme.textTheme.bodySmall!.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final run = widget.run;
    final headline = StateEventSummary.headlineIndex(run);
    // A pair whose other event is the older one shows it as the faint
    // line: "+1 more" would take the same room and say less.
    final pairFaint = run.length == 2 && headline == 1;
    return Semantics(
      button: true,
      expanded: _open,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: () {
            if (!_opening) _toggle();
          },
          child: Padding(
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: StateEventGroup.rhythm + 4,
            ),
            child: LayoutBuilder(
              builder: (context, box) {
                final maxWidth = box.maxWidth >= 600
                    ? StateEventGroup.wideMaxWidth
                    : box.maxWidth;
                // The faint line is always drawn narrower than the
                // headline: capped a step inside the headline's width.
                final front = _lineWidth(
                  StateEventSummary.line(run[headline], l10n),
                  style,
                  MediaQuery.textScalerOf(context),
                  maxWidth,
                );
                final faintCap =
                    math.max(front - 8, 16.0) / StateEventGroup.faintScale;
                return AnimatedBuilder(
                  animation: _progress,
                  builder: (context, _) {
                    final t = _progress.value;
                    double lerp(double a, double b) => ui.lerpDouble(a, b, t)!;
                    final children = <Widget>[];
                    for (var i = 0; i < run.length; i++) {
                      if (i == headline) {
                        if (!pairFaint) {
                          // "+N more" recedes and fades as the rows it
                          // stands for unfold in its place.
                          children.add(
                            _atDepth(
                              OpticalLine(
                                l10n.moreStateEvents(run.length - 1),
                                style: style,
                                maxWidth: faintCap,
                              ),
                              scale: StateEventGroup.faintScale,
                              opacity: StateEventGroup.faintOpacity * (1 - t),
                              tilt: StateEventGroup.faintTilt,
                              blur: StateEventGroup.faintBlur,
                              gap: StateEventGroup.faintGap * (1 - t),
                              height: StateEventGroup.faintScale * (1 - t),
                            ),
                          );
                        }
                        children.add(
                          _row(
                            context,
                            i,
                            headline: true,
                            style: style,
                            maxWidth: maxWidth,
                          ),
                        );
                      } else if (pairFaint) {
                        // The older event of a pair is the faint line, and
                        // comes forward to full size.
                        children.add(
                          _atDepth(
                            _row(
                              context,
                              i,
                              headline: false,
                              style: style,
                              maxWidth: lerp(faintCap, maxWidth),
                              opticalWidth: t < 0.5 ? faintCap : maxWidth,
                            ),
                            scale: lerp(StateEventGroup.faintScale, 1),
                            opacity: lerp(StateEventGroup.faintOpacity, 1),
                            tilt: lerp(StateEventGroup.faintTilt, 0),
                            blur: lerp(StateEventGroup.faintBlur, 0),
                            gap: lerp(
                              StateEventGroup.faintGap,
                              StateEventGroup.rowGap,
                            ),
                            height: lerp(StateEventGroup.faintScale, 1),
                          ),
                        );
                      } else {
                        // Folded events unfold at full size.
                        children.add(
                          _atDepth(
                            _row(
                              context,
                              i,
                              headline: false,
                              style: style,
                              maxWidth: maxWidth,
                            ),
                            scale: 1,
                            opacity: t,
                            tilt: 0,
                            blur: 0,
                            gap: i < headline ? StateEventGroup.rowGap : 0,
                            height: t,
                          ),
                        );
                        if (i > headline) {
                          // Newer housekeeping unfolds below the headline.
                          children.insert(
                            children.length - 1,
                            SizedBox(height: StateEventGroup.rowGap * t),
                          );
                        }
                      }
                    }
                    return SizedBox(
                      width: double.infinity,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: children,
                      ),
                    );
                  },
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}

/// Drawn width of [text] on one line within [maxWidth]. A line cut with an
/// ellipsis fills [maxWidth]: the engine's line metrics leave the ellipsis
/// out, so they are not used here.
double _lineWidth(
  String text,
  TextStyle style,
  TextScaler scaler,
  double maxWidth,
) {
  final painter = TextPainter(
    text: TextSpan(text: text, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
    maxLines: 1,
    ellipsis: '…',
  )..layout(maxWidth: maxWidth);
  final width = painter.didExceedMaxLines ? maxWidth : painter.width;
  painter.dispose();
  return width;
}
