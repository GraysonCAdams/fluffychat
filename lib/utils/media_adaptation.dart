// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/utils/room_features.dart';
import 'package:matrix/matrix.dart';

/// What to do with an attachment's format before sending it into a room.
enum MediaFormatAction {
  /// Send it as it is.
  keep,

  /// Re-encode the image as PNG and send it as `m.image`.
  convertToPng,

  /// Transcode the video to MP4 and send it as `m.video`.
  convertToMp4,

  /// Send the original bytes as `m.file`.
  sendAsFile,

  /// Do not send it: the room's bridge would refuse it.
  refuse,
}

/// The format decision for one attachment, with what to do instead when a
/// conversion fails. [fallback] is [MediaFormatAction.keep],
/// [MediaFormatAction.sendAsFile] or [MediaFormatAction.refuse].
class MediaFormatPlan {
  final MediaFormatAction action;
  final MediaFormatAction fallback;

  const MediaFormatPlan(this.action, {MediaFormatAction? fallback})
    : fallback = fallback ?? action;

  @override
  bool operator ==(Object other) =>
      other is MediaFormatPlan &&
      other.action == action &&
      other.fallback == fallback;

  @override
  int get hashCode => Object.hash(action, fallback);

  @override
  String toString() => 'MediaFormatPlan($action, fallback: $fallback)';
}

/// Decides how a [mimeType] attachment that would go out as [msgType] gets
/// past the room's [features].
///
/// An accepted type is kept. Otherwise an image is converted to PNG, and a
/// video to MP4 when [canConvertVideo], provided the room accepts the
/// result. Next comes sending the original as `m.file`, when
/// [allowFileFallback] and the room accepts the mime type as a file. When
/// none of that works, an attachment the bridge would still pass (a type
/// at the "dropped" level) is kept, and anything else is refused.
MediaFormatPlan planMediaFormat(
  RoomFeatures features, {
  required String msgType,
  required String mimeType,
  bool canConvertVideo = false,
  bool allowFileFallback = true,
}) {
  if (features.acceptsMime(msgType, mimeType)) {
    return const MediaFormatPlan(MediaFormatAction.keep);
  }
  final asFile =
      allowFileFallback &&
      msgType != CapabilityMsgType.file &&
      features.acceptsMime(CapabilityMsgType.file, mimeType);
  final lastResort = asFile
      ? MediaFormatAction.sendAsFile
      : features.rejectsMime(msgType, mimeType)
      ? MediaFormatAction.refuse
      : MediaFormatAction.keep;

  if (msgType == CapabilityMsgType.image &&
      features.acceptsMime(msgType, 'image/png')) {
    return MediaFormatPlan(
      MediaFormatAction.convertToPng,
      fallback: lastResort,
    );
  }
  if (msgType == CapabilityMsgType.video &&
      canConvertVideo &&
      features.acceptsMime(msgType, 'video/mp4')) {
    return MediaFormatPlan(
      MediaFormatAction.convertToMp4,
      fallback: lastResort,
    );
  }
  return MediaFormatPlan(lastResort);
}

/// Whether a caption on a [msgType] event has to go as its own message.
bool captionNeedsOwnMessage(
  RoomFeatures features, {
  required String msgType,
  required bool hasCaption,
}) => hasCaption && !features.acceptsCaption(msgType);

/// The room's size limit for [msgType] when [size] bytes exceed it, else
/// null.
int? exceededSizeLimit(
  RoomFeatures features, {
  required String msgType,
  required int size,
}) {
  final max = features.maxSize(msgType);
  return max != null && size > max ? max : null;
}

/// Thrown when the room's bridge would refuse an attachment's type and no
/// conversion or fallback applies.
class MediaTypeNotAcceptedException implements Exception {
  final String mimeType;
  final String msgType;

  /// Mime types the room takes for [msgType], possibly empty.
  final List<String> acceptedMimeTypes;

  const MediaTypeNotAcceptedException({
    required this.mimeType,
    required this.msgType,
    required this.acceptedMimeTypes,
  });

  @override
  String toString() =>
      'MediaTypeNotAcceptedException($mimeType in $msgType, '
      'accepted: $acceptedMimeTypes)';
}

/// Thrown when an attachment is larger than the room's bridge accepts.
class FileTooBigForChatException implements Exception {
  final int size;
  final int maxSize;

  const FileTooBigForChatException(this.size, this.maxSize);

  @override
  String toString() => 'FileTooBigForChatException($size > $maxSize)';
}

/// An attachment made fit for a room, ready for `Room.sendFileEvent`.
class AdaptedMedia {
  final MatrixFile file;
  final MatrixImageFile? thumbnail;

  /// Merged into the event content: sets `msgtype` to `m.file` when the
  /// attachment goes as a file, else null.
  final Map<String, Object?>? extraContent;

  /// Whether a caption must be left off the media event and sent as a text
  /// message after it.
  final bool captionSeparately;

  const AdaptedMedia({
    required this.file,
    this.thumbnail,
    this.extraContent,
    this.captionSeparately = false,
  });

  bool get sentAsFile => extraContent?['msgtype'] == MessageTypes.File;

  /// [extraContent] merged over [content], for call sites that add their
  /// own keys (a caption body, voice metadata).
  Map<String, Object?>? mergeExtraContent(Map<String, Object?>? content) {
    if (content == null) return extraContent;
    if (extraContent == null) return content;
    return {...content, ...?extraContent};
  }
}

/// Re-encodes [bytes] as PNG with Flutter's own codecs (BMP, GIF, JPEG,
/// WebP and whatever the platform decodes), taking the first frame.
/// Returns null when the image cannot be decoded.
Future<Uint8List?> encodeImageAsPng(Uint8List bytes) async {
  try {
    final codec = await ui.instantiateImageCodec(bytes);
    try {
      final frame = await codec.getNextFrame();
      try {
        final data = await frame.image.toByteData(
          format: ui.ImageByteFormat.png,
        );
        return data?.buffer.asUint8List();
      } finally {
        frame.image.dispose();
      }
    } finally {
      codec.dispose();
    }
  } catch (e, s) {
    Logs().w('Unable to re-encode image as PNG', e, s);
    return null;
  }
}

String _withExtension(String name, String extension) {
  final dot = name.lastIndexOf('.');
  final base = dot > 0 ? name.substring(0, dot) : name;
  return '$base.$extension';
}

/// Fits [file] to the room's [features] following [planMediaFormat], then
/// checks the room's size limit and caption support for what will be sent.
///
/// [msgType] overrides the capability key, for voice messages
/// ([CapabilityMsgType.voice]); it defaults to the file's `msgtype`.
/// [convertVideo] transcodes the original to MP4 and is null where the
/// platform cannot. [convertImage] is the PNG encoder, replaceable in tests.
///
/// A room without restrictions gets [file] and [thumbnail] back untouched.
/// Throws [MediaTypeNotAcceptedException] or [FileTooBigForChatException]
/// when the attachment must not be sent.
Future<AdaptedMedia> adaptMediaForRoom({
  required RoomFeatures features,
  required MatrixFile file,
  MatrixImageFile? thumbnail,
  String? msgType,
  bool hasCaption = false,
  bool allowFileFallback = true,
  Future<MatrixFile?> Function()? convertVideo,
  Future<Uint8List?> Function(Uint8List bytes) convertImage = encodeImageAsPng,
}) async {
  if (features.isUnrestricted) {
    return AdaptedMedia(file: file, thumbnail: thumbnail);
  }
  final originalMsgType = msgType ?? file.msgType;
  final mimeType = file.mimeType;
  final plan = planMediaFormat(
    features,
    msgType: originalMsgType,
    mimeType: mimeType,
    canConvertVideo: convertVideo != null,
    allowFileFallback: allowFileFallback,
  );

  MatrixFile? converted;
  var action = plan.action;
  switch (action) {
    case MediaFormatAction.convertToPng:
      Uint8List? png;
      try {
        png = await convertImage(file.bytes);
      } catch (e, s) {
        Logs().w('Image conversion failed', e, s);
      }
      if (png != null) {
        converted = MatrixImageFile(
          bytes: png,
          name: _withExtension(file.name, 'png'),
          mimeType: 'image/png',
        );
      }
    case MediaFormatAction.convertToMp4:
      MatrixFile? video;
      try {
        video = await convertVideo!();
      } catch (e, s) {
        Logs().w('Video conversion failed', e, s);
      }
      if (video != null &&
          features.acceptsMime(CapabilityMsgType.video, video.mimeType)) {
        final info = video is MatrixVideoFile ? video : null;
        converted = MatrixVideoFile(
          bytes: video.bytes,
          name: _withExtension(file.name, 'mp4'),
          mimeType: video.mimeType,
          width: info?.width,
          height: info?.height,
          duration: info?.duration,
        );
      }
    case MediaFormatAction.keep:
    case MediaFormatAction.sendAsFile:
    case MediaFormatAction.refuse:
      break;
  }
  if ((action == MediaFormatAction.convertToPng ||
          action == MediaFormatAction.convertToMp4) &&
      converted == null) {
    action = plan.fallback;
  }

  final MatrixFile result;
  var resultThumbnail = thumbnail;
  var resultMsgType = originalMsgType;
  Map<String, Object?>? extraContent;
  switch (action) {
    case MediaFormatAction.convertToPng:
    case MediaFormatAction.convertToMp4:
      result = converted!;
    case MediaFormatAction.keep:
      result = file;
    case MediaFormatAction.sendAsFile:
      result = MatrixFile(
        bytes: file.bytes,
        name: file.name,
        mimeType: mimeType,
      );
      resultThumbnail = null;
      resultMsgType = CapabilityMsgType.file;
      extraContent = {'msgtype': MessageTypes.File};
    case MediaFormatAction.refuse:
      throw MediaTypeNotAcceptedException(
        mimeType: mimeType,
        msgType: originalMsgType,
        acceptedMimeTypes:
            features.featuresFor(originalMsgType)?.usableMimeTypes ?? const [],
      );
  }

  final limit = exceededSizeLimit(
    features,
    msgType: resultMsgType,
    size: result.bytes.length,
  );
  if (limit != null) {
    throw FileTooBigForChatException(result.bytes.length, limit);
  }

  return AdaptedMedia(
    file: result,
    thumbnail: resultThumbnail,
    extraContent: extraContent,
    captionSeparately: captionNeedsOwnMessage(
      features,
      msgType: resultMsgType,
      hasCaption: hasCaption,
    ),
  );
}
