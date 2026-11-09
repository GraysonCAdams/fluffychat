// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:light_compressor_v2/light_compressor_v2.dart';
import 'package:matrix/matrix.dart';
import 'package:media_kit/media_kit.dart';
import 'package:media_kit_video/media_kit_video.dart';
import 'package:path_provider/path_provider.dart';

/// Makes a still image for video messages that arrive without a thumbnail,
/// which bridges commonly send. The video is downloaded and its first frame
/// kept as a JPEG, cached on disk by event so this happens once per video.
abstract class VideoPoster {
  /// Larger videos are left with their placeholder rather than downloaded
  /// just to show a preview.
  static const maxVideoSize = 25 * 1024 * 1024;

  static final Map<String, Future<Uint8List?>> _pending = {};

  static bool get isSupported =>
      PlatformInfos.isMobile || PlatformInfos.isWindows;

  /// The poster for [event], or null when none can be made.
  static Future<Uint8List?> forEvent(Event event) =>
      _pending[event.eventId] ??= _load(event);

  static Future<Uint8List?> _load(Event event) async {
    if (!isSupported) return null;
    final size = event.infoMap.tryGet<int>('size');
    if (size != null && size > maxVideoSize) return null;
    try {
      final directory = Directory(
        '${(await getTemporaryDirectory()).path}'
        '${Platform.pathSeparator}video_posters',
      );
      final key = sha256.convert(utf8.encode(event.eventId)).toString();
      final poster = File('${directory.path}${Platform.pathSeparator}$key.jpg');
      if (await poster.exists()) return await poster.readAsBytes();

      final video = await event.downloadAndDecryptAttachment();
      if (video.bytes.length > maxVideoSize) return null;
      await directory.create(recursive: true);
      final videoFile = File(
        '${directory.path}${Platform.pathSeparator}$key.video',
      );
      await videoFile.writeAsBytes(video.bytes);
      try {
        final bytes = PlatformInfos.isMobile
            ? await _mobileFrame(videoFile.path)
            : await _desktopFrame(videoFile.path);
        if (bytes == null || bytes.isEmpty) return null;
        await poster.writeAsBytes(bytes);
        return bytes;
      } finally {
        await videoFile.delete();
      }
    } catch (e, s) {
      Logs().w('Unable to make a poster for video ${event.eventId}', e, s);
      return null;
    }
  }

  static Future<Uint8List?> _mobileFrame(String path) async {
    final thumbnailPath = await LightCompressor().getVideoThumbnail(path);
    return File(thumbnailPath).readAsBytes();
  }

  /// Opens the video muted and paused and grabs the first frame mpv draws.
  static Future<Uint8List?> _desktopFrame(String path) async {
    final player = Player();
    try {
      final controller = VideoController(player);
      await player.setVolume(0);
      await player.open(Media(Uri.file(path).toString()), play: false);
      await controller.waitUntilFirstFrameRendered.timeout(
        const Duration(seconds: 10),
      );
      return await player.screenshot(format: 'image/jpeg');
    } finally {
      await player.dispose();
    }
  }
}
