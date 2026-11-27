// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// A page whose screen already covers the window when it opens, such as
/// the chat a peek card grew into (see `showChatPeek`): its page then
/// enters without a transition, so nothing slides in over the card.
abstract final class PageHandoff {
  static bool _pending = false;

  /// Makes the next page built with a handoff (see `AppRoutes`) enter at
  /// once. Called just before navigating; [cancel] drops it when no such
  /// page was built.
  static void expect() => _pending = true;

  static void cancel() => _pending = false;

  /// Whether a handoff is expected, which it no longer is after this.
  static bool take() {
    final pending = _pending;
    _pending = false;
    return pending;
  }
}

/// A [MaterialPage] that can enter without a transition. It leaves with
/// the usual one, as going back from it is an ordinary pop.
class HandoffPage<T> extends MaterialPage<T> {
  /// Whether the route made from this page enters at once. Read when the
  /// route is created; later pages for the same route do not change it.
  final bool enterInstantly;

  const HandoffPage({
    required super.child,
    this.enterInstantly = false,
    super.key,
    super.restorationId,
  });

  @override
  Route<T> createRoute(BuildContext context) =>
      _HandoffPageRoute<T>(page: this, enterInstantly: enterInstantly);
}

class _HandoffPageRoute<T> extends PageRoute<T>
    with MaterialRouteTransitionMixin<T> {
  final bool enterInstantly;

  _HandoffPageRoute({
    required HandoffPage<T> page,
    required this.enterInstantly,
  }) : super(settings: page);

  HandoffPage<T> get _page => settings as HandoffPage<T>;

  @override
  Widget buildContent(BuildContext context) => _page.child;

  @override
  bool get maintainState => _page.maintainState;

  @override
  bool get fullscreenDialog => _page.fullscreenDialog;

  @override
  String get debugLabel => '${super.debugLabel}(${_page.name})';

  @override
  Duration get transitionDuration =>
      enterInstantly ? Duration.zero : super.transitionDuration;

  @override
  Duration get reverseTransitionDuration => super.transitionDuration;
}
