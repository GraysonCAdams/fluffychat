// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:developer' show Timeline;

import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Feeds pointer and key events to the app as if the platform had sent them,
/// through [GestureBinding.handlePointerEvent] and the keyboard pipeline.
///
/// Nothing reaches the operating system: the real cursor does not move and
/// the window needs no focus. The pointers use device ids of their own, so
/// the app tracks them apart from the real mouse.
class InputInjector {
  /// Device ids the app has not seen from the platform.
  static const int mouseDevice = 0x5ea0;
  static const int touchDevice = 0x5ea1;

  /// Pointer ids well above the ones the engine hands out.
  int _nextPointer = 1 << 24;

  /// Where the injected mouse is while it stays over the app after a hover.
  Offset? _mousePosition;
  int? _mouseView;

  /// Waits between the steps of a gesture. A timer, so widget tests drive it
  /// by pumping time.
  Future<void> Function(Duration) wait = Future<void>.delayed;

  Duration get _now => Duration(microseconds: Timeline.now);

  void _send(PointerEvent event) =>
      GestureBinding.instance.handlePointerEvent(event);

  /// Moves the injected mouse to [position], adding it first if it is not
  /// over the app.
  void _moveMouse(Offset position, int viewId) {
    if (_mousePosition == null || _mouseView != viewId) {
      _removeMouse();
      _send(
        PointerAddedEvent(
          timeStamp: _now,
          kind: PointerDeviceKind.mouse,
          device: mouseDevice,
          position: position,
          viewId: viewId,
        ),
      );
    } else if (_mousePosition != position) {
      _send(
        PointerHoverEvent(
          timeStamp: _now,
          kind: PointerDeviceKind.mouse,
          device: mouseDevice,
          position: position,
          delta: position - _mousePosition!,
          viewId: viewId,
        ),
      );
    }
    _mousePosition = position;
    _mouseView = viewId;
  }

  void _removeMouse() {
    final position = _mousePosition;
    if (position == null) return;
    _send(
      PointerRemovedEvent(
        timeStamp: _now,
        kind: PointerDeviceKind.mouse,
        device: mouseDevice,
        position: position,
        viewId: _mouseView ?? 0,
      ),
    );
    _mousePosition = null;
    _mouseView = null;
  }

  /// Takes the injected mouse off the app, ending any hover it holds.
  void leave() => _removeMouse();

  /// Hovers the injected mouse at [position] and leaves it there.
  void hover(Offset position, {int viewId = 0}) => _moveMouse(position, viewId);

  /// Presses and releases at [position] [count] times, holding each press
  /// for [hold]. [buttons] is a mouse button mask ([kPrimaryButton],
  /// [kSecondaryButton]); a touch ignores it.
  Future<void> tap(
    Offset position, {
    int viewId = 0,
    PointerDeviceKind kind = PointerDeviceKind.mouse,
    int buttons = kPrimaryButton,
    int count = 1,
    Duration hold = const Duration(milliseconds: 40),
    Duration between = const Duration(milliseconds: 80),
    bool stayHovering = false,
  }) async {
    final mouse = kind == PointerDeviceKind.mouse;
    for (var i = 0; i < count; i++) {
      if (i > 0) await wait(between);
      final pointer = _nextPointer++;
      final device = mouse ? mouseDevice : touchDevice;
      if (mouse) _moveMouse(position, viewId);
      _send(
        PointerDownEvent(
          timeStamp: _now,
          pointer: pointer,
          kind: kind,
          device: device,
          position: position,
          buttons: mouse ? buttons : kPrimaryButton,
          viewId: viewId,
        ),
      );
      await wait(hold);
      _send(
        PointerUpEvent(
          timeStamp: _now,
          pointer: pointer,
          kind: kind,
          device: device,
          position: position,
          viewId: viewId,
        ),
      );
    }
    if (mouse && !stayHovering) _removeMouse();
  }

  /// Presses at [from], moves by [delta] in steps of [interval] over
  /// [duration], and releases.
  Future<void> drag(
    Offset from,
    Offset delta, {
    int viewId = 0,
    PointerDeviceKind kind = PointerDeviceKind.touch,
    Duration duration = const Duration(milliseconds: 300),
    Duration interval = const Duration(milliseconds: 16),
  }) async {
    final mouse = kind == PointerDeviceKind.mouse;
    final pointer = _nextPointer++;
    final device = mouse ? mouseDevice : touchDevice;
    if (mouse) _moveMouse(from, viewId);
    _send(
      PointerDownEvent(
        timeStamp: _now,
        pointer: pointer,
        kind: kind,
        device: device,
        position: from,
        buttons: kPrimaryButton,
        viewId: viewId,
      ),
    );
    final steps = (duration.inMicroseconds / interval.inMicroseconds)
        .ceil()
        .clamp(1, 1000);
    var position = from;
    for (var i = 1; i <= steps; i++) {
      await wait(interval);
      final next = from + delta * (i / steps);
      _send(
        PointerMoveEvent(
          timeStamp: _now,
          pointer: pointer,
          kind: kind,
          device: device,
          position: next,
          delta: next - position,
          buttons: kPrimaryButton,
          viewId: viewId,
        ),
      );
      position = next;
    }
    _send(
      PointerUpEvent(
        timeStamp: _now,
        pointer: pointer,
        kind: kind,
        device: device,
        position: position,
        viewId: viewId,
      ),
    );
    if (mouse) {
      _mousePosition = position;
      _removeMouse();
    }
  }

  /// Turns the mouse wheel over [position] by [delta] logical pixels, split
  /// into [steps] events [interval] apart.
  Future<void> scroll(
    Offset position,
    Offset delta, {
    int viewId = 0,
    int steps = 1,
    Duration interval = const Duration(milliseconds: 16),
  }) async {
    _moveMouse(position, viewId);
    for (var i = 0; i < steps; i++) {
      if (i > 0) await wait(interval);
      _send(
        PointerScrollEvent(
          timeStamp: _now,
          kind: PointerDeviceKind.mouse,
          device: mouseDevice,
          position: position,
          scrollDelta: delta / steps.toDouble(),
          viewId: viewId,
        ),
      );
    }
    _removeMouse();
  }

  /// Presses the chord [combo], such as `ctrl+shift+k`, `enter` or `a`:
  /// modifiers down in order, the key down and up, modifiers up. Returns
  /// whether anything in the app handled the key.
  bool pressKeys(String combo) {
    final parts = combo
        .toLowerCase()
        .split('+')
        .map((p) => p.trim())
        .where((p) => p.isNotEmpty)
        .toList();
    if (parts.isEmpty) throw ArgumentError('No key in "$combo"');
    final keys = [for (final p in parts) keyNamed(p)];
    var handled = false;
    for (final key in keys) {
      handled |= _sendKey(
        KeyDownEvent(
          physicalKey: key.$2,
          logicalKey: key.$1,
          character: key == keys.last && keys.length == 1 ? key.$3 : null,
          timeStamp: _now,
        ),
      );
    }
    for (final key in keys.reversed) {
      handled |= _sendKey(
        KeyUpEvent(physicalKey: key.$2, logicalKey: key.$1, timeStamp: _now),
      );
    }
    return handled;
  }

  /// Hands [event] to [HardwareKeyboard] (pressed-key state and its
  /// handlers) and to the focus system, the two places a platform key event
  /// goes.
  bool _sendKey(KeyEvent event) {
    final byKeyboard = HardwareKeyboard.instance.handleKeyEvent(event);
    // The focus system still listens through KeyEventManager.
    // ignore: deprecated_member_use
    final handler = ServicesBinding.instance.keyEventManager.keyMessageHandler;
    // ignore: deprecated_member_use
    final byFocus = handler?.call(KeyMessage([event], null)) ?? false;
    return byKeyboard || byFocus;
  }

  static final Map<String, (LogicalKeyboardKey, PhysicalKeyboardKey)> _named = {
    'enter': (LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter),
    'return': (LogicalKeyboardKey.enter, PhysicalKeyboardKey.enter),
    'escape': (LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape),
    'esc': (LogicalKeyboardKey.escape, PhysicalKeyboardKey.escape),
    'tab': (LogicalKeyboardKey.tab, PhysicalKeyboardKey.tab),
    'space': (LogicalKeyboardKey.space, PhysicalKeyboardKey.space),
    'backspace': (LogicalKeyboardKey.backspace, PhysicalKeyboardKey.backspace),
    'delete': (LogicalKeyboardKey.delete, PhysicalKeyboardKey.delete),
    'up': (LogicalKeyboardKey.arrowUp, PhysicalKeyboardKey.arrowUp),
    'down': (LogicalKeyboardKey.arrowDown, PhysicalKeyboardKey.arrowDown),
    'left': (LogicalKeyboardKey.arrowLeft, PhysicalKeyboardKey.arrowLeft),
    'right': (LogicalKeyboardKey.arrowRight, PhysicalKeyboardKey.arrowRight),
    'home': (LogicalKeyboardKey.home, PhysicalKeyboardKey.home),
    'end': (LogicalKeyboardKey.end, PhysicalKeyboardKey.end),
    'pageup': (LogicalKeyboardKey.pageUp, PhysicalKeyboardKey.pageUp),
    'pagedown': (LogicalKeyboardKey.pageDown, PhysicalKeyboardKey.pageDown),
    'ctrl': (LogicalKeyboardKey.controlLeft, PhysicalKeyboardKey.controlLeft),
    'control': (
      LogicalKeyboardKey.controlLeft,
      PhysicalKeyboardKey.controlLeft,
    ),
    'shift': (LogicalKeyboardKey.shiftLeft, PhysicalKeyboardKey.shiftLeft),
    'alt': (LogicalKeyboardKey.altLeft, PhysicalKeyboardKey.altLeft),
    'meta': (LogicalKeyboardKey.metaLeft, PhysicalKeyboardKey.metaLeft),
    'win': (LogicalKeyboardKey.metaLeft, PhysicalKeyboardKey.metaLeft),
    'cmd': (LogicalKeyboardKey.metaLeft, PhysicalKeyboardKey.metaLeft),
  };

  static const List<PhysicalKeyboardKey> _letters = [
    PhysicalKeyboardKey.keyA, PhysicalKeyboardKey.keyB, //
    PhysicalKeyboardKey.keyC, PhysicalKeyboardKey.keyD,
    PhysicalKeyboardKey.keyE, PhysicalKeyboardKey.keyF,
    PhysicalKeyboardKey.keyG, PhysicalKeyboardKey.keyH,
    PhysicalKeyboardKey.keyI, PhysicalKeyboardKey.keyJ,
    PhysicalKeyboardKey.keyK, PhysicalKeyboardKey.keyL,
    PhysicalKeyboardKey.keyM, PhysicalKeyboardKey.keyN,
    PhysicalKeyboardKey.keyO, PhysicalKeyboardKey.keyP,
    PhysicalKeyboardKey.keyQ, PhysicalKeyboardKey.keyR,
    PhysicalKeyboardKey.keyS, PhysicalKeyboardKey.keyT,
    PhysicalKeyboardKey.keyU, PhysicalKeyboardKey.keyV,
    PhysicalKeyboardKey.keyW, PhysicalKeyboardKey.keyX,
    PhysicalKeyboardKey.keyY, PhysicalKeyboardKey.keyZ,
  ];

  static const List<PhysicalKeyboardKey> _digits = [
    PhysicalKeyboardKey.digit0, PhysicalKeyboardKey.digit1, //
    PhysicalKeyboardKey.digit2, PhysicalKeyboardKey.digit3,
    PhysicalKeyboardKey.digit4, PhysicalKeyboardKey.digit5,
    PhysicalKeyboardKey.digit6, PhysicalKeyboardKey.digit7,
    PhysicalKeyboardKey.digit8, PhysicalKeyboardKey.digit9,
  ];

  static const List<PhysicalKeyboardKey> _functionKeys = [
    PhysicalKeyboardKey.f1, PhysicalKeyboardKey.f2, //
    PhysicalKeyboardKey.f3, PhysicalKeyboardKey.f4,
    PhysicalKeyboardKey.f5, PhysicalKeyboardKey.f6,
    PhysicalKeyboardKey.f7, PhysicalKeyboardKey.f8,
    PhysicalKeyboardKey.f9, PhysicalKeyboardKey.f10,
    PhysicalKeyboardKey.f11, PhysicalKeyboardKey.f12,
  ];

  /// The logical and physical key for a lower-case [name] (`enter`, `ctrl`,
  /// `f5`, `k`, `7`), and the character a lone press of it types.
  static (LogicalKeyboardKey, PhysicalKeyboardKey, String?) keyNamed(
    String name,
  ) {
    final named = _named[name];
    if (named != null) {
      return (named.$1, named.$2, name == 'space' ? ' ' : null);
    }
    if (name.length == 1) {
      final code = name.codeUnitAt(0);
      if (code >= 0x61 && code <= 0x7a) {
        return (LogicalKeyboardKey(code), _letters[code - 0x61], name);
      }
      if (code >= 0x30 && code <= 0x39) {
        return (LogicalKeyboardKey(code), _digits[code - 0x30], name);
      }
    }
    final f = RegExp(r'^f(\d{1,2})$').firstMatch(name);
    if (f != null) {
      final n = int.parse(f.group(1)!);
      if (n >= 1 && n <= 12) {
        final logical = [
          LogicalKeyboardKey.f1, LogicalKeyboardKey.f2, //
          LogicalKeyboardKey.f3, LogicalKeyboardKey.f4,
          LogicalKeyboardKey.f5, LogicalKeyboardKey.f6,
          LogicalKeyboardKey.f7, LogicalKeyboardKey.f8,
          LogicalKeyboardKey.f9, LogicalKeyboardKey.f10,
          LogicalKeyboardKey.f11, LogicalKeyboardKey.f12,
        ][n - 1];
        return (logical, _functionKeys[n - 1], null);
      }
    }
    throw ArgumentError('Unknown key "$name"');
  }

  /// Types [text] into the focused text field at its cursor, replacing the
  /// selection, the way an input method commits text. With [replace] the
  /// field's whole text is replaced. Returns false when no text field has
  /// focus.
  static bool typeText(String text, {bool replace = false}) {
    final state = focusedEditable();
    if (state == null) return false;
    final value = state.textEditingValue;
    final TextEditingValue next;
    if (replace) {
      next = TextEditingValue(
        text: text,
        selection: TextSelection.collapsed(offset: text.length),
      );
    } else {
      final sel = value.selection.isValid
          ? value.selection
          : TextSelection.collapsed(offset: value.text.length);
      final updated = value.text.replaceRange(sel.start, sel.end, text);
      next = TextEditingValue(
        text: updated,
        selection: TextSelection.collapsed(offset: sel.start + text.length),
      );
    }
    state.userUpdateTextEditingValue(next, SelectionChangedCause.keyboard);
    return true;
  }

  /// Sends the focused field's input action (what the keyboard's done or
  /// send key does). Returns false when no text field has focus.
  static bool submit() {
    final state = focusedEditable();
    if (state == null) return false;
    state.performAction(state.widget.textInputAction ?? TextInputAction.done);
    return true;
  }

  /// The [EditableTextState] that holds the primary focus, if any.
  static EditableTextState? focusedEditable() {
    final context = FocusManager.instance.primaryFocus?.context;
    if (context == null) return null;
    if (context is StatefulElement && context.state is EditableTextState) {
      return context.state as EditableTextState;
    }
    return context.findAncestorStateOfType<EditableTextState>();
  }

  /// Completes after the next frame has been drawn.
  static Future<void> nextFrame() {
    SchedulerBinding.instance.scheduleFrame();
    return SchedulerBinding.instance.endOfFrame;
  }
}
