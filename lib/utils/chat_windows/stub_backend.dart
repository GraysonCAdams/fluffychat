// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/chat_windows/chat_windows.dart';

/// Web build stand-in for `win32_backend.dart`, which needs `dart:ffi`: the
/// web app has no windows of its own.
ChatWindowBackend? createChatWindowBackend() => null;
