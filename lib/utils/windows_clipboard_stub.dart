// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

/// Web build stand-in for `windows_clipboard_ffi.dart`, which needs
/// `dart:ffi`.
abstract final class WindowsClipboard {
  static int get sequenceNumber => 0;

  static bool get holdsEmojiPanelContent => false;
}
