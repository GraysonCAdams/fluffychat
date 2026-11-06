// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// Android Direct Share: conversation shortcuts appear in the system share
/// sheet, and picking one names its room (see `MainActivity.kt`).
abstract final class AndroidDirectShare {
  static const _channel = MethodChannel('chat.fluffy.fluffychat/share');

  /// The room picked in the share sheet for the share being received, if any.
  static Future<String?> takeTargetRoomId() async {
    if (!PlatformInfos.isAndroid) return null;
    try {
      return await _channel.invokeMethod<String>('takeShareTargetRoom');
    } catch (e, s) {
      Logs().w('Unable to ask for the Direct Share target', e, s);
      return null;
    }
  }
}
