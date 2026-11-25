// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';

/// Recognizes a press that is held still and then moved, for reordering
/// items that a long press also selects.
///
/// Holding the pointer still for [holdDelay] calls [onHold] and claims the
/// pointer, so letting go there is a plain long press. Moving it past the
/// touch slop after that calls [onLift] and starts the drag. Moving before
/// the hold ends gives the pointer up, so the list can scroll instead. A
/// mouse, whose drags do not scroll, starts the drag as soon as it moves.
class HoldThenDragGestureRecognizer extends MultiDragGestureRecognizer {
  HoldThenDragGestureRecognizer({
    this.holdDelay = kLongPressTimeout,
    this.onHold,
    this.onLift,
    super.debugOwner,
  });

  final Duration holdDelay;

  /// Called when the pointer has been held still for [holdDelay].
  VoidCallback? onHold;

  /// Called just before the drag starts.
  VoidCallback? onLift;

  @override
  MultiDragPointerState createNewPointerState(PointerDownEvent event) =>
      _HoldThenDragState(this, event);

  @override
  String get debugDescription => 'hold then drag';
}

class _HoldThenDragState extends MultiDragPointerState {
  _HoldThenDragState(this.recognizer, PointerDownEvent event)
    : super(event.position, event.kind, recognizer.gestureSettings) {
    _timer = Timer(recognizer.holdDelay, _held);
  }

  final HoldThenDragGestureRecognizer recognizer;

  Timer? _timer;

  /// Whether the pointer was held still long enough to lift on a move.
  bool _holding = false;

  /// Whether the pointer moved far enough to lift as soon as the arena
  /// gives it to this recognizer.
  bool _liftWhenAccepted = false;

  /// Starts the drag; set once the arena gave the pointer to this
  /// recognizer, and cleared when the drag starts.
  GestureMultiDragStartCallback? _starter;

  bool get _isMouse => kind == PointerDeviceKind.mouse;

  void _held() {
    _timer = null;
    _holding = true;
    recognizer.onHold?.call();
    if (_starter == null) resolve(GestureDisposition.accepted);
  }

  void _lift() {
    final starter = _starter;
    if (starter == null) return;
    _starter = null;
    _timer?.cancel();
    _timer = null;
    recognizer.onLift?.call();
    starter(initialPosition);
  }

  @override
  void accepted(GestureMultiDragStartCallback starter) {
    _starter = starter;
    if (_liftWhenAccepted) _lift();
  }

  @override
  void checkForResolutionAfterMove() {
    final distance = pendingDelta!.distance;
    if (_holding) {
      if (distance > computeHitSlop(kind, gestureSettings)) _lift();
      return;
    }
    if (_isMouse) {
      if (distance <= computePanSlop(kind, gestureSettings)) return;
      _liftWhenAccepted = true;
      if (_starter != null) {
        _lift();
      } else {
        resolve(GestureDisposition.accepted);
      }
      return;
    }
    if (distance > computeHitSlop(kind, gestureSettings)) {
      _timer?.cancel();
      _timer = null;
      if (_starter == null) resolve(GestureDisposition.rejected);
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _timer = null;
    super.dispose();
  }
}
