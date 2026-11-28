// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:typed_data';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

/// Whether a bridged attachment is still on its way or never arrived.
enum PendingMediaState { pending, failed }

/// What a bridged attachment will be, from its file name.
enum PendingMediaKind { image, video, file }

/// A photo or video the Google Messages bridge (mautrix-gmessages) has not
/// fetched yet, or could not.
///
/// The bridge sends such a message as an `m.notice` reading "Waiting for
/// attachment" and the file name, and replaces it with an `m.replace` edit
/// carrying the media once it has downloaded it, or with a notice reading
/// "Failed to transfer attachment" and the name. Seam draws a media tile in its place
/// instead of the text.
class PendingMedia {
  final PendingMediaState state;
  final PendingMediaKind kind;

  /// The attachment's file name, as the bridge gives it in the notice.
  final String fileName;

  /// Width over height of the full media, from the bridge's debug data,
  /// when it is there and plausible. The tile takes this shape instead of
  /// 4:3, so the media does not change shape when it arrives.
  final double? aspectRatio;

  /// A low-resolution JPEG of the media (a poster frame for a video), from
  /// the bridge's debug data, which the tile shows blurred while it waits.
  final Uint8List? preview;

  const PendingMedia({
    required this.state,
    required this.kind,
    required this.fileName,
    this.aspectRatio,
    this.preview,
  });

  /// The key the bridge sets on a placeholder (mautrix-gmessages PR #179).
  static const pendingKey = 'fi.mau.gmessages.media_pending';

  /// The base64 of the Google Messages payload the bridge attaches, for
  /// debugging, to the first event of a message, while it is under 8192
  /// characters. Not a stable format.
  static const rawDebugDataKey = 'fi.mau.gmessages.raw_debug_data';

  static const _waitingPrefix = 'Waiting for attachment ';
  static const _failedPrefix = 'Failed to transfer attachment ';

  /// Previews larger than this are ignored rather than decoded; the
  /// bridge's are about 3 KB.
  static const maxPreviewBytes = 16 * 1024;

  /// The pending media [event] stands for, or null when it is an ordinary
  /// message. [event] is the message as shown, with any edit applied.
  static PendingMedia? of(Event event) {
    if (event.type != EventTypes.Message ||
        event.messageType != MessageTypes.Notice ||
        event.redacted) {
      return null;
    }
    final content = event.content;
    final body = event.body;
    final rawDebugData = content.tryGet<String>(rawDebugDataKey);
    // The bridge's ghosts, one per Google Messages contact.
    final fromBridge = event.senderId.startsWith('@gmessages_');

    final PendingMediaState state;
    final String fileName;
    if (content[pendingKey] == true) {
      state = PendingMediaState.pending;
      fileName = body.startsWith(_waitingPrefix)
          ? body.substring(_waitingPrefix.length)
          : '';
    } else if (body.startsWith(_waitingPrefix) &&
        fromBridge &&
        rawDebugData != null) {
      state = PendingMediaState.pending;
      fileName = body.substring(_waitingPrefix.length);
    } else if (body.startsWith(_failedPrefix) &&
        (fromBridge || rawDebugData != null)) {
      state = PendingMediaState.failed;
      fileName = body.substring(_failedPrefix.length);
    } else {
      return null;
    }

    final media = rawDebugData == null
        ? null
        : GmessagesMediaContent.find(rawDebugData, fileName);
    return PendingMedia(
      state: state,
      kind: _kindOf(fileName, media?.mimeType),
      fileName: fileName,
      aspectRatio: media?.aspectRatio,
      preview: state == PendingMediaState.pending ? media?.preview : null,
    );
  }

  /// How a preview of the message reads, in the chat list and in a
  /// notification: as a photo or video message reads ("Photo", "Video"),
  /// a file by its name, and a failed transfer as such. Google Messages
  /// often names an attachment by a number with no extension, which says
  /// nothing about it, so such a file reads "Attachment".
  String previewText(L10n l10n) => switch ((state, kind)) {
    (PendingMediaState.pending, PendingMediaKind.image) => l10n.photo,
    (PendingMediaState.pending, PendingMediaKind.video) => l10n.video,
    (PendingMediaState.pending, PendingMediaKind.file) =>
      _hasExtension ? fileName : l10n.attachment,
    (PendingMediaState.failed, PendingMediaKind.image) =>
      l10n.photoDidNotArrive,
    (PendingMediaState.failed, PendingMediaKind.video) =>
      l10n.videoDidNotArrive,
    (PendingMediaState.failed, PendingMediaKind.file) =>
      l10n.attachmentDidNotArrive,
  };

  bool get _hasExtension {
    final dot = fileName.lastIndexOf('.');
    return dot > 0 && dot < fileName.length - 1;
  }

  static PendingMediaKind _kindOf(String fileName, String? mimeType) {
    final type = lookupMimeType(fileName) ?? mimeType ?? '';
    if (type.startsWith('image/')) return PendingMediaKind.image;
    if (type.startsWith('video/')) return PendingMediaKind.video;
    return PendingMediaKind.file;
  }
}

/// The parts of a Google Messages `MediaContent` the pending tile uses,
/// read from the bridge's `fi.mau.gmessages.raw_debug_data`.
///
/// The payload is an envelope whose field 3 holds field 2, which is the
/// `Message` (gmessages pkg/libgm/gmproto/conversations.proto). Its
/// repeated field 10 holds each part's `MessageInfo`, whose field 3 is the
/// `MediaContent`: name 4, dimensions 6 ({width 1, height 2}), preview JPEG
/// 7, MIME type 14. Only that path is walked, with no protobuf library.
class GmessagesMediaContent {
  final String? name;
  final String? mimeType;
  final int? width;
  final int? height;
  final Uint8List? previewBytes;

  const GmessagesMediaContent({
    this.name,
    this.mimeType,
    this.width,
    this.height,
    this.previewBytes,
  });

  /// Width over height, when both are given and the shape is one a photo
  /// or video plausibly has.
  double? get aspectRatio {
    final w = width;
    final h = height;
    if (w == null || h == null) return null;
    if (w <= 0 || h <= 0 || w > 100000 || h > 100000) return null;
    final ratio = w / h;
    if (ratio < 0.2 || ratio > 5) return null;
    return ratio;
  }

  /// [previewBytes] when they are a JPEG of a size worth decoding.
  Uint8List? get preview {
    final bytes = previewBytes;
    if (bytes == null ||
        bytes.length < 4 ||
        bytes.length > PendingMedia.maxPreviewBytes) {
      return null;
    }
    // JPEG's start-of-image marker.
    if (bytes[0] != 0xFF || bytes[1] != 0xD8 || bytes[2] != 0xFF) return null;
    return bytes;
  }

  /// The media in [rawDebugData] named [fileName], or the first media in it
  /// when none has that name. Null when there is none or the data does not
  /// parse as expected.
  static GmessagesMediaContent? find(String rawDebugData, String fileName) {
    try {
      final root = base64.decode(rawDebugData);
      final envelope = _ProtoReader.firstBytes(root, 3);
      if (envelope == null) return null;
      final message = _ProtoReader.firstBytes(envelope, 2);
      if (message == null) return null;
      GmessagesMediaContent? first;
      for (final info in _ProtoReader.allBytes(message, 10)) {
        final mediaBytes = _ProtoReader.firstBytes(info, 3);
        if (mediaBytes == null) continue;
        final media = _parse(mediaBytes);
        if (media.name == fileName) return media;
        first ??= media;
      }
      return first;
    } on FormatException {
      return null;
    }
  }

  static GmessagesMediaContent _parse(Uint8List bytes) {
    String? name;
    String? mimeType;
    int? width;
    int? height;
    Uint8List? preview;
    for (final field in _ProtoReader.fields(bytes)) {
      switch ((field.number, field.value)) {
        case (4, final Uint8List value):
          name = utf8.decode(value, allowMalformed: true);
        case (6, final Uint8List value):
          for (final dimension in _ProtoReader.fields(value)) {
            switch ((dimension.number, dimension.value)) {
              case (1, final int value):
                width = value;
              case (2, final int value):
                height = value;
            }
          }
        case (7, final Uint8List value):
          preview = value;
        case (14, final Uint8List value):
          mimeType = utf8.decode(value, allowMalformed: true);
      }
    }
    return GmessagesMediaContent(
      name: name,
      mimeType: mimeType,
      width: width,
      height: height,
      previewBytes: preview,
    );
  }
}

/// One field of a protobuf message: an int for a varint or fixed-width
/// value, the bytes for a length-delimited one.
typedef _ProtoField = ({int number, Object value});

/// Reads the fields of a protobuf message, throwing [FormatException] on
/// anything malformed.
abstract class _ProtoReader {
  static Iterable<_ProtoField> fields(Uint8List bytes) sync* {
    var offset = 0;
    int varint() {
      var result = 0;
      var shift = 0;
      while (true) {
        if (offset >= bytes.length || shift > 63) {
          throw const FormatException('Truncated varint');
        }
        final byte = bytes[offset++];
        result |= (byte & 0x7F) << shift;
        if (byte & 0x80 == 0) return result;
        shift += 7;
      }
    }

    while (offset < bytes.length) {
      final tag = varint();
      final number = tag >> 3;
      switch (tag & 7) {
        case 0:
          yield (number: number, value: varint());
        case 1:
          if (offset + 8 > bytes.length) {
            throw const FormatException('Truncated fixed64');
          }
          offset += 8;
        case 2:
          final length = varint();
          if (length < 0 || offset + length > bytes.length) {
            throw const FormatException('Truncated field');
          }
          yield (
            number: number,
            value: Uint8List.sublistView(bytes, offset, offset + length),
          );
          offset += length;
        case 5:
          if (offset + 4 > bytes.length) {
            throw const FormatException('Truncated fixed32');
          }
          offset += 4;
        default:
          throw const FormatException('Unknown wire type');
      }
    }
  }

  static Uint8List? firstBytes(Uint8List bytes, int number) =>
      allBytes(bytes, number).firstOrNull;

  static Iterable<Uint8List> allBytes(Uint8List bytes, int number) => fields(
    bytes,
  ).where((f) => f.number == number).map((f) => f.value).whereType<Uint8List>();
}
