// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:fluffychat/utils/chat_windows/chat_windows.dart';

/// A chat window that only records what is asked of it.
class FakeChatWindow implements ChatWindowHandle {
  FakeChatWindow({
    required this.size,
    required this.title,
    required this.onCloseRequested,
    required this.onDestroyed,
    required this.onChanged,
  });

  Size size;
  final String title;
  final VoidCallback onCloseRequested;
  final VoidCallback onDestroyed;
  final VoidCallback onChanged;

  bool minimized = false;
  bool maximized = false;
  bool destroyed = false;
  int focusCount = 0;

  /// Resizes the window as the user would, dragging its frame.
  void resize(Size newSize) {
    size = newSize;
    onChanged();
  }

  @override
  FlutterView get view => throw UnimplementedError('No views in tests');

  @override
  Size get contentSize => size;

  @override
  bool get isMinimized => minimized;

  @override
  bool get isMaximized => maximized;

  @override
  void focus() => focusCount++;

  @override
  void setTitleBarColors({
    required Brightness brightness,
    required Color caption,
    required Color text,
  }) {}

  @override
  void destroy() {
    if (destroyed) return;
    destroyed = true;
    onDestroyed();
  }
}

/// Opens [FakeChatWindow]s and keeps every one it opened.
class FakeChatWindowBackend implements ChatWindowBackend {
  final windows = <FakeChatWindow>[];

  @override
  ChatWindowHandle create({
    required Size size,
    required String title,
    required VoidCallback onCloseRequested,
    required VoidCallback onDestroyed,
    required VoidCallback onChanged,
  }) {
    final window = FakeChatWindow(
      size: size,
      title: title,
      onCloseRequested: onCloseRequested,
      onDestroyed: onDestroyed,
      onChanged: onChanged,
    );
    windows.add(window);
    return window;
  }
}

/// Puts a [FakeChatWindowBackend] behind [ChatWindows.instance].
FakeChatWindowBackend installFakeChatWindows() {
  final backend = FakeChatWindowBackend();
  ChatWindows.instance.backend = backend;
  return backend;
}

/// Closes what a test left open and takes the backend away again.
void removeFakeChatWindows() {
  ChatWindows.instance.closeAll();
  ChatWindows.instance.backend = null;
}
