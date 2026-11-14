// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  final payload = FluffyChatPushPayload(
    'FluffyChat Windows',
    '!room:example.org',
    r'$event',
  ).toString();

  test('a reply button click unpacks into action, payload and input', () {
    final arguments = windowsNotificationActionArguments(
      FluffyChatNotificationActions.reply,
      payload,
    );
    // Windows hands the button's arguments back as both fields.
    final response = unpackWindowsResponse(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: arguments,
        payload: arguments,
        data: {windowsReplyInputId: 'on my way'},
      ),
    );
    expect(response.actionId, FluffyChatNotificationActions.reply.name);
    expect(response.payload, payload);
    expect(response.input, 'on my way');
    expect(
      FluffyChatPushPayload.fromString(response.payload!).roomId,
      '!room:example.org',
    );
  });

  test('a click on the toast body opens the notification', () {
    // The toast's launch arguments are its payload, and Windows passes them
    // on a body click too, which the plugin reports as an action.
    final response = unpackWindowsResponse(
      NotificationResponse(
        notificationResponseType:
            NotificationResponseType.selectedNotificationAction,
        actionId: payload,
        payload: payload,
      ),
    );
    expect(
      response.notificationResponseType,
      NotificationResponseType.selectedNotification,
    );
    expect(response.payload, payload);
  });
}
