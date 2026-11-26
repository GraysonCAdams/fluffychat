// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// Flutter's windowing API is experimental and internal: it lives under
// `src/` and is gated by a feature flag.
// ignore_for_file: implementation_imports, invalid_use_of_internal_member

import 'dart:ffi' hide Size;
import 'dart:io';
import 'dart:ui' show Brightness, Color, FlutterView, Size;

import 'package:ffi/ffi.dart';
import 'package:fluffychat/utils/chat_windows/chat_windows.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/src/foundation/_features.dart' as features;
import 'package:flutter/src/widgets/_window.dart';
import 'package:flutter/src/widgets/_window_win32.dart';

/// The backend for this platform: Win32 windows on Windows, none elsewhere.
ChatWindowBackend? createChatWindowBackend() =>
    Platform.isWindows ? Win32ChatWindowBackend() : null;

/// Opens chat windows through the Windows engine's windowing API, in this
/// engine and isolate, so every window shares the app's Matrix clients.
///
/// The app is built without the `enable-windowing` flag: with it, every
/// `showDialog` would open a native dialog window instead of an in-app
/// dialog. The flag's runtime switch, [features.isWindowingEnabled], is
/// turned on only while the windowing objects are constructed, the one
/// place the API checks it for what is used here.
class Win32ChatWindowBackend implements ChatWindowBackend {
  WindowingOwnerWin32? _owner;

  static T _withWindowing<T>(T Function() create) {
    final enabled = features.isWindowingEnabled;
    features.isWindowingEnabled = true;
    try {
      return create();
    } finally {
      features.isWindowingEnabled = enabled;
    }
  }

  @override
  ChatWindowHandle create({
    required Size size,
    required String title,
    required VoidCallback onCloseRequested,
    required VoidCallback onDestroyed,
    required VoidCallback onChanged,
  }) {
    final owner = _owner ??= _withWindowing<WindowingOwnerWin32>(
      WindowingOwnerWin32.new,
    );
    final controller = _withWindowing(
      () => RegularWindowControllerWin32(
        owner: owner,
        delegate: _Delegate(onCloseRequested, onDestroyed),
        size: size,
        title: title,
        resizable: true,
      ),
    );
    controller.addListener(onChanged);
    return _Win32ChatWindow(controller);
  }
}

/// Hands the window's close request and destruction to [ChatWindows]. The
/// mixin's own implementations are not called: they throw while the
/// windowing flag is off.
class _Delegate with RegularWindowControllerDelegate {
  final VoidCallback onCloseRequested;
  final VoidCallback onDestroyed;

  _Delegate(this.onCloseRequested, this.onDestroyed);

  @override
  void onWindowCloseRequested(RegularWindowController controller) =>
      onCloseRequested();

  @override
  void onWindowDestroyed() => onDestroyed();
}

class _Win32ChatWindow implements ChatWindowHandle {
  final RegularWindowControllerWin32 controller;

  _Win32ChatWindow(this.controller);

  static final _user32 = DynamicLibrary.open('user32.dll');
  static final _dwmapi = DynamicLibrary.open('dwmapi.dll');
  static final _setForegroundWindow = _user32
      .lookupFunction<Int32 Function(Pointer), int Function(Pointer)>(
        'SetForegroundWindow',
      );
  static final _dwmSetWindowAttribute = _dwmapi
      .lookupFunction<
        Int32 Function(Pointer, Uint32, Pointer, Uint32),
        int Function(Pointer, int, Pointer, int)
      >('DwmSetWindowAttribute');

  static const _dwmwaUseImmersiveDarkMode = 20;
  static const _dwmwaCaptionColor = 35;
  static const _dwmwaTextColor = 36;

  String? _lastCaption;

  @override
  FlutterView get view => controller.rootView;

  @override
  Size get contentSize => controller.contentSize;

  @override
  bool get isMinimized => controller.isMinimized;

  @override
  bool get isMaximized => controller.isMaximized;

  @override
  void focus() {
    // Restoring only a minimized window keeps a maximized one maximized.
    if (controller.isMinimized) controller.setMinimized(false);
    _setForegroundWindow(controller.windowHandle);
  }

  @override
  void setTitleBarColors({
    required Brightness brightness,
    required Color caption,
    required Color text,
  }) {
    final key = '$brightness ${caption.toARGB32()} ${text.toARGB32()}';
    if (key == _lastCaption) return;
    _lastCaption = key;
    final hwnd = controller.windowHandle;
    final value = calloc<Uint32>();
    try {
      value.value = brightness == Brightness.dark ? 1 : 0;
      _dwmSetWindowAttribute(hwnd, _dwmwaUseImmersiveDarkMode, value, 4);
      value.value = _colorRef(caption);
      _dwmSetWindowAttribute(hwnd, _dwmwaCaptionColor, value, 4);
      value.value = _colorRef(text);
      _dwmSetWindowAttribute(hwnd, _dwmwaTextColor, value, 4);
    } finally {
      calloc.free(value);
    }
  }

  /// A Win32 COLORREF, 0x00BBGGRR.
  static int _colorRef(Color color) =>
      ((color.b * 255).round() << 16) |
      ((color.g * 255).round() << 8) |
      (color.r * 255).round();

  @override
  void destroy() => controller.destroy();
}
