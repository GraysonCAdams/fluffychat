// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

export 'windows_clipboard_stub.dart'
    if (dart.library.ffi) 'windows_clipboard_ffi.dart';
