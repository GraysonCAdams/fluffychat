// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// The one menu open from the chat list's header or the Windows title bar:
/// the chat filter, the account menu and the Search in menu.
///
/// These menus open on the chat list's navigator, whose modal barrier
/// covers the app's pages but not the Windows title bar drawn above them.
/// So a click on the bar would reach the bar: its anchor would open a
/// second menu over the first, and the part that moves the window would
/// leave the menu open. Opening every such menu through [show] keeps one
/// open at a time: a click on its anchor, or on another anchor, closes it,
/// as a click on the barrier does. The title bar lays [barrier] over itself
/// while a menu is open, and closes it when the window loses focus.
abstract final class HeaderMenu {
  /// The anchor whose menu is open, or null.
  static final ValueNotifier<Object?> open = ValueNotifier(null);

  static Route<Object?>? _route;

  /// Whether the menu of [anchor] is open.
  static bool isOpen(Object anchor) => open.value == anchor && _isUp;

  static bool get _isUp => _route?.isActive ?? false;

  /// Opens a menu for [anchor] with [showMenu], which pushes it on
  /// [navigator] at once (as `showMenu` does), and completes with its
  /// result. While any of these menus is open it instead closes that menu
  /// and completes with null.
  static Future<T?> show<T>({
    required Object anchor,
    required NavigatorState navigator,
    required Future<T?> Function() showMenu,
  }) async {
    if (_isUp) {
      close();
      return null;
    }
    final result = showMenu();
    Route<Object?>? route;
    // The top route, which is the menu just pushed; nothing is popped.
    navigator.popUntil((top) {
      route = top;
      return true;
    });
    // Never a page, which closing the menu would pop.
    if (route is! PopupRoute) return result;
    _route = route;
    open.value = anchor;
    try {
      return await result;
    } finally {
      if (_route == route) {
        _route = null;
        open.value = null;
      }
    }
  }

  /// Closes the open menu, if any, as a click outside it would.
  static void close() {
    final route = _route;
    _route = null;
    open.value = null;
    if (route == null || !route.isActive) return;
    final navigator = route.navigator!;
    if (route.isCurrent) {
      navigator.pop();
    } else {
      navigator.removeRoute(route);
    }
  }

  /// Covers [child] while a menu is open, so that a click on it closes the
  /// menu and goes no further.
  static Widget barrier({required Widget child}) => ValueListenableBuilder(
    valueListenable: open,
    builder: (context, anchor, child) => Stack(
      children: [
        child!,
        if (anchor != null && _isUp)
          Positioned.fill(
            child: Listener(
              behavior: HitTestBehavior.opaque,
              onPointerDown: (_) => close(),
            ),
          ),
      ],
    ),
    child: child,
  );
}
