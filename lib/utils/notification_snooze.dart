// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';

/// When notifications come back, or null if they are not snoozed.
DateTime? get notificationsSnoozedUntil {
  final until = DateTime.fromMillisecondsSinceEpoch(
    AppSettings.snoozeNotificationsUntil.value,
  );
  return until.isAfter(DateTime.now()) ? until : null;
}

Future<void> snoozeNotificationsUntil(DateTime? until) => AppSettings
    .snoozeNotificationsUntil
    .setItem(until?.millisecondsSinceEpoch ?? 0);

/// The next 8:00 after now, for "until tomorrow morning".
DateTime get nextMorning {
  final now = DateTime.now();
  final today = DateTime(now.year, now.month, now.day, 8);
  return today.isAfter(now) ? today : today.add(const Duration(days: 1));
}
