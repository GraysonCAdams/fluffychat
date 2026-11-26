# window_manager 0.5.2, patched for FluffyChat

A copy of the pub.dev release (`lib/`, `windows/`, `linux/`, `macos/`), used
through `dependency_overrides` in the app's `pubspec.yaml`.

The Windows engine hands the messages of every top-level window to each
plugin's window procedure delegate, including the chat windows the app opens
through Flutter's windowing API (`lib/utils/chat_windows/`). Upstream treats
every one of them as the main window: with the main window's title bar hidden
it strips a chat window's native frame, swallows its activation repaint, and
reports its resizes and minimizes as the main window's.

The patch makes `WindowManagerPlugin::HandleWindowProc` in
`windows/window_manager_plugin.cpp` ignore messages for any window other than
the root window of the plugin registrar's view. The patched spot is marked
`FluffyChat:`. To move to a newer release, copy it over this one and reapply
that hunk.
