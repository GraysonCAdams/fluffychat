// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

/// The binary payload of a Matrix verification QR code (MSC1543: "MATRIX",
/// a version byte, a mode byte, the transaction ID, two keys and a
/// secret) from what a scanner reports.
///
/// Scanners report a code as text decoded in a guessed character set, and
/// on Android and iOS also as its raw data codewords. The payload is binary,
/// so the text is only right when the guess was ISO-8859-1. The codewords
/// hold it exactly: a byte-mode segment, a 4-bit mode indicator (0100), a
/// character count of 8 bits (versions 1 to 9) or 16 bits (10 to 40), then
/// the bytes. The version is not reported, so both counts are tried, and the
/// first reading that starts with "MATRIX" wins. Null if none does.
Uint8List? matrixQrPayload({String? text, List<int>? rawBytes}) {
  final raw = rawBytes;
  if (raw != null) {
    for (final countBits in const [8, 16]) {
      final payload = _byteSegment(raw, countBits);
      if (payload != null && _isMatrix(payload)) return payload;
    }
  }
  if (text != null && text.codeUnits.every((unit) => unit < 256)) {
    final payload = Uint8List.fromList(latin1.encode(text));
    if (_isMatrix(payload)) return payload;
  }
  return null;
}

const _prefix = [0x4D, 0x41, 0x54, 0x52, 0x49, 0x58]; // MATRIX

bool _isMatrix(Uint8List payload) {
  // Prefix, version, mode and the transaction ID's length.
  if (payload.length < _prefix.length + 4) return false;
  for (var i = 0; i < _prefix.length; i++) {
    if (payload[i] != _prefix[i]) return false;
  }
  return true;
}

Uint8List? _byteSegment(List<int> codewords, int countBits) {
  var bit = 0;
  int? read(int length) {
    if (bit + length > codewords.length * 8) return null;
    var value = 0;
    for (var i = 0; i < length; i++, bit++) {
      final byte = codewords[bit >> 3];
      value = (value << 1) | ((byte >> (7 - (bit & 7))) & 1);
    }
    return value;
  }

  if (read(4) != 0x4) return null; // not byte mode
  final count = read(countBits);
  if (count == null || count == 0) return null;
  final bytes = Uint8List(count);
  for (var i = 0; i < count; i++) {
    final byte = read(8);
    if (byte == null) return null;
    bytes[i] = byte;
  }
  return bytes;
}
