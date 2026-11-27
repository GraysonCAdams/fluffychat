// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:matrix/matrix.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// The most bytes of a picture that goes into a notification.
const notificationMediaMaxBytes = 1024 * 1024;

/// The longest side, in pixels, of a picture asked of the homeserver for a
/// notification.
const notificationMediaMaxDimension = 1024;

/// How long a stored picture stays in the cache directory. Notifications
/// older than this show their text only.
const notificationMediaMaxAge = Duration(days: 7);

/// A picture the notification shows, as the `Message` of a
/// `MessagingStyle` takes it.
class NotificationMedia {
  const NotificationMedia({required this.mimeType, required this.uri});

  final String mimeType;

  /// A `content://` URI served by the app's notification media provider.
  final String uri;
}

/// Gets the picture of an event for a notification, or null for none.
typedef NotificationMediaDownloader = Future<MatrixFile?> Function(Event event);

/// Where the stored pictures go.
typedef NotificationMediaDirectory = Future<Directory> Function();

/// The authority of the provider that serves the stored pictures; the
/// `provider` entry in `AndroidManifest.xml` declares it.
typedef NotificationMediaAuthority = Future<String> Function();

/// The content of [event] as it reads after its edit: for an edit
/// (`m.replace`) the event its `m.new_content` makes, otherwise [event].
///
/// A bridge that has to wait for an attachment sends a notice first and the
/// attachment as an edit of it, so the edit is where the picture is.
Event effectiveEvent(Event event) {
  if (event.relationshipType != RelationshipTypes.edit) return event;
  final newContent = event.content.tryGetMap<String, Object?>('m.new_content');
  if (newContent == null) return event;
  return Event(
    content: newContent,
    type: event.type,
    eventId: event.eventId,
    senderId: event.senderId,
    originServerTs: event.originServerTs,
    room: event.room,
    stateKey: event.stateKey,
  );
}

/// Whether [event] is a picture or a video, once any edit is applied.
bool hasNotificationMedia(Event event) {
  final effective = effectiveEvent(event);
  return effective.type == EventTypes.Sticker ||
      effective.type == EventTypes.Message &&
          const {
            MessageTypes.Image,
            MessageTypes.Sticker,
            MessageTypes.Video,
          }.contains(effective.messageType);
}

/// Picks the smallest source of a still picture for [event] and downloads
/// it, decrypting it in an encrypted room: the thumbnail (a video's poster,
/// a GIF's first frame) when there is one, else the image itself when it is
/// small. Null when there is nothing small enough, such as a video without
/// a poster or a large encrypted image without a thumbnail.
Future<MatrixFile?> downloadNotificationMedia(Event event) async {
  final info = event.infoMap;
  final thumbnailSize = event.thumbnailInfoMap.tryGet<int>('size');
  final size = info.tryGet<int>('size');
  final isVideo = event.messageType == MessageTypes.Video;

  bool fits(int? bytes) => bytes == null || bytes <= notificationMediaMaxBytes;

  final MatrixFile file;
  if (event.hasThumbnail && fits(thumbnailSize)) {
    file = await event.downloadAndDecryptAttachment(getThumbnail: true);
  } else if (!isVideo && event.hasAttachment && size != null && fits(size)) {
    file = await event.downloadAndDecryptAttachment();
  } else if (!isVideo &&
      !event.isAttachmentEncrypted &&
      event.attachmentMxcUrl != null) {
    // The homeserver scales a large or animated picture down to one frame.
    final client = event.room.client;
    final uri = await event.attachmentMxcUrl!.getThumbnailUri(
      client,
      width: notificationMediaMaxDimension,
      height: notificationMediaMaxDimension,
      method: ThumbnailMethod.scale,
      animated: false,
    );
    final response = await client.httpClient.get(
      uri,
      headers: client.accessToken == null
          ? null
          : {'authorization': 'Bearer ${client.accessToken}'},
    );
    if (response.statusCode != 200) return null;
    file = MatrixFile(
      bytes: response.bodyBytes,
      name: 'notification',
      mimeType: response.headers['content-type'] ?? '',
    );
  } else {
    return null;
  }
  return file.bytes.length <= notificationMediaMaxBytes ? file : null;
}

String? _extensionOf(String mimeType) => switch (mimeType) {
  'image/jpeg' || 'image/jpg' => 'jpg',
  'image/png' => 'png',
  'image/webp' => 'webp',
  'image/gif' => 'gif',
  _ => null,
};

/// Writes [file] under [directory] and returns it as a notification
/// picture, or null when it is not a picture the system can decode.
///
/// The file is named after [eventId] so a second push for the same event
/// reuses it. Files older than [notificationMediaMaxAge] go.
Future<NotificationMedia?> storeNotificationMedia(
  MatrixFile file, {
  required String eventId,
  required Directory directory,
  required String authority,
}) async {
  final mimeType = file.mimeType.split(';').first.trim().toLowerCase();
  final extension = _extensionOf(mimeType);
  if (extension == null || file.bytes.isEmpty) return null;

  await directory.create(recursive: true);
  final name = '${sha256.convert(eventId.codeUnits)}.$extension';
  await File(path.join(directory.path, name)).writeAsBytes(file.bytes);
  await _removeOldMedia(directory);

  return NotificationMedia(
    mimeType: mimeType == 'image/jpg' ? 'image/jpeg' : mimeType,
    uri: 'content://$authority/$notificationMediaPathName/$name',
  );
}

/// The `name` of the `cache-path` in `res/xml/notification_media_paths.xml`,
/// and so the first segment of every picture's URI.
const notificationMediaPathName = 'notification_media';

Future<void> _removeOldMedia(Directory directory) async {
  final cutoff = DateTime.now().subtract(notificationMediaMaxAge);
  await for (final entity in directory.list()) {
    if (entity is File && (await entity.lastModified()).isBefore(cutoff)) {
      await entity.delete();
    }
  }
}

Future<Directory> _defaultDirectory() async => Directory(
  path.join((await getTemporaryDirectory()).path, notificationMediaPathName),
);

Future<String> _defaultAuthority() async =>
    '${(await PackageInfo.fromPlatform()).packageName}.$notificationMediaPathName';

/// The picture [event] shows in its notification, or null when there is none
/// to show: the event is not a picture or video, it was sent with Invisible
/// Ink, or the picture cannot be had. A failure here never stops the
/// notification, which then carries the text alone.
Future<NotificationMedia?> notificationMediaOf(
  Event event, {
  NotificationMediaDownloader downloader = downloadNotificationMedia,
  NotificationMediaDirectory directory = _defaultDirectory,
  NotificationMediaAuthority authority = _defaultAuthority,
  Duration timeout = const Duration(seconds: 5),
}) async {
  final effective = effectiveEvent(event);
  if (!hasNotificationMedia(event)) return null;
  // Invisible Ink hides what a message says; its picture stays hidden too.
  if (effectOf(event) == MessageEffect.invisibleInk ||
      effectOf(effective) == MessageEffect.invisibleInk) {
    return null;
  }
  try {
    final file = await downloader(effective).timeout(timeout);
    if (file == null) return null;
    return await storeNotificationMedia(
      file,
      eventId: event.eventId,
      directory: await directory(),
      authority: await authority(),
    );
  } catch (e, s) {
    Logs().w('Unable to get the picture for a notification', e, s);
    return null;
  }
}

/// The `Message` a notification shows for [event]: [body] from [person],
/// with [media] under it when given.
Message notificationMessage(
  Event event, {
  required String body,
  required Person person,
  NotificationMedia? media,
}) => Message(
  body,
  event.originServerTs,
  person,
  dataMimeType: media?.mimeType,
  dataUri: media?.uri,
);

/// The time of the event [event] edits, or null when it is not an edit or
/// the original cannot be had.
Future<DateTime?> editedEventTime(Event event) async {
  if (event.relationshipType != RelationshipTypes.edit) return null;
  final originalId = event.relationshipEventId;
  if (originalId == null) return null;
  try {
    return (await event.room.getEventById(originalId))?.originServerTs;
  } catch (e, s) {
    Logs().w('Unable to load the event an edit replaces', e, s);
    return null;
  }
}

/// [messages] with [message] added. When [replacedTime] is given and a
/// message of the same sender sits at that time, [message] takes its place,
/// so an edit that turns a placeholder into the picture leaves one line.
List<Message> withNotificationMessage(
  List<Message>? messages,
  Message message, {
  DateTime? replacedTime,
}) {
  final result = [...?messages];
  if (replacedTime != null) {
    final index = result.indexWhere(
      (m) =>
          m.timestamp.millisecondsSinceEpoch ==
              replacedTime.millisecondsSinceEpoch &&
          m.person?.key == message.person?.key,
    );
    if (index != -1) {
      result[index] = message;
      return result;
    }
  }
  return result..add(message);
}
