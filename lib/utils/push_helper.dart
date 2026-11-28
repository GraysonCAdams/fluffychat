// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/android_bubble.dart';
import 'package:fluffychat/utils/android_conversation_notifications.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/conversation_shortcut_icon.dart';
import 'package:fluffychat/utils/fallback_avatar_image.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_locals.dart';
import 'package:fluffychat/utils/merged_contacts/conversation.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:fluffychat/utils/notification_avatar_extension.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/notification_body.dart';
import 'package:fluffychat/utils/notification_media.dart';
import 'package:fluffychat/utils/notification_snooze.dart';
import 'package:fluffychat/utils/one_time_code.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/room_kind.dart';
import 'package:fluffychat/utils/start_push_foreground_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_new_badger/flutter_new_badger.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart' hide Result;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:synchronized/synchronized.dart';

final Map<String, DateTime> lastReceivedPushNotification = {};

final _pushLock = Lock();

Future<void> pushHelper(
  PushNotification notification, {
  List<Client>? clients,
  L10n? l10n,
  String? activeRoomId,
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
}) async {
  l10n ??= await lookupL10n(PlatformDispatcher.instance.locale);

  try {
    await _pushLock.synchronized(
      () => _tryPushHelper(
        notification,
        clients: clients,
        l10n: l10n,
        activeRoomId: activeRoomId,
        flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
      ).timeout(const Duration(seconds: 30)),
    );
  } catch (e, s) {
    if (e.toString() == 'Exception: Client is not logged in.') {
      Logs().w('Ignore push notification, when not logged in', e);
      return;
    }
    if (PlatformInfos.isAndroid &&
        e is! TimeoutException &&
        e is! IOException &&
        e is! http.ClientException) {
      Logs().e('Push Helper has crashed! Writing into temporary file...', e, s);
      final store = await SharedPreferences.getInstance();
      await store.setStringList(AppConfig.pushHelperCrashReportKey, [
        e.toString(),
        s.toString(),
      ]);
    }

    if (notification.roomId != null) {
      await flutterLocalNotificationsPlugin.show(
        id: notification.notificationId,
        title: l10n.newMessageInFluffyChat,
        body: l10n.openAppToReadMessages,
        notificationDetails: NotificationDetails(
          iOS: DarwinNotificationDetails(
            threadIdentifier:
                '${notification.clientName}_${notification.roomId}',
          ),
          android: AndroidNotificationDetails(
            AppConfig.pushNotificationsChannelId,
            l10n.incomingMessages,
            number: notification.counts?.unread,
            ticker: l10n.unreadChatsInApp(
              AppSettings.applicationName.value,
              (notification.counts?.unread ?? 0).toString(),
            ),
            importance: Importance.high,
            priority: Priority.max,
            shortcutId: notification.roomId,
            category: AndroidNotificationCategory.message,
            groupKey: notification.clientName,
          ),
        ),
      );
    }
    rethrow;
  } finally {
    if (!_pushLock.locked) ForegroundServices.stopService('background_push');
  }
}

Future<void> _tryPushHelper(
  PushNotification notification, {
  List<Client>? clients,
  L10n? l10n,
  String? activeRoomId,
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
}) async {
  final isBackgroundMessage = clients == null;
  Logs().v(
    'Push helper has been started (background=$isBackgroundMessage).',
    // The full payload is only useful while debugging, and serializing it
    // on every push costs time on the UI isolate in release builds.
    kDebugMode ? notification.toJson() : null,
  );

  final clientName = notification.clientName;
  final store = await AppSettings.init();

  final client = clientName == null
      ? (clients?.first ??
            (await ClientManager.getClients(
              initialize: false,
              store: store,
            )).first)
      : (clients?.firstWhereOrNull(
              (client) => client.clientName == clientName,
            ) ??
            await ClientManager.createClient(clientName, store));

  lastReceivedPushNotification[client.clientName] = DateTime.now();

  l10n ??= await L10n.delegate.load(PlatformDispatcher.instance.locale);

  Logs().v('Load event...');
  final event = await client.getEventByPushNotification(
    notification,
    storeInDatabase: false,
  );

  updateAppBadge(notification.counts?.unread ?? 0);

  if (event == null) {
    Logs().v('Notification is a clearing indicator.');
    if (client.syncPending) return;
    if (clients?.length == 1 && (notification.counts?.unread == 0)) {
      await flutterLocalNotificationsPlugin.cancelAll();
    } else {
      // Make sure client is fully loaded and synced before dismiss notifications:
      await client.roomsLoading;
      await client
          .oneShotSync()
          .timeout(const Duration(seconds: 8))
          .catchError((_) => null);
      await cancelNotificationsOnSync(
        client.onSync.value!,
        clientName!,
        client.userID!,
        l10n,
        flutterLocalNotificationsPlugin,
        client: client,
      );
    }
    return;
  }

  Logs().v('Push helper got notification event of type ${event.type}.');

  if (notificationsSnoozedUntil != null) {
    Logs().i('Push helper: notifications are snoozed.');
    return;
  }

  if (!client.pushruleEvaluator.match(event).notify) {
    Logs().i('Push helper: filtered by client-side push rules.');
    return;
  }

  // Waits for the merged contacts too, which decide below whether this room
  // is on screen and which conversation it belongs to.
  await MergedContactsStore.forClient(client).loaded;

  if (notification.roomId != null &&
      isChatActive(activeRoomId, client, notification.roomId!) &&
      WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed) {
    Logs().v('Room is in foreground. Stop push helper here.');
    return;
  }

  final body = event.type == EventTypes.Encrypted
      ? l10n.newMessageInFluffyChat
      : notificationBodyOf(event, l10n);

  // The person object for the android message style notification
  final avatar = event.room.chatAvatar;
  final senderAvatar = event.room.isOneToOne
      ? avatar
      : event.senderFromMemoryOrFallback.avatarUrl;

  final ownUser = event.room.unsafeGetUserFromMemoryOrFallback(client.userID!);

  final userAvatarFile = await client.tryDownloadNotificationAvatar(
    ownUser.avatarUrl,
  );
  final senderAvatarFile = await client.tryDownloadNotificationAvatar(
    senderAvatar,
  );

  // A room in a merged contact shares one conversation (notification,
  // channel, shortcut) with the contact's other rooms.
  final conversation = notificationConversation(client, event.room.id);
  final id = '${client.clientName}_$conversation'.hashCode;

  final senderName = event.senderFromMemoryOrFallback.calcDisplayname();
  // A sender without a picture gets their initials, as in the app.
  final senderIcon = senderAvatarFile ?? await renderFallbackAvatar(senderName);
  // Show notification

  // Photos and videos show in the notification. Anything that goes wrong
  // getting one leaves the text, never no notification.
  final media = PlatformInfos.isAndroid
      ? await notificationMediaOf(event)
      : null;

  final newMessage = notificationMessage(
    event,
    body: body,
    person: Person(
      bot: notificationSenderIsBot(event),
      key: event.senderId,
      name: senderName,
      icon: senderIcon == null ? null : ByteArrayAndroidIcon(senderIcon),
    ),
    media: media,
  );

  final messagingStyleInformation = PlatformInfos.isAndroid
      ? await AndroidFlutterLocalNotificationsPlugin()
            .getActiveNotificationMessagingStyle(id: id)
      : null;
  final activeMessages = messagingStyleInformation?.messages;
  if (activeMessages != null) {
    // The edit that brings a bridge's awaited attachment takes the line of
    // the placeholder notice it edits.
    final merged = withNotificationMessage(
      activeMessages,
      newMessage,
      replacedTime: hasNotificationMedia(event)
          ? await editedEventTime(event)
          : null,
    );
    activeMessages
      ..clear()
      ..addAll(merged);
  }

  final roomName =
      notificationConversationName(client, event.room.id, MatrixLocals(l10n)) ??
      event.room.chatDisplayname(MatrixLocals(l10n));

  final notificationGroupId = event.room.isOneToOne
      ? 'directChats'
      : 'groupChats';
  final groupName = event.room.isOneToOne ? l10n.directChats : l10n.groups;

  final messageRooms = AndroidNotificationChannelGroup(
    notificationGroupId,
    groupName,
  );

  await flutterLocalNotificationsPlugin
      .resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin
      >()
      ?.createNotificationChannelGroup(messageRooms);

  if (PlatformInfos.isAndroid) {
    await AndroidConversationNotifications.createConversationChannel(
      id: conversation,
      name: roomName,
      groupId: notificationGroupId,
      parentChannelId: AppConfig.pushNotificationsChannelId,
      shortcutId: conversation,
    );
  }

  final androidPlatformChannelSpecifics = AndroidNotificationDetails(
    conversation,
    roomName,
    number: notification.counts?.unread,
    category: AndroidNotificationCategory.message,
    shortcutId: conversation,
    // The system only bubbles chats the user allows bubbles for.
    bubbleActivity: AndroidBubble.activityClass,
    styleInformation:
        messagingStyleInformation ??
        MessagingStyleInformation(
          Person(
            name: ownUser.calcDisplayname(),
            icon: userAvatarFile == null
                ? null
                : ByteArrayAndroidIcon(userAvatarFile),
            key: event.room.client.userID,
          ),
          conversationTitle: event.room.isOneToOne ? null : roomName,
          groupConversation: !event.room.isOneToOne,
          messages: [newMessage],
        ),
    ticker: event.room.isOneToOne ? body : l10n.senderMessage(senderName, body),
    importance: Importance.high,
    priority: Priority.max,
    groupKey: client.clientName,
    actions: androidNotificationActions(event, l10n),
  );
  final iOSAttachmentPath = PlatformInfos.isIOS
      ? await client.getIosNotificationAvatar(event.room.chatAvatar)
      : null;
  final iOSPlatformChannelSpecifics = DarwinNotificationDetails(
    threadIdentifier: '${notification.clientName}_$conversation',
    attachments: iOSAttachmentPath == null
        ? null
        : [
            DarwinNotificationAttachment(
              iOSAttachmentPath,
              identifier: 'image',
            ),
          ],
  );
  final platformChannelSpecifics = NotificationDetails(
    android: androidPlatformChannelSpecifics,
    iOS: iOSPlatformChannelSpecifics,
  );

  final title = roomName;

  if (PlatformInfos.isAndroid) {
    await AndroidConversationNotifications.publishShortcut(
      id: conversation,
      name: roomName,
      roomUrl: AppConfig.inviteLinkPrefix + event.room.id,
      // The shortcut's picture is the conversation icon of this
      // notification, so it is pushed with the chat list's picture before
      // the notification is shown.
      avatar: await conversationShortcutIcon(client, event.room, roomName),
      isImportant: event.room.isFavourite,
    );
  }

  final needsTitleAndBody = !PlatformInfos.isAndroid;

  await flutterLocalNotificationsPlugin.show(
    // Apple platforms show one notification per message; elsewhere one per
    // conversation, updated as messages come in.
    id: PlatformInfos.isCupertinoStyle ? notification.notificationId : id,
    title: needsTitleAndBody ? title : null,
    body: needsTitleAndBody ? body : null,
    notificationDetails: platformChannelSpecifics,
    payload: FluffyChatPushPayload(
      client.clientName,
      event.room.id,
      event.eventId,
    ).toString(),
  );

  // Send summary notification on Android
  if (PlatformInfos.isAndroid) {
    await updateSummaryNotification(
      clientName: client.clientName,
      l10n: l10n,
      flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
    );
  }
  Logs().v('Push helper has been completed!');
}

/// The buttons of an Android notification for [event]. Android shows three
/// at most. A message with a one-time code (see [oneTimeCodeOf]) offers to
/// copy it first, which also marks it read, in place of muting: a code's
/// sender is seldom one to mute from the notification, while replying and
/// marking read without copying stay useful.
List<AndroidNotificationAction>? androidNotificationActions(
  Event event,
  L10n l10n,
) {
  switch (event.type) {
    case EventTypes.Message || EventTypes.Encrypted || EventTypes.Sticker:
      final code = oneTimeCodeOf(event);
      return [
        if (code != null)
          AndroidNotificationAction(
            FluffyChatNotificationActions.copyCode.name,
            l10n.copyOneTimeCode(code),
            clipboardText: code,
          ),
        AndroidNotificationAction(
          FluffyChatNotificationActions.reply.name,
          l10n.reply,
          inputs: [AndroidNotificationActionInput(label: l10n.writeAMessage)],
          allowGeneratedReplies: true,
          semanticAction: SemanticAction.reply,
        ),
        AndroidNotificationAction(
          FluffyChatNotificationActions.markAsRead.name,
          l10n.markAsRead,
          semanticAction: SemanticAction.markAsRead,
        ),
        if (code == null)
          AndroidNotificationAction(
            FluffyChatNotificationActions.mute.name,
            l10n.mute,
            semanticAction: SemanticAction.mute,
          ),
      ];
    default:
      return null;
  }
}

void updateAppBadge(int unreadCount) {
  if (PlatformInfos.isAndroid || PlatformInfos.isMacOS || PlatformInfos.isIOS) {
    if (unreadCount == 0) {
      FlutterNewBadger.removeBadge();
    } else {
      FlutterNewBadger.setBadge(unreadCount);
    }
    return;
  }
}

Future<void> updateSummaryNotification({
  required FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin,
  required String clientName,
  required L10n l10n,
}) async {
  final activeNotifications =
      (await flutterLocalNotificationsPlugin.getActiveNotifications())
          .where((n) => n.groupKey == clientName && n.id != clientName.hashCode)
          .toList();

  if (activeNotifications.isEmpty) {
    await flutterLocalNotificationsPlugin.cancel(id: clientName.hashCode);
    return;
  }

  if (activeNotifications.any(
    (notification) => notification.id == clientName.hashCode,
  )) {
    // Already have a visible summary notification!
    return;
  }

  await flutterLocalNotificationsPlugin.show(
    id: clientName.hashCode,
    notificationDetails: NotificationDetails(
      android: AndroidNotificationDetails(
        AppConfig.pushNotificationsChannelId,
        l10n.incomingMessages,
        groupKey: clientName,
        setAsGroupSummary: true,
        styleInformation: InboxStyleInformation(
          activeNotifications.map((n) => n.body ?? '').toList(),
        ),
        autoCancel: false,
        silent: true,
      ),
    ),
  );
}

class FluffyChatPushPayload {
  final String? clientName, roomId, eventId;

  FluffyChatPushPayload(this.clientName, this.roomId, this.eventId);

  factory FluffyChatPushPayload.fromString(String payload) {
    final parts = payload.split('|');
    if (parts.length != 3) {
      return FluffyChatPushPayload(null, null, null);
    }
    return FluffyChatPushPayload(parts.first, parts[1], parts[2]);
  }

  @override
  String toString() => '$clientName|$roomId|$eventId';
}

extension on PushNotification {
  String? get clientName =>
      devices?.firstOrNull?.data?.tryGet<String>('client_name');
  int get notificationId {
    final roomId = this.roomId;
    if (roomId == null) return 0;
    final clientName = this.clientName;
    if (PlatformInfos.isCupertinoStyle) {
      return '${clientName}_${roomId}_$eventId'.hashCode;
    }
    if (clientName == null) return roomId.hashCode;
    return '${clientName}_$roomId'.hashCode;
  }
}

Future<void> cancelNotificationsOnSync(
  SyncUpdate syncUpdate,
  String clientName,
  String userId,
  L10n l10n,
  FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin, {

  /// The account, to keep a merged contact's notification until all of its
  /// rooms are read.
  Client? client,
}) async {
  final newReadRoomIds =
      syncUpdate.rooms?.join?.entries
          .where(
            (entry) =>
                (entry.value.ephemeral?.any(
                      (event) =>
                          event.type == 'm.receipt' &&
                          event.content.values.any(
                            (value) =>
                                value is Map<String, Object?> &&
                                (value
                                            .tryGetMap<String, Object?>(
                                              'm.read',
                                            )
                                            ?.keys
                                            .contains(userId) ==
                                        true ||
                                    value
                                            .tryGetMap<String, Object?>(
                                              'm.read.private',
                                            )
                                            ?.keys
                                            .contains(userId) ==
                                        true),
                          ),
                    ) ??
                    false) &&
                entry.value.unreadNotifications?.notificationCount == 0,
          )
          .map((entry) => entry.key)
          .toSet() ??
      {};
  if (newReadRoomIds.isEmpty) return;

  List<ActiveNotification>? activeNotifications;

  for (final roomId in newReadRoomIds) {
    if (PlatformInfos.isMacOS || PlatformInfos.isIOS || PlatformInfos.isWeb) {
      activeNotifications ??= await flutterLocalNotificationsPlugin
          .getActiveNotifications();
      for (final notification in activeNotifications) {
        final payload = FluffyChatPushPayload.fromString(
          notification.payload ?? '',
        );
        if (payload.clientName != clientName || payload.roomId != roomId) {
          continue;
        }
        final id = notification.id;
        // TODO: notifications from NSE have no id. How to clean them up?
        if (id == null) continue;
        await flutterLocalNotificationsPlugin.cancel(id: id);
      }
      continue;
    }
    // A merged contact's notification stays until all its rooms are read.
    if (client != null && !notificationConversationRead(client, roomId)) {
      continue;
    }
    final conversation = client == null
        ? roomId
        : notificationConversation(client, roomId);
    final id = '${clientName}_$conversation'.hashCode;
    await flutterLocalNotificationsPlugin.cancel(id: id);
  }

  if (PlatformInfos.isAndroid) {
    await updateSummaryNotification(
      clientName: clientName,
      flutterLocalNotificationsPlugin: flutterLocalNotificationsPlugin,
      l10n: l10n,
    );
  }
}
