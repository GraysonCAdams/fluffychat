// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/gestures.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

/// Something on screen that a request named: where it is and how it was
/// found.
class Found {
  /// The match's bounds, in the view's logical pixels.
  final Rect rect;
  final int viewId;
  final String description;

  /// Whether a press at the centre of [rect] reaches the match, rather than
  /// something drawn over it.
  final bool hittable;

  /// The semantics node, for a match found by label.
  final SemanticsNode? node;

  const Found({
    required this.rect,
    required this.viewId,
    required this.description,
    this.hittable = true,
    this.node,
  });

  Offset get center => rect.center;

  Map<String, Object?> toJson() => {
    'description': description,
    'view': viewId,
    'rect': rectJson(rect),
    'center': {'x': _r(rect.center.dx), 'y': _r(rect.center.dy)},
    'hittable': hittable,
  };
}

double _r(double v) => (v * 10).round() / 10;

Map<String, double> rectJson(Rect r) => {
  'x': _r(r.left),
  'y': _r(r.top),
  'w': _r(r.width),
  'h': _r(r.height),
};

/// Where a request points, read from its parameters: `x`/`y`, or a finder
/// (`key`, `text`, `textContains`, `type`, `label`, `labelContains`,
/// `tooltip`, `identifier`) with an optional `index` and `view`.
class TargetSpec {
  final double? x;
  final double? y;
  final String? key;
  final String? text;
  final String? textContains;
  final String? type;
  final String? label;
  final String? labelContains;
  final String? tooltip;
  final String? identifier;
  final int index;
  final int? view;

  const TargetSpec({
    this.x,
    this.y,
    this.key,
    this.text,
    this.textContains,
    this.type,
    this.label,
    this.labelContains,
    this.tooltip,
    this.identifier,
    this.index = 0,
    this.view,
  });

  factory TargetSpec.from(Map<String, Object?> p) {
    String? s(String k) => p[k]?.toString();
    double? d(String k) => p[k] == null ? null : double.parse('${p[k]}');
    return TargetSpec(
      x: d('x'),
      y: d('y'),
      key: s('key'),
      text: s('text'),
      textContains: s('textContains'),
      type: s('type'),
      label: s('label'),
      labelContains: s('labelContains'),
      tooltip: s('tooltip'),
      identifier: s('identifier'),
      index: p['index'] == null ? 0 : int.parse('${p['index']}'),
      view: p['view'] == null ? null : int.parse('${p['view']}'),
    );
  }

  bool get isPoint => x != null && y != null;
  bool get bySemantics =>
      label != null ||
      labelContains != null ||
      tooltip != null ||
      identifier != null;
  bool get byWidget =>
      key != null || text != null || textContains != null || type != null;
  bool get isEmpty => !isPoint && !bySemantics && !byWidget;

  @override
  String toString() => [
    if (isPoint) 'x=$x,y=$y',
    if (key != null) 'key=$key',
    if (text != null) 'text="$text"',
    if (textContains != null) 'textContains="$textContains"',
    if (type != null) 'type=$type',
    if (label != null) 'label="$label"',
    if (labelContains != null) 'labelContains="$labelContains"',
    if (tooltip != null) 'tooltip="$tooltip"',
    if (identifier != null) 'identifier=$identifier',
    if (index != 0) 'index=$index',
  ].join(' ');
}

/// Finds widgets in the element tree and nodes in the semantics tree.
class Finder {
  /// Keeps the semantics tree built while something reads it. The handle is
  /// let go [semanticsIdle] after the last read: a live semantics tree costs
  /// build time on every frame, which would skew frame timings.
  SemanticsHandle? _semantics;
  Timer? _semanticsTimer;
  Duration semanticsIdle = const Duration(seconds: 60);

  bool get semanticsHeld => _semantics != null;

  void releaseSemantics() {
    _semanticsTimer?.cancel();
    _semanticsTimer = null;
    _semantics?.dispose();
    _semantics = null;
  }

  /// Turns the semantics tree on, waiting for the frame that builds it when
  /// it was off.
  Future<void> holdSemantics(Future<void> Function() nextFrame) async {
    _semanticsTimer?.cancel();
    _semanticsTimer = Timer(semanticsIdle, releaseSemantics);
    if (_semantics != null) return;
    _semantics = SemanticsBinding.instance.ensureSemantics();
    await nextFrame();
  }

  static Iterable<RenderView> get views => WidgetsBinding.instance.renderViews;

  static RenderView viewFor(int? viewId) {
    if (viewId == null) {
      final implicit = WidgetsBinding.instance.platformDispatcher.implicitView;
      for (final v in views) {
        if (v.flutterView == implicit) return v;
      }
      return views.first;
    }
    return views.firstWhere(
      (v) => v.flutterView.viewId == viewId,
      orElse: () => throw ArgumentError('No view $viewId'),
    );
  }

  /// Every widget the spec's `key`, `text`, `textContains` and `type` match,
  /// on stage, hittable ones first.
  List<Found> widgets(TargetSpec spec, {int limit = 50}) {
    final root = WidgetsBinding.instance.rootElement;
    if (root == null) return const [];
    final seen = <RenderObject>{};
    final found = <Found>[];
    void visit(Element element) {
      if (found.length >= limit * 4) return;
      final widget = element.widget;
      if (_widgetMatches(widget, spec)) {
        final box = element.findRenderObject();
        if (box is RenderBox && box.attached && box.hasSize && seen.add(box)) {
          final view = _viewOf(box);
          if (view != null &&
              (spec.view == null || spec.view == view.flutterView.viewId)) {
            final rect = MatrixUtils.transformRect(
              box.getTransformTo(null),
              Offset.zero & box.size,
            );
            final viewId = view.flutterView.viewId;
            found.add(
              Found(
                rect: rect,
                viewId: viewId,
                description: _describe(widget),
                hittable: _hits(box, rect.center, viewId),
              ),
            );
          }
        }
      }
      element.debugVisitOnstageChildren(visit);
    }

    // debugVisitOnstageChildren runs in every build mode; it skips what
    // Offstage, inactive routes and lazy lists keep out of view.
    root.debugVisitOnstageChildren(visit);
    // Hittable matches first, each group in tree order.
    final hittable = [...found.where((f) => f.hittable)];
    final covered = [...found.where((f) => !f.hittable)];
    return [...hittable, ...covered].take(limit).toList();
  }

  static bool _widgetMatches(Widget widget, TargetSpec spec) {
    if (!spec.byWidget) return false;
    if (spec.key != null) {
      final key = widget.key;
      final value = switch (key) {
        ValueKey(:final value) => '$value',
        ObjectKey(:final value) => '$value',
        _ => null,
      };
      if (value != spec.key) return false;
    }
    if (spec.type != null && widget.runtimeType.toString() != spec.type) {
      return false;
    }
    if (spec.text != null || spec.textContains != null) {
      final text = switch (widget) {
        Text(:final data, :final textSpan) => data ?? textSpan?.toPlainText(),
        RichText(:final text) => text.toPlainText(),
        EditableText(:final controller) => controller.text,
        _ => null,
      };
      if (text == null) return false;
      if (spec.text != null && text != spec.text) return false;
      if (spec.textContains != null && !text.contains(spec.textContains!)) {
        return false;
      }
    }
    return true;
  }

  static String _describe(Widget widget) {
    final text = switch (widget) {
      Text(:final data, :final textSpan) => data ?? textSpan?.toPlainText(),
      RichText(:final text) => text.toPlainText(),
      _ => null,
    };
    final key = widget.key;
    return [
      widget.runtimeType.toString(),
      if (key != null) '$key',
      if (text != null)
        '"${text.length > 60 ? '${text.substring(0, 60)}…' : text}"',
    ].join(' ');
  }

  static RenderView? _viewOf(RenderObject object) {
    RenderObject? o = object;
    while (o != null && o is! RenderView) {
      o = o.parent;
    }
    return o as RenderView?;
  }

  static bool _hits(RenderObject target, Offset position, int viewId) {
    final result = HitTestResult();
    WidgetsBinding.instance.hitTestInView(result, position, viewId);
    return result.path.any((entry) => entry.target == target);
  }

  /// Every semantics node the spec's `label`, `labelContains`, `tooltip`
  /// and `identifier` match; every node when the spec names none of them.
  List<Found> semantics(TargetSpec spec, {int limit = 500}) {
    final found = <Found>[];
    for (final view in views) {
      final viewId = view.flutterView.viewId;
      if (spec.view != null && spec.view != viewId) continue;
      final root = view.owner?.semanticsOwner?.rootSemanticsNode;
      if (root == null) continue;
      final dpr = view.flutterView.devicePixelRatio;
      void visit(SemanticsNode node, Matrix4 toRoot) {
        if (found.length >= limit) return;
        final transform = node.transform;
        final here = transform == null ? toRoot : toRoot.multiplied(transform);
        if (!node.isInvisible && !node.isMergedIntoParent) {
          final data = node.getSemanticsData();
          if (_semanticsMatches(data, spec)) {
            final physical = MatrixUtils.transformRect(here, node.rect);
            final rect = Rect.fromLTRB(
              physical.left / dpr,
              physical.top / dpr,
              physical.right / dpr,
              physical.bottom / dpr,
            );
            found.add(
              Found(
                rect: rect,
                viewId: viewId,
                description: describeSemantics(data),
                node: node,
              ),
            );
          }
        }
        node.visitChildren((child) {
          visit(child, here);
          return true;
        });
      }

      // Each node's transform maps it into its parent, and the chain ends in
      // physical pixels, hence the division by the pixel ratio above.
      visit(root, Matrix4.identity());
    }
    return found;
  }

  static bool _semanticsMatches(SemanticsData data, TargetSpec spec) {
    if (spec.label != null && data.label != spec.label) return false;
    if (spec.labelContains != null &&
        !data.label.contains(spec.labelContains!) &&
        !data.value.contains(spec.labelContains!) &&
        !data.hint.contains(spec.labelContains!) &&
        !data.tooltip.contains(spec.labelContains!)) {
      return false;
    }
    if (spec.tooltip != null && data.tooltip != spec.tooltip) return false;
    if (spec.identifier != null && data.identifier != spec.identifier) {
      return false;
    }
    if (!spec.bySemantics) {
      // An unfiltered listing skips the containers that say nothing.
      return data.label.isNotEmpty ||
          data.value.isNotEmpty ||
          data.tooltip.isNotEmpty ||
          data.identifier.isNotEmpty ||
          data.actions != 0;
    }
    return true;
  }

  static String describeSemantics(SemanticsData data) => [
    if (data.label.isNotEmpty) '"${data.label.replaceAll('\n', ' ')}"',
    if (data.value.isNotEmpty) 'value="${data.value}"',
    if (data.tooltip.isNotEmpty) 'tooltip="${data.tooltip}"',
    if (data.identifier.isNotEmpty) 'id=${data.identifier}',
  ].join(' ');

  static Map<String, Object?> semanticsJson(Found found) {
    final data = found.node!.getSemanticsData();
    return {
      'id': found.node!.id,
      'label': data.label,
      if (data.value.isNotEmpty) 'value': data.value,
      if (data.hint.isNotEmpty) 'hint': data.hint,
      if (data.tooltip.isNotEmpty) 'tooltip': data.tooltip,
      if (data.identifier.isNotEmpty) 'identifier': data.identifier,
      'role': data.role.name,
      'flags': data.flagsCollection.toStrings(),
      'actions': [
        for (final action in SemanticsAction.values)
          if (data.hasAction(action)) action.name,
      ],
      'view': found.viewId,
      'rect': rectJson(found.rect),
    };
  }

  /// The one thing [spec] names: its point, or its [TargetSpec.index]th
  /// match. Throws [StateError] when nothing matches.
  Future<Found> resolve(
    TargetSpec spec,
    Future<void> Function() nextFrame,
  ) async {
    if (spec.isPoint) {
      final view = viewFor(spec.view);
      final p = Offset(spec.x!, spec.y!);
      return Found(
        rect: Rect.fromCenter(center: p, width: 0, height: 0),
        viewId: view.flutterView.viewId,
        description: 'point',
      );
    }
    final List<Found> matches;
    if (spec.bySemantics) {
      await holdSemantics(nextFrame);
      matches = semantics(spec);
    } else if (spec.byWidget) {
      matches = widgets(spec);
    } else {
      throw ArgumentError('Name a target: x/y, key, text, type or label');
    }
    if (matches.length <= spec.index) {
      throw StateError('No match for $spec (${matches.length} found)');
    }
    return matches[spec.index];
  }
}

/// The pointer kind a request asks for: `mouse` or `touch`, by default the
/// platform's own.
PointerDeviceKind pointerKind(Object? name, {required bool desktop}) =>
    switch (name?.toString()) {
      'touch' => PointerDeviceKind.touch,
      'mouse' => PointerDeviceKind.mouse,
      null => desktop ? PointerDeviceKind.mouse : PointerDeviceKind.touch,
      final other => throw ArgumentError('Unknown pointer kind "$other"'),
    };
