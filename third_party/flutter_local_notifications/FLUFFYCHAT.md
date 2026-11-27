# flutter_local_notifications 23.0.0, patched for FluffyChat

A copy of the pub.dev release (`lib/`, `android/`, `ios/`, `macos/`), used
through `dependency_overrides` in the app's `pubspec.yaml`.

The patch adds `AndroidNotificationDetails.bubbleActivity`: the class name of
an embeddable activity that shows the conversation as an Android chat bubble.
When it and `shortcutId` are set, on Android 10 and later the plugin attaches
`NotificationCompat.BubbleMetadata` with a mutable pending intent that starts
that activity with the shortcut ID as the `shortcutId` extra.

The patch also grants `com.android.systemui` read access to a message's
`dataUri` when it is a `content://` URI of the app's own provider, in
`createMessage` of `FlutterLocalNotificationsPlugin.java`, so the picture of a
`MessagingStyle` message shows.

The patch also adds `AndroidNotificationAction.clipboardText`: the action's
intent carries the text, and `ActionBroadcastReceiver` copies it to the
clipboard (as a sensitive clip on Android 13 and later) before handing the
action to Dart, since the background isolate that handles actions has no
activity for Flutter's clipboard.

Patched spots are marked `FluffyChat:` in
`lib/src/platform_specifics/android/notification_details.dart`,
`lib/src/platform_specifics/android/method_channel_mappers.dart`,
`android/.../models/NotificationDetails.java`,
`android/.../models/NotificationAction.java`,
`android/.../ActionBroadcastReceiver.java` and
`android/.../FlutterLocalNotificationsPlugin.java`. To move to a newer
release, copy it over this one and reapply those hunks.
