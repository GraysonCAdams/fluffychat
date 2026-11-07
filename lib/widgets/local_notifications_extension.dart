// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:ui' as ui;

import 'package:collection/collection.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/notification_snooze.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:fluffychat/utils/string_color.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/fluffy_chat_app.dart';
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
    if (activeRoomId == roomId) {
      if (WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
        return;
      }
    }

    final title = event.room.getLocalizedDisplayname(
      MatrixLocals(L10n.of(context)),
    );
    final body = await event.calcLocalizedBody(
      MatrixLocals(L10n.of(context)),
      withSenderNamePrefix:
          !event.room.isDirectChat ||
          event.room.lastEvent?.senderId == client.userID,
      plaintextBody: true,
      hideReply: true,
      hideEdit: true,
      removeMarkdown: true,
    );
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
        : '${client.clientName}_$roomId'.hashCode;

    final unreadRooms = client.rooms.where((r) => r.isUnreadOrInvited).length;

    if (kIsWeb && AppSettings.webNotificationSound.value) _audioPlayer.play();

    final payload = FluffyChatPushPayload(
      client.clientName,
      event.room.id,
      event.eventId,
    ).toString();
    final windowsAvatar = !PlatformInfos.isWindows
        ? null
        : avatarUrl != null
        ? await _windowsAvatarFile(avatarUrl, size, thumbnailMethod)
        : await _windowsFallbackAvatarFile(title, size);
    final isMessage = {
      EventTypes.Message,
      EventTypes.Encrypted,
      EventTypes.Sticker,
    }.contains(event.type);

    await FlutterLocalNotificationsPlugin().show(
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
              WindowsImage(
                windowsAvatar ?? _windowsAppLogo,
                altText: title,
                placement: WindowsImagePlacement.appLogoOverride,
                crop: windowsAvatar == null ? null : WindowsImageCrop.circle,
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
          threadIdentifier: '${client.clientName}_$roomId',
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
  }

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
                  fontFamily: 'RobotoMono',
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

  /// Shown if neither the chat's avatar nor a drawn fallback is available.
  static Uri get _windowsAppLogo => Uri.file(
    '${File(Platform.resolvedExecutable).parent.path}'
    r'\data\flutter_assets\assets\logo\mini\logo_mini.png',
  );

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
