// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluffychat/utils/ogg_opus_remuxer.dart';
import 'package:opus_codec_dart/opus_codec_dart.dart';

const whisperSampleRate = 16000;

/// Decodes an Ogg Opus file into the 16 kHz mono 16-bit WAV that whisper.cpp
/// reads. libopus resamples and downmixes by itself when the decoder is
/// opened at 16 kHz mono, so no separate resampler is needed.
///
/// `initOpus` must have been called before.
Uint8List oggOpusToWav(Uint8List ogg) {
  final packets = readOggPackets(ogg);
  if (packets.isEmpty || !_startsWith(packets.first, 'OpusHead')) {
    throw const FormatException('Not an Ogg Opus file');
  }
  final head = packets.first;
  // Mapping families above 0 are multistream, which SimpleOpusDecoder can
  // not decode. Voice messages are always mono or stereo.
  if (head.length < 19 || head[18] != 0) {
    throw const FormatException('Unsupported Opus channel mapping');
  }
  final preSkip =
      ByteData.sublistView(head).getUint16(10, Endian.little) *
      whisperSampleRate ~/
      48000;

  final decoder = SimpleOpusDecoder(sampleRate: whisperSampleRate, channels: 1);
  final chunks = <Int16List>[];
  try {
    for (final packet in packets.skip(1)) {
      if (packet.isEmpty || _startsWith(packet, 'OpusTags')) continue;
      chunks.add(decoder.decode(input: packet));
    }
  } finally {
    decoder.destroy();
  }

  final length = chunks.fold(0, (sum, chunk) => sum + chunk.length);
  final samples = Int16List(length);
  var offset = 0;
  for (final chunk in chunks) {
    samples.setAll(offset, chunk);
    offset += chunk.length;
  }
  return pcm16MonoWav(
    preSkip < samples.length
        ? Int16List.sublistView(samples, preSkip)
        : samples,
  );
}

Uint8List pcm16MonoWav(Int16List samples) {
  final dataLength = samples.length * 2;
  final header = ByteData(44)
    ..setUint32(4, 36 + dataLength, Endian.little)
    ..setUint32(16, 16, Endian.little)
    ..setUint16(20, 1, Endian.little) // PCM
    ..setUint16(22, 1, Endian.little) // mono
    ..setUint32(24, whisperSampleRate, Endian.little)
    ..setUint32(28, whisperSampleRate * 2, Endian.little)
    ..setUint16(32, 2, Endian.little)
    ..setUint16(34, 16, Endian.little)
    ..setUint32(40, dataLength, Endian.little);
  final bytes = header.buffer.asUint8List();
  bytes.setAll(0, ascii.encode('RIFF'));
  bytes.setAll(8, ascii.encode('WAVEfmt '));
  bytes.setAll(36, ascii.encode('data'));

  final pcm = ByteData(dataLength);
  for (var i = 0; i < samples.length; i++) {
    pcm.setInt16(i * 2, samples[i], Endian.little);
  }
  return (BytesBuilder(copy: false)
        ..add(bytes)
        ..add(pcm.buffer.asUint8List()))
      .takeBytes();
}

bool isOggFile(Uint8List data) => _startsWith(data, 'OggS');

bool _startsWith(Uint8List data, String magic) {
  if (data.length < magic.length) return false;
  for (var i = 0; i < magic.length; i++) {
    if (data[i] != magic.codeUnitAt(i)) return false;
  }
  return true;
}
