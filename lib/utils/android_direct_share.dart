// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// Android Direct Share: conversation shortcuts appear in the system share
/// sheet (published by `AndroidShareTargets` and by message notifications),
/// and picking one names its shortcut (see `MainActivity.kt`). Once a share
/// is sent or left, Seam returns to the app that shared.
abstract final class AndroidDirectShare {
  static const _channel = MethodChannel('chat.fluffy.fluffychat/share');

  /// Set by tests to use the channel off Android; null asks the platform.
  @visibleForTesting
  static bool? debugIsAndroid;

  static bool get _isAndroid => debugIsAndroid ?? PlatformInfos.isAndroid;

  /// The shortcut ID picked in the share sheet for the share being received,
  /// if any: a room ID, or `contact_<id>` for a merged contact. Turn it into
  /// a route with `shareTargetRoute`.
  static Future<String?> takeTargetShortcutId() async {
    if (!PlatformInfos.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takeShareTarget');
    } catch (e, s) {
      Logs().w('Unable to ask for the Direct Share target', e, s);
      return null;
    }
  }

  /// Puts Seam behind the app that shared into it, after a share from the
  /// share sheet was sent or abandoned, and shows [toast] when given as a
  /// system toast, which stays visible once Seam is gone. Seam's activity
  /// is single-task, so moving its task back reveals the sharing app.
  static Future<void> returnToSourceApp({String? toast}) async {
    if (!_isAndroid) return;
    try {
      await _channel.invokeMethod<void>('returnToSourceApp', {'toast': toast});
    } catch (e, s) {
      Logs().w('Unable to return to the sharing app', e, s);
    }
  }
}
