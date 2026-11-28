// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// Web build stand-in for `windows_clipboard_ffi.dart`, which needs
/// `dart:ffi`.
abstract final class WindowsClipboard {
  @visibleForTesting
  static int? debugSequenceNumber;
  @visibleForTesting
  static bool? debugHoldsEmojiPanelContent;

  static int get sequenceNumber => debugSequenceNumber ?? 0;

  static bool get holdsEmojiPanelContent =>
      debugHoldsEmojiPanelContent ?? false;
}
