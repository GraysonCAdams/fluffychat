# flutter_local_notifications 22.3.3, patched for FluffyChat

A copy of the pub.dev release (`lib/`, `android/`, `ios/`, `macos/`), used
through `dependency_overrides` in the app's `pubspec.yaml`.

The patch adds `AndroidNotificationDetails.bubbleActivity`: the class name of
an embeddable activity that shows the conversation as an Android chat bubble.
When it and `shortcutId` are set, on Android 10 and later the plugin attaches
`NotificationCompat.BubbleMetadata` with a mutable pending intent that starts
that activity with the shortcut ID as the `shortcutId` extra.

Patched spots are marked `FluffyChat:` in
`lib/src/platform_specifics/android/notification_details.dart`,
`lib/src/platform_specifics/android/method_channel_mappers.dart`,
`android/.../models/NotificationDetails.java` and
`android/.../FlutterLocalNotificationsPlugin.java`. To move to a newer
release, copy it over this one and reapply those hunks.
