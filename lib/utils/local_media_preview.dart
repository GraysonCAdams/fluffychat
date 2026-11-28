// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/encoded_image_size.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:matrix/matrix.dart';

/// Fills in the pixel size of [file] when it is an image that lacks one.
///
/// `Room.sendFileEvent` shows the message from the file's own `info` while
/// it uploads, and a photo picked from the gallery has no size yet, so its
/// bubble would take a square shape until the server's copy of the event
/// arrives. Only the image header is read, so this is quick even for a
/// large photo.
Future<void> fillImageSize(MatrixFile file) async {
  if (file is! MatrixImageFile || (file.width != null && file.height != null)) {
    return;
  }
  final size = await encodedImageSize(file.bytes);
  if (size == null) return;
  file.setImageSizeIfNull(width: size.width, height: size.height);
}

/// Primes the timeline's image cache with what a file about to be sent
/// under [txid] looks like: an image's own bytes, or a video's poster frame
/// from [thumbnail]. Its bubble then draws the local picture at full
/// sharpness from the first frame and keeps it once the server's event,
/// which carries the same transaction ID, replaces the local one.
void primeLocalMediaPreview({
  required Room room,
  required String txid,
  required MatrixFile file,
  MatrixImageFile? thumbnail,
}) {
  final bytes = switch (file) {
    MatrixImageFile() => file.bytes,
    MatrixVideoFile() => thumbnail?.bytes,
    _ => null,
  };
  if (bytes == null || bytes.isEmpty) return;
  MxcImage.prime(cacheName: room.id, cacheKey: txid, bytes: bytes);
}
