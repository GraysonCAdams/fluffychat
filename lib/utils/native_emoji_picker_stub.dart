// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

/// The operating system's own emoji picker, which the web does not have
/// (see the FFI version).
abstract final class NativeEmojiPicker {
  @visibleForTesting
  static bool? debugSupported;

  static bool get supported => debugSupported ?? false;

  @visibleForTesting
  static Future<void> Function()? debugOpen;

  static Future<void> open() async => debugOpen?.call();
}
