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
