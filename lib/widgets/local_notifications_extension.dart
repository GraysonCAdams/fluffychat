// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:crypto/crypto.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/group_members_collage.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/conversation.dart';
import 'package:fluffychat/utils/merged_contacts/merged_contact.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/notification_media.dart';
import 'package:fluffychat/utils/notification_snooze.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/utils/windows_toast_identity.dart';
import 'package:fluffychat/utils/windows_toast_images.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
import 'package:fluffychat/widgets/group_avatar.dart';
import 'package:fluffychat/widgets/incoming_call_dialog.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:universal_html/html.dart' as html;

extension LocalNotificationsExtension on MatrixState {
  static final html.AudioElement _audioPlayer = html.AudioElement()
    ..src = 'assets/assets/sounds/notification.mp3'
    ..load();

  Future<void> showLocalNotification(Event event) async {
    if (event.type == RtcNotificationContent.eventType &&
        event.tryParseRtcNotificationContent()?.notificationType == .ring) {
      final context =
          FluffyChatApp.router.routerDelegate.navigatorKey.currentContext ??
          this.context;
      showDialog<bool>(
        context: context,
        builder: (_) => IncomingCallDialog(event: event),
      ).then((joinCall) {
        if (joinCall != true) return;
        if (!context.mounted) return;
        setActiveClient(event.room.client);
        FluffyChatApp.router.go('/rooms/${event.room.id}?action=call');
      });
    }

    if (notificationsSnoozedUntil != null) return;

    if (kIsWeb &&
        WebFlutterLocalNotificationsPlugin().permissionStatus != .granted) {
      return;
    }

    final l10n = L10n.of(context);
    final roomId = event.room.id;
    if (isChatActive(activeRoomId, event.room.client, roomId)) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
    }

    // A merged contact's rooms share one title and one notification.
    final conversation = notificationConversation(event.room.client, roomId);
    final title =
        notificationConversationName(
          event.room.client,
          roomId,
          MatrixLocals(L10n.of(context)),
        ) ??
        event.room.getLocalizedDisplayname(MatrixLocals(L10n.of(context)));
    // An effect that hides the message keeps it out of the notification.
    var body =
        effectPreviewOf(event, L10n.of(context)) ??
        event.calcLocalizedBody(
          MatrixLocals(L10n.of(context)),
          plaintextBody: true,
          hideReply: true,
          hideEdit: true,
          removeMarkdown: true,
        );
    if (!event.room.isDirectChat) {
      final sender =
          await event.fetchSenderUser() ?? event.senderFromMemoryOrFallback;
      body = l10n.senderMessage(sender.calcDisplayname(), body);
    }
    final avatarUrl = event.room.avatar;

    const size = 128;
    const thumbnailMethod = ThumbnailMethod.crop;

    if (kIsWeb && avatarUrl != null) {
      // Pre-cache so that we can later just set the thumbnail uri as icon:
      try {
        await client.downloadMxcCached(
          avatarUrl,
          width: size,
          height: size,
          thumbnailMethod: thumbnailMethod,
          isThumbnail: true,
          rounded: true,
        );
      } catch (e, s) {
        Logs().d('Unable to pre-download avatar for web notification', e, s);
      }
    }

    final id =
        PlatformInfos.isMacOS || PlatformInfos.isIOS || PlatformInfos.isWeb
        ? '${client.clientName}_${roomId}_${event.eventId}'.hashCode
        : '${client.clientName}_$conversation'.hashCode;

    final unreadRooms = client.rooms.where((r) => r.isUnreadOrInvited).length;

    if (kIsWeb && AppSettings.webNotificationSound.value) _audioPlayer.play();

    final payload = FluffyChatPushPayload(
      client.clientName,
      event.room.id,
      event.eventId,
    ).toString();
    // The picture the chat list shows for the chat: a merged contact's
    // picture is its send-via room's, a group without one shows its members.
    final avatarRoom =
        MergedContact.ofRoom(client, roomId)?.sendViaRoom ?? event.room;
    final windowsCollage =
        PlatformInfos.isWindows && GroupAvatar.shows(avatarRoom)
        ? await _windowsCollageFile(avatarRoom, size)
        : null;
    final windowsAvatarUrl = avatarRoom.avatar;
    final windowsAvatar = !PlatformInfos.isWindows
        ? null
        : windowsCollage ??
              (windowsAvatarUrl != null
                  ? await _windowsAvatarFile(
                      windowsAvatarUrl,
                      size,
                      thumbnailMethod,
                    )
                  : null) ??
              await _windowsFallbackAvatarFile(title, size);
    final isMessage = {
      EventTypes.Message,
      EventTypes.Encrypted,
      EventTypes.Sticker,
    }.contains(event.type);

    // A photo or video shows under the text. Its download starts now; the
    // toast waits a moment for it and otherwise goes out as text, to be
    // posted again with the picture under the same id once it arrives.
    final windowsMediaFuture = PlatformInfos.isWindows
        ? notificationMediaFileOf(
            event,
            directory: _windowsMediaDirectory,
            timeout: _windowsMediaTimeout,
          )
        : null;
    final windowsMedia = await windowsMediaFuture?.timeout(
      _windowsMediaWait,
      onTimeout: () => null,
    );

    Future<void> post(Uri? toastMedia) async => await FlutterLocalNotificationsPlugin().show(
      id: id,
      title: title,
      body: body,
      notificationDetails: NotificationDetails(
        linux: LinuxNotificationDetails(
          sound: ThemeLinuxSound('message-new-instant'),
          actions: switch (event.type) {
            EventTypes.Message ||
            EventTypes.Encrypted ||
            EventTypes.Sticker => [
              LinuxNotificationAction(
                key: FluffyChatNotificationActions.markAsRead.name,
                label: l10n.markAsRead,
              ),
              LinuxNotificationAction(
                key: FluffyChatNotificationActions.mute.name,
                label: l10n.mute,
              ),
            ],
            RtcNotificationContent.eventType => [
              LinuxNotificationAction(
                key: FluffyChatNotificationActions.enterCall.name,
                label: l10n.enterCall,
              ),
            ],
            _ => [],
          },
        ),
        windows: WindowsNotificationDetails(
          timestamp: event.originServerTs,
          images: [
            if (PlatformInfos.isWindows)
              ...windowsToastImages(
                avatar: windowsAvatar ?? _windowsAppLogo,
                title: title,
                // The collage is round faces on a clear square already.
                roundAvatar: windowsAvatar != null && windowsCollage == null,
                media: toastMedia,
                mediaAltText: body,
              ),
          ],
          inputs: [
            if (isMessage)
              WindowsTextInput(
                id: windowsReplyInputId,
                placeHolderContent: l10n.writeAMessage,
              ),
          ],
          actions: [
            if (isMessage) ...[
              WindowsAction(
                content: l10n.reply,
                arguments: windowsNotificationActionArguments(
                  FluffyChatNotificationActions.reply,
                  payload,
                ),
                inputId: windowsReplyInputId,
              ),
              WindowsAction(
                content: l10n.markAsRead,
                arguments: windowsNotificationActionArguments(
                  FluffyChatNotificationActions.markAsRead,
                  payload,
                ),
              ),
            ],
          ],
        ),
        macOS: DarwinNotificationDetails(
          badgeNumber: unreadRooms,
          threadIdentifier: '${client.clientName}_$conversation',
        ),
        web: WebNotificationDetails(
          renotify: true,
          iconUrl: kIsWeb
              ? await avatarUrl?.getThumbnailUri(
                  client,
                  width: size,
                  height: size,
                  method: thumbnailMethod,
                )
              : null,
          timestamp: event.originServerTs,
        ),
      ),
      payload: payload,
    );

    await post(windowsMedia);
    if (windowsMedia == null && windowsMediaFuture != null) {
      // Too slow for the toast: it is posted again with the picture.
      final arrived = await windowsMediaFuture;
      if (arrived != null) await post(arrived);
    }
  }

  /// How long a toast waits for its picture before going out as text.
  static const _windowsMediaWait = Duration(seconds: 2);

  /// How long the picture of a toast may take at most.
  static const _windowsMediaTimeout = Duration(seconds: 15);

  /// Where the pictures of toasts are kept, next to the icon of the toast
  /// identity.
  static Future<Directory> _windowsMediaDirectory() async => Directory(
    '${Platform.environment['LOCALAPPDATA'] ?? (await getTemporaryDirectory()).path}'
    '${Platform.pathSeparator}Seam${Platform.pathSeparator}toast_media',
  );

  /// Draws the same fallback avatar the app shows for a chat without one:
  /// initials, or an icon for number-named chats, in the name's colours.
  Future<Uri?> _windowsFallbackAvatarFile(String name, int size) async {
    try {
      final letters = Avatar.calcFallbackLetters(name);
      final icon = Avatar.numberIcon(name);
      final colors = letters.colorScheme;
      final key =
          '$letters ${icon?.codePoint} '
                  '${colors.primaryContainer.toARGB32()}'
              .hashCode
              .toUnsigned(32);
      final file = File(
        '${(await getTemporaryDirectory()).path}'
        '${Platform.pathSeparator}notification_avatars'
        '${Platform.pathSeparator}fallback_$key.png',
      );
      if (file.existsSync()) return file.uri;

      final recorder = ui.PictureRecorder();
      final canvas = Canvas(recorder);
      canvas.drawRect(
        Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
        Paint()..color = colors.primaryContainer,
      );
      // Same text styles as the Avatar widget, scaled to the image size.
      final painter = TextPainter(
        textDirection: TextDirection.ltr,
        text: icon != null
            ? TextSpan(
                text: String.fromCharCode(icon.codePoint),
                style: TextStyle(
                  fontFamily: icon.fontFamily,
                  package: icon.fontPackage,
                  fontSize: size / 2,
                  color: colors.onPrimaryContainer,
                ),
              )
            : TextSpan(
                text: letters,
                style: TextStyle(
                  // Painted outside the widget tree, so the app font is named.
                  fontFamily: 'GoogleSansFlex',
                  fontWeight: FontWeight.bold,
                  fontSize: size / 2.5,
                  color: colors.onPrimaryContainer,
                ),
              ),
      )..layout();
      painter.paint(
        canvas,
        Offset((size - painter.width) / 2, (size - painter.height) / 2),
      );
      painter.dispose();
      final image = await recorder.endRecording().toImage(size, size);
      final png = await image.toByteData(format: ui.ImageByteFormat.png);
      image.dispose();
      if (png == null) return null;
      await file.create(recursive: true);
      await file.writeAsBytes(png.buffer.asUint8List());
      return file.uri;
    } catch (e, s) {
      Logs().w('Unable to draw a fallback avatar for a notification', e, s);
      return null;
    }
  }

  /// The members' collage of a group without a picture, cached as a file
  /// for the toast like the other avatars.
  Future<Uri?> _windowsCollageFile(Room room, int size) async {
    try {
      final bytes = await groupMembersCollage(client, room, size: size);
      if (bytes == null) return null;
      final file = File(
        '${(await getTemporaryDirectory()).path}'
        '${Platform.pathSeparator}notification_avatars'
        '${Platform.pathSeparator}collage_'
        '${sha256.convert(bytes).toString().substring(0, 16)}.png',
      );
      if (!file.existsSync()) {
        await file.create(recursive: true);
        await file.writeAsBytes(bytes);
      }
      return file.uri;
    } catch (e, s) {
      Logs().w('Unable to draw a group avatar for a notification', e, s);
      return null;
    }
  }

  /// Shown if neither the chat's avatar nor a drawn fallback is available.
  static Uri get _windowsAppLogo => Uri.file(windowsToastIcon());

  /// Windows toasts of unpackaged apps can only show local image files, so
  /// the room avatar is cached as one under the temp directory.
  Future<Uri?> _windowsAvatarFile(
    Uri avatarUrl,
    int size,
    ThumbnailMethod thumbnailMethod,
  ) async {
    try {
      final directory = Directory(
        '${(await getTemporaryDirectory()).path}'
        '${Platform.pathSeparator}notification_avatars',
      );
      final name = avatarUrl.toString().hashCode.toUnsigned(32);
      if (directory.existsSync()) {
        final cached = directory.listSync().whereType<File>().firstWhereOrNull(
          (f) => f.uri.pathSegments.last.startsWith('$name.'),
        );
        if (cached != null) return cached.uri;
      }

      final bytes = await client.downloadMxcCached(
        avatarUrl,
        width: size,
        height: size,
        thumbnailMethod: thumbnailMethod,
        isThumbnail: true,
      );
      final isPng = bytes.length > 3 && bytes[0] == 0x89 && bytes[1] == 0x50;
      final file = File(
        '${directory.path}${Platform.pathSeparator}$name.${isPng ? 'png' : 'jpg'}',
      );
      await file.create(recursive: true);
      await file.writeAsBytes(bytes);
      return file.uri;
    } catch (e, s) {
      Logs().w('Unable to cache avatar for Windows notification', e, s);
      return null;
    }
  }
}
