// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:material_ui/material_ui.dart';

/// Web build stand-in for `windows_shell_ffi.dart`, which needs `dart:ffi`.
class WindowsTitleBarSync extends StatelessWidget {
  final Widget child;

  const WindowsTitleBarSync({required this.child, super.key});

  @override
  Widget build(BuildContext context) => child;
}

class WindowsChrome extends StatelessWidget {
  final Widget child;
  final VoidCallback showChatList;

  const WindowsChrome({
    required this.child,
    required this.showChatList,
    super.key,
  });

  static const double height = 0;

  static final covers = ValueNotifier<int>(0);

  @override
  Widget build(BuildContext context) => child;
}

class WindowButtons extends StatelessWidget {
  const WindowButtons({super.key});

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

class WindowMoveArea extends StatelessWidget {
  final Widget child;

  const WindowMoveArea({required this.child, super.key});

  @override
  Widget build(BuildContext context) => child;
}

abstract final class WindowFullScreen {
  static Future<bool> get isOn async => false;

  static Future<void> set(bool on) async {}
}

Future<void> updateWindowsTaskbarBadge(
  BuildContext context,
  int unreadChats,
) async {}

abstract final class WindowsDesktop {
  static const startHiddenArgument = '--hidden';

  static Future<void> init(List<String> args, Object l10n) async {}

  static void setLaunchAtStartup(bool enabled) {}

  static Future<void> showWindow() async {}
}
