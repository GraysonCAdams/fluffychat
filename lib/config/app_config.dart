// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:flutter/foundation.dart';

abstract class AppConfig {
  /// Seam Cobalt, the brand colour (brand/BRAND.md) and the default seed of
  /// the colour scheme.
  static const Color primaryColor = Color(0xFF1A5AD7);

  static const Color chatColor = primaryColor;
  static const double messageFontSize = 16.0;
  static const bool allowOtherHomeservers = true;
  static const bool enableRegistration = true;
  static const bool hideTypingUsernames = false;

  static const String inviteLinkPrefix = 'https://matrix.to/#/';
  static const String schemePrefix = 'matrix:';
  // Internal Android notification channel id, never shown to the user. All
  // builds share it, so existing installs keep their channel settings.
  static const String pushNotificationsChannelId = 'fluffychat_push';
  static const double borderRadius = 18.0;
  static const double spaceBorderRadius = 11.0;
  static const double columnWidth = 360.0;

  static const String appId = 'im.fluffychat.app';
  // Seam's own id, in the dev.threeonetwo namespace: the Play build's package
  // name (android/app/build.gradle.kts) and the base of its URL schemes. On
  // Windows it is the AppUserModelID Seam's toasts are posted and registered
  // under.
  static const String seamApplicationId = 'dev.threeonetwo.seam';

  /// Whether this is the published Seam app: a release build on Android,
  /// which installs as [seamApplicationId] (android/app/build.gradle.kts).
  /// Debug and profile builds, and every other platform, keep the
  /// identifiers the existing installs were set up under, so they upgrade
  /// in place and stay logged in.
  static bool get isPlayRelease =>
      kReleaseMode &&
      !kIsWeb &&
      defaultTargetPlatform == TargetPlatform.android;

  /// The pusher app id the push gateway sees, before the device id is added.
  static String get pushNotificationsAppId =>
      isPlayRelease ? seamApplicationId : 'chat.fluffy.fluffychat';

  /// URL schemes for deep links and the SSO redirect. On Android these must
  /// match the appUrlScheme and appSsoUrlScheme manifest placeholders.
  static String get appOpenUrlScheme =>
      isPlayRelease ? seamApplicationId : 'im.fluffychat';
  static String get appSsoUrlScheme =>
      isPlayRelease ? '$seamApplicationId.auth' : 'im.fluffychat.auth';
  static String get deepLinkPrefix => '$appOpenUrlScheme://chat/';
  // Identifies Seam's notification activation callback on Windows, a CLSID
  // that names Seam's executable alone; FluffyChat's installs use another.
  // Never change!
  static const String windowsNotificationGuid =
      '6f3c1a5e-8d24-4b7a-9c0e-5a2d7e41b9f3';

  // Seam's own repository: source, issues, releases and changelog. The app is
  // a modified FluffyChat, so the About screen also credits the original.
  static const String sourceCodeUrl =
      'https://github.com/GraysonCAdams/fluffychat';
  static const String supportUrl =
      'https://github.com/GraysonCAdams/fluffychat/issues';
  static const String changelogUrl =
      'https://github.com/GraysonCAdams/fluffychat/commits/main';
  static const String latestReleaseApiUrl =
      'https://api.github.com/repos/GraysonCAdams/fluffychat/releases/latest';
  static const String upstreamSourceCodeUrl =
      'https://github.com/krille-chan/fluffychat';

  static const Set<String> defaultReactions = {'👍', '❤️', '😂', '😮', '😢'};

  static final Uri newIssueUrl = Uri(
    scheme: 'https',
    host: 'github.com',
    path: '/GraysonCAdams/fluffychat/issues/new',
  );

  static final Uri homeserverList = Uri(
    scheme: 'https',
    host: 'raw.githubusercontent.com',
    path:
        'GraysonCAdams/fluffychat/refs/heads/main/recommended_homeservers.json',
  );

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
  static const String pushHelperCrashReportKey = 'push_helper_crash_report';

  static const String vodozemacVersion = '0.9.0';
}
