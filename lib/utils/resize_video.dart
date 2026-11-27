// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/utils/encoded_image_size.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';
import 'package:matrix/matrix.dart';
import 'package:mime/mime.dart';

/// Whether [ResizeImage.getVideoInfo] can transcode on this platform. Its
/// output is always MP4.
bool get canTranscodeVideo => PlatformInfos.isMobile || PlatformInfos.isMacOS;

/// The width and height a video shows at, from its encoded frame size and
/// its rotation in degrees. Phones store a portrait clip as landscape frames
/// turned a quarter, so the event's `w` and `h` are swapped for it.
({int? width, int? height}) displayedVideoSize(
  int? width,
  int? height,
  int? rotation,
) => (rotation ?? 0) % 180 == 0
    ? (width: width, height: height)
    : (width: height, height: width);

/// A video's thumbnail image, carrying its pixel size so the event's
/// `thumbnail_info` gives the shape the video is shown in.
Future<MatrixImageFile> videoThumbnailFile(Uint8List bytes, String name) async {
  final size = await encodedImageSize(bytes);
  return MatrixImageFile(
    bytes: bytes,
    name: name,
    width: size?.width,
    height: size?.height,
  );
}

extension ResizeImage on XFile {
  Future<MatrixVideoFile> getVideoInfo({bool compress = true}) async {
    MediaInfo? mediaInfo;
    String? destinationPath;
    try {
      if (canTranscodeVideo) {
        if (compress) {
          final result = await LightCompressor().compressVideo(
            path: path,
            videoQuality: VideoQuality.medium,
            android: AndroidConfig(isSharedStorage: false),
            ios: IOSConfig(saveInGallery: false),
            video: Video(videoName: name, targetSizeMb: 5),
          );
          if (result is OnFailure) {
            Logs().e('Failed to compress video!', result);
          }
          if (result is OnSuccess) {
            destinationPath = result.destinationPath;
          }
        }
        mediaInfo = await LightCompressor().getMediaInfo(
          destinationPath ?? path,
        );
      }
    } catch (e, s) {
      Logs().w('Error while fetching video media info', e, s);
    }

    final shown = displayedVideoSize(
      mediaInfo?.width,
      mediaInfo?.height,
      mediaInfo?.rotation,
    );
    return MatrixVideoFile(
      bytes: destinationPath != null
          ? await XFile(destinationPath).readAsBytes()
          : await readAsBytes(),
      name: name,
      mimeType: destinationPath != null
          ? lookupMimeType(destinationPath)
          : mimeType,
      width: shown.width,
      height: shown.height,
      duration: mediaInfo?.duration?.inMilliseconds,
    );
  }

  Future<MatrixImageFile?> getVideoThumbnail() async {
    if (!PlatformInfos.isMobile) return null;

    try {
      final thumbnailPath = await LightCompressor().getVideoThumbnail(path);
      final bytes = await XFile(thumbnailPath).readAsBytes();
      return await videoThumbnailFile(bytes, name);
    } catch (e, s) {
      Logs().w('Error while compressing video', e, s);
    }
    return null;
  }
}
