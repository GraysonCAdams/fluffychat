// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/notification_background_handler.dart';
import 'package:fluffychat/utils/push_helper.dart';
import 'package:fluffychat/widgets/local_notifications_extension.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show Locale;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import '../pages/chat_list/chat_list_fakes.dart';

/// No notifications are showing, so no summary needs updating.
class _NoNotifications extends FlutterLocalNotificationsPlatform {
  @override
  Future<List<ActiveNotification>> getActiveNotifications() async => [];
}

/// A notification for a message with a one-time code offers to copy it,
/// and the button copies the code and marks the message read.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late FakeChatListClient client;
  late FakeChatListRoom room;
  late L10n l10n;
  String? clipboard;

  setUp(() async {
    client = await setUpFakeChatList('notification copy code');
    room = addFakeChat(
      client,
      '!bank:x',
      'Bank',
      partner: '@bank:x',
      notificationCount: 1,
    );
    l10n = await lookupL10n(const Locale('en'));
    FlutterLocalNotificationsPlatform.instance = _NoNotifications();
    clipboard = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (call) async {
          if (call.method == 'Clipboard.setData') {
            clipboard = (call.arguments as Map)['text'] as String?;
          }
          return null;
        });
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
    tearDownFakeChatList(client);
  });

  Event message(
    String body, {
    String sender = '@bank:x',
    Map<String, Object?> extra = const {},
  }) => Event(
    content: {'msgtype': MessageTypes.Text, 'body': body, ...extra},
    type: EventTypes.Message,
    eventId: r'$code',
    senderId: sender,
    originServerTs: DateTime(2026),
    room: room,
  );

  const otp = 'Your Apple Account Code is: 837669. Do not share it.';

  group('Android', () {
    test('a code takes the place of mute, first of the three', () {
      final actions = androidNotificationActions(message(otp), l10n)!;
      expect(actions.map((a) => a.id), [
        FluffyChatNotificationActions.copyCode.name,
        FluffyChatNotificationActions.reply.name,
        FluffyChatNotificationActions.markAsRead.name,
      ]);
      expect(actions.first.title, 'Copy "837669"');
      // The plugin copies it natively; the background isolate cannot.
      expect(actions.first.clipboardText, '837669');
      expect(actions.first.cancelNotification, isTrue);
    });

    test('a message without a code keeps reply, mark as read and mute', () {
      final actions = androidNotificationActions(
        message('See you at 1830'),
        l10n,
      )!;
      expect(actions.map((a) => a.id), [
        FluffyChatNotificationActions.reply.name,
        FluffyChatNotificationActions.markAsRead.name,
        FluffyChatNotificationActions.mute.name,
      ]);
      expect(actions.every((a) => a.clipboardText == null), isTrue);
    });

    test('invisible ink never offers its code', () {
      final ink = message(
        otp,
        extra: {messageEffectKey: MessageEffect.invisibleInk.id},
      );
      expect(
        androidNotificationActions(ink, l10n)!.map((a) => a.id),
        isNot(contains(FluffyChatNotificationActions.copyCode.name)),
      );
    });
  });

  group('Windows', () {
    final payload = FluffyChatPushPayload(
      'notification copy code',
      '!bank:x',
      r'$code',
    ).toString();

    test('a code adds a copy button before reply and mark as read', () {
      final actions = windowsNotificationActions(message(otp), l10n, payload);
      expect(actions.map((a) => a.content), [
        'Copy "837669"',
        l10n.reply,
        l10n.markAsRead,
      ]);
      final response = unpackWindowsResponse(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: actions.first.arguments,
          payload: actions.first.arguments,
        ),
      );
      expect(response.actionId, FluffyChatNotificationActions.copyCode.name);
      expect(response.payload, payload);
      expect(response.data[windowsCopyCodeKey], '837669');
    });

    test('invisible ink never offers its code', () {
      final ink = message(
        otp,
        extra: {messageEffectKey: MessageEffect.invisibleInk.id},
      );
      expect(windowsNotificationActions(ink, l10n, payload), hasLength(2));
    });

    test('the copy button copies the code and marks the message read, '
        'through the toast activation handler', () async {
      final arguments = windowsNotificationActionArguments(
        FluffyChatNotificationActions.copyCode,
        payload,
        code: '837669',
      );
      await notificationTap(
        NotificationResponse(
          notificationResponseType:
              NotificationResponseType.selectedNotificationAction,
          actionId: arguments,
          payload: arguments,
        ),
        clients: [client],
        l10n: l10n,
      );
      expect(clipboard, '837669');
      expect(room.readMarkers, [r'$code']);
      // Windows unpacks toast arguments only on Windows.
    }, testOn: 'windows');
  });
}
