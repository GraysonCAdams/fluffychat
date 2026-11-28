// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:matrix/matrix.dart';

/// The operating system's own emoji picker, which types into the text field
/// that has focus.
///
/// Windows has its emoji panel (Win+.) and macOS its Character Viewer, and
/// an app can open both. Android and iOS keep their emoji in the keyboard,
/// and neither has a public API to switch the keyboard to them; Linux has no
/// picker an app can open. There the picker is not [supported].
abstract final class NativeEmojiPicker {
  /// Stands in for the platform, for tests.
  @visibleForTesting
  static bool? debugSupported;

  static bool get supported =>
      debugSupported ?? (Platform.isWindows || Platform.isMacOS);

  /// Answered by the macOS runner, which opens the Character Viewer.
  static const _macChannel = MethodChannel(
    'chat.fluffy.fluffychat/emoji_palette',
  );

  /// Opens the picker. The caller gives the text field focus first, since
  /// the picker types where focus is.
  static Future<void> open() async {
    try {
      if (Platform.isWindows) {
        _pressWinPeriod();
      } else if (Platform.isMacOS) {
        await _macChannel.invokeMethod<void>('open');
      }
    } catch (e, s) {
      Logs().w('Unable to open the emoji picker', e, s);
    }
  }

  static final _sendInput = DynamicLibrary.open('user32.dll')
      .lookupFunction<
        Uint32 Function(Uint32, Pointer<Uint8>, Int32),
        int Function(int, Pointer<Uint8>, int)
      >('SendInput');

  /// Presses and releases Win+. as the keyboard would. Windows answers it
  /// by opening its emoji panel at the caret.
  static void _pressWinPeriod() {
    const leftWindows = 0x5B; // VK_LWIN
    const period = 0xBE; // VK_OEM_PERIOD
    const keyUp = 0x0002; // KEYEVENTF_KEYUP
    const keyboard = 1; // INPUT_KEYBOARD
    // An INPUT on 64 bit Windows is 40 bytes: a 4 byte type, 4 of padding,
    // then the union, as large as its largest member, MOUSEINPUT. The
    // KEYBDINPUT in it starts with wVk (2 bytes), wScan (2) and dwFlags (4).
    const size = 40;
    const keys = [
      (leftWindows, 0),
      (period, 0),
      (period, keyUp),
      (leftWindows, keyUp),
    ];
    final inputs = calloc<Uint8>(size * keys.length);
    try {
      final data = ByteData.sublistView(inputs.asTypedList(size * keys.length));
      for (final (i, (key, flags)) in keys.indexed) {
        data.setUint32(i * size, keyboard, Endian.little);
        data.setUint16(i * size + 8, key, Endian.little);
        data.setUint32(i * size + 12, flags, Endian.little);
      }
      _sendInput(keys.length, inputs, size);
    } finally {
      calloc.free(inputs);
    }
  }
}
