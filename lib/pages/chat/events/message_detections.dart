// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/data_detectors/data_detections.dart';
import 'package:fluffychat/utils/data_detectors/detection.dart';
import 'package:fluffychat/utils/data_detectors/detection_actions.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/rendering.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// The data detections of one message, for the message's text renderer:
/// it underlines them in the text colour and reports taps on them to
/// [onTap] with the tapped stretch's box on screen.
class DetectionScope extends InheritedWidget {
  final String eventId;
  final List<Detection> detections;
  final void Function(Detection detection, Rect span)? onTap;

  /// The detection whose menu is open, shown pressed.
  final Detection? pressed;

  const DetectionScope({
    required this.eventId,
    required this.detections,
    required this.onTap,
    this.pressed,
    required super.child,
    super.key,
  });

  /// The detections of the message [eventId], if the nearest scope is that
  /// message's. A quoted reply inside the bubble renders its own text and
  /// gets none.
  static DetectionScope? maybeOf(BuildContext context, String? eventId) {
    final scope = context.dependOnInheritedWidgetOfExactType<DetectionScope>();
    return scope != null && scope.eventId == eventId ? scope : null;
  }

  @override
  bool updateShouldNotify(DetectionScope oldWidget) =>
      !identical(detections, oldWidget.detections) ||
      eventId != oldWidget.eventId ||
      !identical(pressed, oldWidget.pressed) ||
      (onTap == null) != (oldWidget.onTap == null);
}

/// Finds the data detections of [event] once it is built and hands them to
/// [builder], with the assist chips the message shows: one per detection
/// in reading order, at most [DataDetections.maxChips], and only while the
/// message is its chat's newest with detections.
///
/// Taps on a detection open its menu under the bubble. Long-presses are
/// left to the message.
class MessageDetections extends StatefulWidget {
  final Event event;

  /// Whether detections can be tapped and chips show; off while messages
  /// are being selected.
  final bool enabled;

  /// Builds the message: [wrapBubble] goes around the bubble, giving the
  /// text inside it its [DetectionScope] and the menu its place, and
  /// [chips] are the assist chips, null when the message shows none.
  final Widget Function(
    BuildContext context,
    Widget Function(Widget bubble) wrapBubble,
    Widget? chips,
  )
  builder;

  const MessageDetections({
    required this.event,
    required this.builder,
    this.enabled = true,
    super.key,
  });

  @override
  State<MessageDetections> createState() => _MessageDetectionsState();
}

class _MessageDetectionsState extends State<MessageDetections> {
  String? _text;
  List<Detection> _detections = const [];
  String? _contactRoomId;
  Detection? _pressed;
  final _bubbleKey = GlobalKey(debugLabel: 'detection bubble');

  ValueListenable<({String eventId, DateTime sent})?>? _newest;

  /// Whether this message is its chat's newest with detections, the one
  /// that shows chips. Only a change to this rebuilds the message.
  bool _showChips = false;

  @override
  void initState() {
    super.initState();
    _listen();
    _load();
  }

  void _listen() {
    _newest?.removeListener(_onNewest);
    _newest = DataDetections.instance.chipsEventOf(widget.event.room.id)
      ..addListener(_onNewest);
    _showChips = _computeShowChips();
  }

  bool _computeShowChips() =>
      widget.enabled &&
      _detections.isNotEmpty &&
      _newest?.value?.eventId == widget.event.eventId;

  void _onNewest() {
    final show = _computeShowChips();
    if (show != _showChips && mounted) setState(() => _showChips = show);
  }

  @override
  void dispose() {
    _newest?.removeListener(_onNewest);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant MessageDetections oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.event.room.id != oldWidget.event.room.id) _listen();
    if (DataDetections.textOf(widget.event) != _text ||
        widget.event.eventId != oldWidget.event.eventId) {
      _load();
    }
    _showChips = _computeShowChips();
  }

  void _load() {
    final event = widget.event;
    final text = DataDetections.textOf(event);
    _text = text;
    if (text == null) {
      _detections = const [];
      return;
    }
    final known = DataDetections.instance.cached(event.eventId, text);
    if (known != null) {
      _accept(known);
      return;
    }
    _detections = const [];
    DataDetections.instance.detect(event, text).then((found) {
      if (!mounted || _text != text) return;
      setState(() => _accept(found));
    });
  }

  void _accept(List<Detection> found) {
    _detections = found;
    _showChips = _computeShowChips();
    final phone = found.firstWhereOrNullType(DetectionType.phone);
    _contactRoomId = phone == null
        ? null
        : contactRoomForPhone(widget.event.room.client, phone.text);
  }

  Future<void> _openMenu(Detection detection, Rect span) async {
    final l10n = L10n.of(context);
    final (:system, :seam) = actionsFor(
      detection,
      l10n,
      contactRoomId: _contactRoomId,
    );
    final overlay =
        Overlay.of(context).context.findRenderObject()! as RenderBox;
    final bubble = _bubbleKey.currentContext?.findRenderObject() as RenderBox?;
    final bubbleRect = bubble == null || !bubble.attached
        ? span
        : MatrixUtils.transformRect(
            bubble.getTransformTo(overlay),
            Offset.zero & bubble.size,
          );
    final topLeft = overlay.globalToLocal(span.topLeft);
    final localSpan = topLeft & span.size;
    final position = detectionMenuPosition(
      span: localSpan,
      bubbleTop: bubbleRect.top,
      bubbleBottom: bubbleRect.bottom,
      menuHeight: detectionMenuHeight(system.length, seam.length),
      space: overlay.size,
    );
    setState(() => _pressed = detection);
    final picked = await showMenu<DetectionAction>(
      context: context,
      position: position,
      items: [
        for (final action in system) _item(action),
        if (system.isNotEmpty && seam.isNotEmpty) const PopupMenuDivider(),
        for (final action in seam) _item(action),
      ],
    );
    if (!mounted) return;
    setState(() => _pressed = null);
    if (picked == null) return;
    await DetectionActions.run(
      context,
      detection,
      picked,
      messageText: _text ?? detection.text,
    );
  }

  PopupMenuItem<DetectionAction> _item(DetectionAction action) => PopupMenuItem(
    value: action,
    child: Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        DetectionActionIcon(action, size: 24),
        const SizedBox(width: 12),
        Text(action.title),
      ],
    ),
  );

  @override
  Widget build(BuildContext context) {
    final detections = _detections;
    // The same widgets with or without detections, so the bubble is never
    // rebuilt from scratch when they arrive.
    Widget wrapBubble(Widget bubble) => KeyedSubtree(
      key: _bubbleKey,
      child: DetectionScope(
        eventId: widget.event.eventId,
        detections: detections,
        onTap: widget.enabled && detections.isNotEmpty ? _openMenu : null,
        pressed: _pressed,
        child: bubble,
      ),
    );
    final l10n = L10n.of(context);
    return widget.builder(
      context,
      wrapBubble,
      _showChips
          ? DetectionChips(
              key: ValueKey('chips_${widget.event.eventId}'),
              detections: detections.take(DataDetections.maxChips).toList(),
              actionOf: (detection) => chipActionFor(detection, l10n),
              onPressed: (detection, action) => DetectionActions.run(
                context,
                detection,
                action,
                messageText: _text ?? detection.text,
              ),
            )
          : null,
    );
  }
}

extension on List<Detection> {
  Detection? firstWhereOrNullType(DetectionType type) {
    for (final detection in this) {
      if (detection.type == type) return detection;
    }
    return null;
  }
}

/// The assist chips under a bubble, 8dp apart: the app's [ActionChip]s,
/// each with the action's app icon or Material icon as its avatar.
class DetectionChips extends StatelessWidget {
  final List<Detection> detections;
  final DetectionAction Function(Detection detection) actionOf;
  final void Function(Detection detection, DetectionAction action) onPressed;

  const DetectionChips({
    required this.detections,
    required this.actionOf,
    required this.onPressed,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, detection) in detections.indexed) ...[
          if (i > 0) const SizedBox(width: 8),
          Builder(
            builder: (context) {
              final action = actionOf(detection);
              return ActionChip(
                onPressed: () => onPressed(detection, action),
                // The chip sits 4dp under the bubble, which a padded 48dp
                // target would cover.
                materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                avatar: DetectionActionIcon(
                  action,
                  size: 18,
                  color: theme.colorScheme.primary,
                ),
                label: Text(action.title),
                tooltip: detection.text,
              );
            },
          ),
        ],
      ],
    );
  }
}

/// An action's leading visual: the handling app's icon when the platform
/// gave one, else a Material icon.
class DetectionActionIcon extends StatelessWidget {
  final DetectionAction action;
  final double size;
  final Color? color;

  const DetectionActionIcon(
    this.action, {
    required this.size,
    this.color,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final png = action.appIcon;
    if (png == null) return Icon(action.icon, size: size, color: color);
    return ClipOval(
      child: Image.memory(
        png,
        width: size,
        height: size,
        fit: BoxFit.cover,
        filterQuality: FilterQuality.medium,
        gaplessPlayback: true,
        errorBuilder: (_, _, _) => Icon(action.icon, size: size, color: color),
      ),
    );
  }
}

/// The height [showMenu] gives a detection's menu: 8dp above and below,
/// 48dp an item, 16dp for the divider between the platform's actions and
/// Seam's.
double detectionMenuHeight(int system, int seam) =>
    16 + 48.0 * (system + seam) + (system > 0 && seam > 0 ? 16 : 0);

/// Where a detection's menu goes in [space]: 4dp under the bubble and lined
/// up with the [span], or 4dp over the bubble when there is no room
/// underneath. A span right of the middle hangs the menu from its right
/// edge.
RelativeRect detectionMenuPosition({
  required Rect span,
  required double bubbleTop,
  required double bubbleBottom,
  required double menuHeight,
  required Size space,
}) {
  final below = bubbleBottom + 4;
  final top = below + menuHeight <= space.height - 8
      ? below
      : math.max(8.0, bubbleTop - 4 - menuHeight);
  final alignRight = span.center.dx > space.width / 2;
  final x = alignRight ? span.right : span.left;
  return RelativeRect.fromLTRB(
    alignRight ? space.width : x,
    top,
    space.width - x,
    0,
  );
}

/// The box on screen around the stretch of [detection] under [global], in
/// the paragraph found there; null when there is no paragraph.
Rect? detectionSpanRect(
  BuildContext context,
  Detection detection,
  Offset global,
) {
  final result = HitTestResult();
  WidgetsBinding.instance.hitTestInView(
    result,
    global,
    View.of(context).viewId,
  );
  for (final entry in result.path) {
    final target = entry.target;
    if (target is! RenderParagraph) continue;
    final local = target.globalToLocal(global);
    final plain = target.text.toPlainText(includeSemanticsLabels: false);
    for (final piece in detection.pieces) {
      var from = 0;
      while (true) {
        final at = plain.indexOf(piece, from);
        if (at < 0) break;
        from = at + 1;
        final boxes = target.getBoxesForSelection(
          TextSelection(baseOffset: at, extentOffset: at + piece.length),
        );
        if (boxes.isEmpty) continue;
        var rect = boxes.first.toRect();
        for (final box in boxes.skip(1)) {
          rect = rect.expandToInclude(box.toRect());
        }
        if (!rect.inflate(2).contains(local)) continue;
        return MatrixUtils.transformRect(target.getTransformTo(null), rect);
      }
    }
  }
  return null;
}
