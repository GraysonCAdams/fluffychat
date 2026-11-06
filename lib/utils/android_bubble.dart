// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Android chat bubbles run on the same Flutter engine as the main window
/// (see `BubbleActivity.kt`), so the bubble tells Dart which room to show.
abstract final class AndroidBubble {
  static const _channel = MethodChannel('chat.fluffy.fluffychat/bubble');

  /// The activity class that notifications name as their bubble.
  static const activityClass = 'chat.fluffy.fluffychat.BubbleActivity';

  /// Whether the app is currently drawn inside a chat bubble.
  static final isActive = ValueNotifier<bool>(false);

  static void init(GoRouter router) {
    if (!PlatformInfos.isAndroid) return;
    _channel.setMethodCallHandler((call) async {
      switch (call.method) {
        case 'openRoom':
          _openRoom(router, call.arguments as String);
        case 'leaveBubble':
          isActive.value = false;
      }
    });
    // A bubble opened while the app was closed starts the engine itself, and
    // its first openRoom call can arrive before this handler exists.
    _channel
        .invokeMethod<String>('takePendingRoom')
        .then((roomId) {
          if (roomId != null) _openRoom(router, roomId);
        })
        .catchError((Object e, StackTrace s) {
          Logs().w('Unable to ask for a pending bubble room', e, s);
        });
  }

  static void _openRoom(GoRouter router, String roomId) {
    isActive.value = true;
    router.go('/rooms/$roomId');
  }
}
