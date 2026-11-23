// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:async/async.dart' show Result;
import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/utils/other_party_can_receive.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/resize_video.dart';
import 'package:fluffychat/utils/start_push_foreground_service.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:mime/mime.dart';

/// Files smaller than this are sent as they are: compressing them saves
/// almost nothing and costs a transcode.
const int _minSizeToCompress = 20 * 1000;

/// Upload limit assumed when the homeserver does not report `m.upload.size`.
const int _fallbackMaxUploadSize = 100 * 1000 * 1000;

/// Sends [files] to [room] as one file event each, in the given order.
///
/// This is the upload path shared by the composer and the gallery picker, and
/// it produces the same events as `SendFileDialog`: the mime type comes from
/// the picker or the file path, images are shrunk to 1600 px on their longest
/// side when [compress] is true (animated images keep all frames because the
/// client's image resizer skips them), videos on mobile get a thumbnail and are
/// transcoded when [compress] is true, and anything over the homeserver's
/// upload limit is refused before it is uploaded.
///
/// A failure in one file is logged and handed to [onError], and the remaining
/// files are still sent, so this never throws for a single bad file. If the
/// room is encrypted and no other member has a device to decrypt with, nothing
/// is sent and [onError] receives [OtherPartyCanNotReceiveMessages].
///
/// Progress snackbars ("compressing video", "sending files, do not exit") are
/// shown only when both [scaffoldMessenger] and [l10n] are given, because this
/// function has no [BuildContext] of its own. On platforms with a foreground
/// service (mobile, and the web's leave-page guard) that service keeps the
/// upload alive instead of the "do not exit" snackbar, as in the dialog.
Future<void> sendAttachments({
  required Room room,
  required List<XFile> files,
  bool compress = true,
  String? threadRootEventId,
  String? threadLastEventId,
  ScaffoldMessengerState? scaffoldMessenger,
  L10n? l10n,
  void Function(Object error, StackTrace stackTrace)? onError,
}) async {
  if (files.isEmpty) return;

  void report(String message, Object error, StackTrace stackTrace) {
    Logs().w(message, error, stackTrace);
    onError?.call(error, stackTrace);
  }

  if (!room.otherPartyCanReceiveMessages) {
    report(
      'Not sending attachments: no other device can decrypt them',
      OtherPartyCanNotReceiveMessages(),
      StackTrace.current,
    );
    return;
  }

  final snackbars = scaffoldMessenger != null && l10n != null
      ? (messenger: scaffoldMessenger, l10n: l10n)
      : null;
  void showSendingSnackBar() {
    if (snackbars == null || ForegroundServices.platformSupported) return;
    snackbars.messenger.showLoadingSnackBar(
      snackbars.l10n.sendingFilesDoNotExit(files.length),
    );
  }

  if (ForegroundServices.platformSupported) {
    await ForegroundServices.startService('send_files');
  } else {
    showSendingSnackBar();
  }

  try {
    final clientConfig = await Result.capture(room.client.getConfig());
    final maxUploadSize =
        clientConfig.asValue?.value.mUploadSize ?? _fallbackMaxUploadSize;

    for (final xfile in files) {
      try {
        await _sendOne(
          room: room,
          xfile: xfile,
          compress: compress,
          maxUploadSize: maxUploadSize,
          threadRootEventId: threadRootEventId,
          threadLastEventId: threadLastEventId,
          onCompressStart: () {
            if (snackbars == null) return;
            snackbars.messenger.clearSnackBars();
            snackbars.messenger.showLoadingSnackBar(
              snackbars.l10n.compressingVideo,
            );
          },
          onCompressEnd: () {
            snackbars?.messenger.clearSnackBars();
            showSendingSnackBar();
          },
        );
      } catch (e, s) {
        report('Unable to send attachment ${xfile.name}', e, s);
      }
    }
  } finally {
    if (ForegroundServices.platformSupported) {
      await ForegroundServices.stopService('send_files');
    } else {
      snackbars?.messenger.clearSnackBars();
    }
  }
}

/// Builds the [MatrixFile] for one picked file and sends it, retrying once
/// after the server's requested delay when rate limited.
Future<void> _sendOne({
  required Room room,
  required XFile xfile,
  required bool compress,
  required int maxUploadSize,
  required String? threadRootEventId,
  required String? threadLastEventId,
  required void Function() onCompressStart,
  required void Function() onCompressEnd,
}) async {
  final mimeType = xfile.mimeType ?? lookupMimeType(xfile.path);
  final isMobileVideo =
      PlatformInfos.isMobile &&
      mimeType != null &&
      mimeType.startsWith('video');

  final MatrixFile file;
  MatrixImageFile? thumbnail;
  if (isMobileVideo) {
    thumbnail = await xfile.getVideoThumbnail();
    final length = (await Result.capture(xfile.length())).asValue?.value;
    onCompressStart();
    try {
      file = await xfile.getVideoInfo(
        compress: compress && length != null && length > _minSizeToCompress,
      );
    } finally {
      onCompressEnd();
    }
  } else {
    file = MatrixFile(
      bytes: await xfile.readAsBytes(),
      name: xfile.name,
      mimeType: mimeType,
    ).detectFileType;
  }

  if (file.bytes.length > maxUploadSize) {
    throw FileTooBigMatrixException(file.bytes.length, maxUploadSize);
  }

  Future<void> send() => room.sendFileEvent(
    file,
    thumbnail: thumbnail,
    shrinkImageMaxDimension: compress ? 1600 : null,
    threadRootEventId: threadRootEventId,
    threadLastEventId: threadLastEventId,
  );

  try {
    await send();
  } on MatrixException catch (e) {
    final retryAfterMs = e.retryAfterMs;
    if (e.error != MatrixError.M_LIMIT_EXCEEDED || retryAfterMs == null) {
      rethrow;
    }
    await Future.delayed(Duration(milliseconds: retryAfterMs + 1000));
    await send();
  }
}

extension on ScaffoldMessengerState {
  /// A persistent snackbar with a small spinner, matching the one
  /// `SendFileDialog` shows while files upload.
  void showLoadingSnackBar(String title) => showSnackBar(
    SnackBar(
      showCloseIcon: false,
      persist: true,
      content: Row(
        spacing: 8,
        children: [
          Expanded(child: Text(title, overflow: .ellipsis, maxLines: 1)),
          SizedBox.square(
            dimension: 16,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: Theme.of(context).colorScheme.onInverseSurface,
            ),
          ),
        ],
      ),
    ),
  );
}
