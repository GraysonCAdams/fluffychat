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
  // name (android/app/build.gradle.kts) and its deep link scheme. On
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

  /// The app group the iOS app shares with its notification service and
  /// share extensions: the database directory and the keychain item holding
  /// the database key live there. Must match the three entitlements files in
  /// ios/ and NotificationService.swift.
  static const String seamAppGroupId = 'group.$seamApplicationId';

  /// Whether this build carries Seam's own identifiers and store defaults:
  /// the Play release, and every iOS and macOS build, which are bundled as
  /// [seamApplicationId] in all build modes (ios/ and macos/ Xcode projects).
  static bool get usesSeamIdentity =>
      isPlayRelease ||
      (!kIsWeb &&
          (defaultTargetPlatform == TargetPlatform.iOS ||
              defaultTargetPlatform == TargetPlatform.macOS));

  /// The Matrix push gateway that relays to APNs for the iOS app, set at
  /// build time with `--dart-define=SEAM_PUSH_GATEWAY_URL=...`. Empty means
  /// the build registers no pusher on iOS.
  static const String applePushGatewayUrl = String.fromEnvironment(
    'SEAM_PUSH_GATEWAY_URL',
  );

  /// The pusher app id the push gateway sees, before the device id is added.
  static String get pushNotificationsAppId =>
      usesSeamIdentity ? seamApplicationId : 'chat.fluffy.fluffychat';

  /// URL scheme for deep links. On Android it must match the appUrlScheme
  /// manifest placeholder, on iOS the CFBundleURLSchemes in
  /// ios/Runner/Info.plist.
  static String get appOpenUrlScheme =>
      usesSeamIdentity ? seamApplicationId : 'im.fluffychat';

  /// SSO redirect schemes (Android, iOS and macOS; desktop redirects to
  /// localhost). OIDC requires a native client's private-use scheme to start
  /// with the host of its client_uri (AppSettings.website, seam.312.dev) in
  /// reverse, and homeservers such as matrix.org refuse the registration
  /// otherwise. Debug and profile builds take their own scheme, so they and
  /// the release app on one device do not both claim the redirect. On Android
  /// these must match the appSsoUrlScheme manifest placeholders in
  /// android/app/build.gradle.kts; on iOS both are listed in the
  /// CFBundleURLSchemes of ios/Runner/Info.plist.
  static const String releaseSsoUrlScheme = 'dev.312.seam.auth';
  static const String developmentSsoUrlScheme = 'dev.312.seam.dev.auth';
  static String get appSsoUrlScheme =>
      kReleaseMode ? releaseSsoUrlScheme : developmentSsoUrlScheme;
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
