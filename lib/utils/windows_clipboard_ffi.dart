// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';

/// Clipboard queries that Flutter has no API for, made through Win32 over
/// FFI. Both getters are cheap enough to poll.
abstract final class WindowsClipboard {
  static final _user32 = DynamicLibrary.open('user32.dll');

  static final _getClipboardSequenceNumber = _user32
      .lookupFunction<Uint32 Function(), int Function()>(
        'GetClipboardSequenceNumber',
      );
  static final _isClipboardFormatAvailable = _user32
      .lookupFunction<Int32 Function(Uint32), int Function(int)>(
        'IsClipboardFormatAvailable',
      );
  static final _registerClipboardFormat = _user32
      .lookupFunction<
        Uint32 Function(Pointer<Utf16>),
        int Function(Pointer<Utf16>)
      >('RegisterClipboardFormatW');

  /// The format Windows' own input surfaces, such as the emoji panel, tag
  /// their clipboard writes with.
  static final int _systemInputFormat = using(
    (arena) => _registerClipboardFormat(
      'SystemInputDataTransferContent'.toNativeUtf16(allocator: arena),
    ),
  );

  /// Changes whenever anything writes to the clipboard; 0 off Windows.
  static int get sequenceNumber =>
      Platform.isWindows ? _getClipboardSequenceNumber() : 0;

  /// Whether the clipboard was last written by the emoji panel (Win+.),
  /// which copies a picked GIF there but never pastes it into a Flutter
  /// window.
  static bool get holdsEmojiPanelContent =>
      Platform.isWindows &&
      _isClipboardFormatAvailable(_systemInputFormat) != 0;
}
