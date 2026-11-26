// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat_windows/chat_windows.dart';
import 'package:material_ui/material_ui.dart';

/// Above everything a chat window shows: which chat it is and its native
/// window.
class ChatWindowScope extends InheritedWidget {
  final ChatWindowTarget target;
  final ChatWindowHandle handle;

  const ChatWindowScope({
    required this.target,
    required this.handle,
    required super.child,
    super.key,
  });

  static ChatWindowScope? maybeOf(BuildContext context) =>
      context.getInheritedWidgetOfExactType<ChatWindowScope>();

  /// Whether [context] is inside a chat window rather than the main window.
  static bool isChatWindow(BuildContext context) => maybeOf(context) != null;

  @override
  bool updateShouldNotify(ChatWindowScope oldWidget) =>
      target != oldWidget.target || handle != oldWidget.handle;
}

/// Renders each window in [ChatWindows.instance] into its own view, with
/// what [windowBuilder] builds for its chat, and [child] in the main window.
/// The windows sit below this widget in the tree, so they see the same
/// inherited state as [child] does here: the Matrix clients above all.
class ChatWindowsHost extends StatefulWidget {
  final Widget child;
  final Widget Function(BuildContext context, ChatWindowTarget target)
  windowBuilder;

  const ChatWindowsHost({
    required this.windowBuilder,
    required this.child,
    super.key,
  });

  @override
  State<ChatWindowsHost> createState() => _ChatWindowsHostState();
}

class _ChatWindowsHostState extends State<ChatWindowsHost> {
  @override
  void initState() {
    super.initState();
    ChatWindows.instance.addListener(_onWindowsChanged);
  }

  @override
  void dispose() {
    ChatWindows.instance.removeListener(_onWindowsChanged);
    super.dispose();
  }

  void _onWindowsChanged() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final windows = ChatWindows.instance.windows;
    return ViewAnchor(
      view: windows.isEmpty
          ? null
          : ViewCollection(
              views: [
                for (final MapEntry(key: target, value: handle)
                    in windows.entries)
                  View(
                    key: ObjectKey(handle),
                    view: handle.view,
                    child: ChatWindowScope(
                      target: target,
                      handle: handle,
                      child: Builder(
                        builder: (context) =>
                            widget.windowBuilder(context, target),
                      ),
                    ),
                  ),
              ],
            ),
      child: widget.child,
    );
  }
}

/// Keeps a chat window's native title bar in step with the theme of
/// [child], as `WindowsTitleBarSync` does for the main window.
class ChatWindowTitleBarSync extends StatelessWidget {
  final Widget child;

  const ChatWindowTitleBarSync({required this.child, super.key});

  @override
  Widget build(BuildContext context) {
    final handle = ChatWindowScope.maybeOf(context)?.handle;
    if (handle == null) return child;
    final theme = Theme.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // The window may have closed since this frame was built.
      if (!ChatWindows.instance.windows.containsValue(handle)) return;
      handle.setTitleBarColors(
        brightness: theme.brightness,
        caption: theme.colorScheme.surface,
        text: theme.colorScheme.onSurface,
      );
    });
    return child;
  }
}
