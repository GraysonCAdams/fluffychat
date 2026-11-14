// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:isolate';
import 'dart:ui';

import 'package:collection/collection.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/client_manager.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:fluffychat/utils/windows_shell.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_vodozemac/flutter_vodozemac.dart' as vod;
import 'package:go_router/go_router.dart';
import 'package:matrix/matrix.dart';

import '../config/app_config.dart';
import '../config/setting_keys.dart';

bool _vodInitialized = false;

extension NotificationResponseJson on NotificationResponse {
  String toJsonString() => jsonEncode({
    'type': notificationResponseType.name,
    'id': id,
    'actionId': actionId,
    'input': input,
    'payload': payload,
    'data': data,
  });

  static NotificationResponse fromJsonString(String jsonString) {
    final json = jsonDecode(jsonString) as Map<String, Object?>;
    return NotificationResponse(
      notificationResponseType: NotificationResponseType.values.singleWhere(
        (t) => t.name == json['type'],
      ),
      id: json['id'] as int?,
      actionId: json['actionId'] as String?,
      input: json['input'] as String?,
      payload: json['payload'] as String?,
      data: json['data'] as Map<String, dynamic>,
    );
  }
}

Future<void> waitForPushIsolateDone() async {
  if (IsolateNameServer.lookupPortByName(AppConfig.pushIsolatePortName) !=
      null) {
    Logs().i('Wait for Push Isolate to be done...');
    await Future.delayed(const Duration(milliseconds: 300));
  }
}

@pragma('vm:entry-point')
Future<void> notificationTapBackground(
  NotificationResponse notificationResponse,
) async {
  final sendPort = IsolateNameServer.lookupPortByName(
    AppConfig.mainIsolatePortName,
  );
  if (sendPort != null) {
    sendPort.send(notificationResponse.toJsonString());
    Logs().i('Notification tap sent to main isolate!');
    return;
  }
  Logs().i(
    'Main isolate no up - Create temporary client for notification tap intend!',
  );

  final pushIsolateReceivePort = ReceivePort();
  IsolateNameServer.registerPortWithName(
    pushIsolateReceivePort.sendPort,
    AppConfig.pushIsolatePortName,
  );

  if (!_vodInitialized) {
    await vod.init();
    _vodInitialized = true;
  }
  final store = await AppSettings.init();

  final payload = FluffyChatPushPayload.fromString(
    notificationResponse.payload ?? '',
  );
  final clientName = payload.clientName;
  final client = clientName == null
      ? (await ClientManager.getClients(store: store, initialize: false)).first
      : (await ClientManager.createClient(clientName, store));
  await client.abortSync();
  await client.init(
    waitForFirstSync: false,
    waitUntilLoadCompletedLoaded: false,
  );

  if (!client.isLogged()) {
    throw Exception('Notification tab in background but not logged in!');
  }
  try {
    await notificationTap(notificationResponse, clients: [client]);
  } finally {
    await client.dispose(closeDatabase: false);
    pushIsolateReceivePort.sendPort.send('DONE');
    IsolateNameServer.removePortNameMapping(AppConfig.pushIsolatePortName);
  }
  return;
}

/// Packs a notification action with its payload into a Windows toast
/// button's arguments, which is the only value Windows hands back on click.
String windowsNotificationActionArguments(
  FluffyChatNotificationActions action,
  String payload,
) => '${action.name}#$payload';

/// The input id of the reply box on Windows toasts.
const windowsReplyInputId = 'reply';

/// Windows reports a toast button's arguments as both the action ID and the
/// payload, and typed text in [NotificationResponse.data], so unpack them into
/// the shape the other platforms report.
///
/// A click on the toast body also arrives as an action, because the plugin
/// takes any launch arguments to mean a button, and the toast's own launch
/// arguments are its payload. Button arguments always contain `#`, so
/// arguments without one are a body click.
@visibleForTesting
NotificationResponse unpackWindowsResponse(NotificationResponse response) {
  final arguments = response.actionId;
  if (response.notificationResponseType !=
          NotificationResponseType.selectedNotificationAction ||
      arguments == null) {
    return response;
  }
  if (!arguments.contains('#')) {
    return NotificationResponse(
      notificationResponseType: NotificationResponseType.selectedNotification,
      id: response.id,
      payload: arguments,
      data: response.data,
    );
  }
  final separator = arguments.indexOf('#');
  return NotificationResponse(
    notificationResponseType: response.notificationResponseType,
    id: response.id,
    actionId: arguments.substring(0, separator),
    payload: arguments.substring(separator + 1),
    input: response.data[windowsReplyInputId] as String? ?? response.input,
    data: response.data,
  );
}

Future<void> notificationTap(
  NotificationResponse response, {
  GoRouter? router,
  required List<Client> clients,
  L10n? l10n,
}) async {
  final notificationResponse = PlatformInfos.isWindows
      ? unpackWindowsResponse(response)
      : response;
  Logs().d(
    'Notification action handler started',
    notificationResponse.notificationResponseType.name,
  );
  final payload = FluffyChatPushPayload.fromString(
    notificationResponse.payload ?? '',
  );
  final client =
      clients.firstWhereOrNull(
        (client) => client.clientName == payload.clientName,
      ) ??
      clients.first;

  updateSummaryNotification(
    flutterLocalNotificationsPlugin: FlutterLocalNotificationsPlugin(),
    clientName: client.clientName,
    l10n: await lookupL10n(PlatformDispatcher.instance.locale),
  );

  switch (notificationResponse.notificationResponseType) {
    case NotificationResponseType.selectedNotification:
      final roomId = payload.roomId;
      if (roomId == null) return;

      if (router == null) {
        Logs().v('Ignore select notification action in background mode');
        return;
      }
      Logs().v('Open room from notification tap', roomId);
      await client.roomsLoading;
      await client.accountDataLoading;
      if (client.getRoomById(roomId) == null) {
        await client
            .waitForRoomInSync(roomId)
            .timeout(const Duration(seconds: 30));
      }
      router.go(_notificationRoute(client, roomId, payload.eventId));
      // Closing the window only hides it to the tray, and the toast does not
      // bring it back by itself.
      if (PlatformInfos.isWindows) await WindowsDesktop.showWindow();
    case NotificationResponseType.selectedNotificationAction:
      final actionType = FluffyChatNotificationActions.values.singleWhereOrNull(
        (action) => action.name == notificationResponse.actionId,
      );
      if (actionType == null) {
        throw Exception('Selected notification with action but no action ID');
      }
      final roomId = payload.roomId;
      if (roomId == null) {
        throw Exception('Selected notification with action but no payload');
      }
      await client.roomsLoading;
      await client.accountDataLoading;
      await client.userDeviceKeysLoading;
      final room = client.getRoomById(roomId);
      if (room == null) {
        throw Exception(
          'Selected notification with action but unknown room $roomId',
        );
      }
      switch (actionType) {
        case FluffyChatNotificationActions.markAsRead:
          await room.setReadMarker(
            payload.eventId ?? room.lastEvent!.eventId,
            mRead: payload.eventId ?? room.lastEvent!.eventId,
            public: AppSettings.sendPublicReadReceipts.value,
          );
        case FluffyChatNotificationActions.reply:
          final input = notificationResponse.input;
          if (input == null || input.isEmpty) {
            throw Exception(
              'Selected notification with reply action but without input',
            );
          }

          await room.sendTextEvent(
            input,
            parseCommands: false,
            displayPendingEvent: false,
          );
        case FluffyChatNotificationActions.mute:
          await room.setPushRuleState(PushRuleState.mentionsOnly);
        case FluffyChatNotificationActions.open:
          router?.go(_notificationRoute(client, roomId, payload.eventId));
        case FluffyChatNotificationActions.enterCall:
          router?.go('/rooms/$roomId?client=${client.clientName}&action=call');
      }
    case NotificationResponseType.notificationDismissed:
      return;
  }
}

enum FluffyChatNotificationActions { markAsRead, reply, mute, open, enterCall }

/// The chat a notification belongs to, scrolled to the notified message.
String _notificationRoute(Client client, String roomId, String? eventId) {
  final event = eventId == null || eventId.isEmpty
      ? ''
      : '&event=${Uri.encodeQueryComponent(eventId)}';
  return '/rooms/$roomId?client=${client.clientName}$event';
}
