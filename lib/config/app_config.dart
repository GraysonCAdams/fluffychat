// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

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
  static const String deepLinkPrefix = 'im.fluffychat://chat/';
  static const String schemePrefix = 'matrix:';
  static const String pushNotificationsChannelId = 'fluffychat_push';
  static const String pushNotificationsAppId = 'chat.fluffy.fluffychat';
  static const double borderRadius = 18.0;
  static const double spaceBorderRadius = 11.0;
  static const double columnWidth = 360.0;

  static const String appId = 'im.fluffychat.app';
  // Seam's own id, in the dev.threeonetwo namespace, as its release build is
  // named on Android. On Windows it is the AppUserModelID Seam's toasts are
  // posted and registered under.
  static const String seamApplicationId = 'dev.threeonetwo.seam';
  static const String appOpenUrlScheme = 'im.fluffychat';
  static const String appSsoUrlScheme = 'im.fluffychat.auth';
  // Identifies the notification activation callback on Windows. Never change!
  static const String windowsNotificationGuid =
      '4894dfda-c70a-4ebc-b139-acae55f3988d';

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

  static final Uri crashReportEndpoint = Uri(
    scheme: 'https',
    host: 'crash.fluffy.chat',
  );

  static const String mainIsolatePortName = 'main_isolate';
  static const String pushIsolatePortName = 'push_isolate';
  static const String pushHelperCrashReportKey = 'push_helper_crash_report';

  static const String vodozemacVersion = '0.9.0';
}
