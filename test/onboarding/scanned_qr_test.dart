// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/pages/key_verification/scanned_qr.dart';
import 'package:flutter_test/flutter_test.dart';

/// Data codewords for one byte-mode segment, as a scanner reports them.
List<int> codewords(List<int> payload, {required int countBits}) {
  final bits = <int>[];
  void put(int value, int length) {
    for (var i = length - 1; i >= 0; i--) {
      bits.add((value >> i) & 1);
    }
  }

  put(0x4, 4);
  put(payload.length, countBits);
  for (final byte in payload) {
    put(byte, 8);
  }
  put(0, 4); // terminator
  while (bits.length % 8 != 0) {
    bits.add(0);
  }
  final out = <int>[];
  for (var i = 0; i < bits.length; i += 8) {
    var byte = 0;
    for (var j = 0; j < 8; j++) {
      byte = (byte << 1) | bits[i + j];
    }
    out.add(byte);
  }
  // Pad codewords fill the rest of the symbol.
  return [...out, 0xEC, 0x11, 0xEC, 0x11];
}

void main() {
  // "MATRIX", version 2, mode 0, a 4-byte transaction ID, then binary
  // bytes that are not valid UTF-8.
  final payload = [
    ...ascii.encode('MATRIX'),
    0x02,
    0x00,
    0x00,
    0x04,
    ...ascii.encode('txn1'),
    for (var i = 0; i < 72; i++) (i * 37 + 200) % 256,
  ];

  test('reads the payload from codewords with an 8-bit count', () {
    expect(
      matrixQrPayload(rawBytes: codewords(payload, countBits: 8)),
      payload,
    );
  });

  test('reads the payload from codewords with a 16-bit count', () {
    expect(
      matrixQrPayload(rawBytes: codewords(payload, countBits: 16)),
      payload,
    );
  });

  test('falls back to text decoded as ISO-8859-1', () {
    expect(matrixQrPayload(text: latin1.decode(payload)), payload);
  });

  test('anything else is not a verification code', () {
    expect(
      matrixQrPayload(text: 'https://matrix.to/#/@alex:matrix.org'),
      isNull,
    );
    expect(
      matrixQrPayload(rawBytes: codewords(ascii.encode('hello'), countBits: 8)),
      isNull,
    );
  });
}
