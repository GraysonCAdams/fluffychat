// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:async/async.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:managed_configurations/managed_configurations.dart';
import 'package:matrix/matrix_api_lite/utils/logs.dart';
import 'package:shared_preferences/shared_preferences.dart';

enum AppSettings<T> {
  textMessageMaxLength<int>('textMessageMaxLength', 16384),

  /// Max lines for unselected HTML/text bubbles; 0 = unlimited (no fade).
  messagePreviewMaxLines<int>('chat.fluffy.message_preview_max_lines', 50),
  audioRecordingNumChannels<int>('audioRecordingNumChannels', 1),
  audioRecordingAutoGain<bool>('audioRecordingAutoGain', true),
  audioRecordingEchoCancel<bool>('audioRecordingEchoCancel', false),
  audioRecordingNoiseSuppress<bool>('audioRecordingNoiseSuppress', true),
  audioRecordingBitRate<int>('audioRecordingBitRate', 64000),
  audioRecordingSamplingRate<int>('audioRecordingSamplingRate', 48000),
  showNoGoogle<bool>('chat.fluffy.show_no_google', false),
  unifiedPushRegistered<bool>('chat.fluffy.unifiedpush.registered', false),
  unifiedPushEndpoint<String>('chat.fluffy.unifiedpush.endpoint', ''),
  pushNotificationsGatewayUrl<String>(
    'pushNotificationsGatewayUrl',
    'https://push.fluffychat.im/_matrix/push/v1/notify',
  ),
  pushNotificationsPusherFormat<String>(
    'pushNotificationsPusherFormat',
    'event_id_only',
  ),
  renderHtml<bool>('chat.fluffy.renderHtml', true),
  fontSizeFactor<double>('chat.fluffy.font_size_factor', 1.0),
  hideRedactedEvents<bool>('chat.fluffy.hideRedactedEvents', false),
  hideUnknownEvents<bool>('chat.fluffy.hideUnknownEvents', true),
  autoplayImages<bool>('chat.fluffy.autoplay_images', true),
  sendTypingNotifications<bool>('chat.fluffy.send_typing_notifications', true),
  // Off: reads are still marked with a private receipt, which clears unread
  // counts on the account's own devices without telling the other side.
  sendPublicReadReceipts<bool>('chat.fluffy.send_public_read_receipts', false),
  swipeRightToLeftToReply<bool>('chat.fluffy.swipeRightToLeftToReply', false),
  sendOnEnter<bool>('chat.fluffy.send_on_enter', false),
  voiceMessages<bool>('chat.fluffy.voice_messages', true),
  networkBubbleColors<bool>('chat.fluffy.network_bubble_colors', true),
  // The network and linked-chat badges on avatars in the main chat list
  // only; other lists keep theirs.
  chatListNetworkBadges<bool>('chat.fluffy.chat_list_network_badges', true),
  networkBubbleColorOverrides<String>(
    'chat.fluffy.network_bubble_color_overrides',
    '{}',
  ),
  // A JSON list of the messages whose effect has played, newest last (see
  // PlayedMessageEffects).
  playedMessageEffects<String>('chat.fluffy.played_message_effects', '[]'),
  closeToTray<bool>('chat.fluffy.close_to_tray', true),
  launchAtStartup<bool>('chat.fluffy.launch_at_startup', false),
  windowBounds<String>('chat.fluffy.window_bounds', ''),

  /// `width,height` of the last chat window, the size new ones open at.
  chatWindowSize<String>('chat.fluffy.chat_window_size', ''),

  /// Milliseconds since epoch until which no notifications are shown; 0 = off.
  snoozeNotificationsUntil<int>('chat.fluffy.snooze_notifications_until', 0),
  displayNavigationRail<bool>('chat.fluffy.display_navigation_rail', false),
  shareKeysWith<String>('chat.fluffy.share_keys_with_2', 'all'),
  noEncryptionWarningShown<bool>(
    'chat.fluffy.no_encryption_warning_shown',
    false,
  ),
  displayChatDetailsColumn('chat.fluffy.display_chat_details_column', false),
  // AppConfig-mirrored settings
  applicationName<String>('chat.fluffy.application_name', 'Seam'),
  defaultHomeserver<String>('chat.fluffy.default_homeserver', 'matrix.org'),
  // colorSchemeSeed stored as ARGB int. The default is Seam Cobalt
  // (AppConfig.primaryColor).
  colorSchemeSeedInt<int>('chat.fluffy.color_scheme_seed', 0xFF1A5AD7),
  emojiSuggestionLocale<String>('emoji_suggestion_locale', ''),
  enableSoftLogout<bool>('chat.fluffy.enable_soft_logout', true),
  enableMatrixNativeOIDC<bool>('chat.fluffy.enable_matrix_native_oidc', true),
  presetHomeserver<String>('chat.fluffy.preset_homeserver', ''),
  welcomeText<String>('chat.fluffy.welcome_text', ''),

  website<String>('chat.fluffy.website_url', 'https://fluffychat.im'),
  logoUrl<String>(
    'chat.fluffy.logo_url',
    'https://fluffychat.im/assets/favicon.png',
  ),
  privacyPolicy<String>(
    'chat.fluffy.privacy_policy_url',
    'https://fluffychat.im/privacy',
  ),
  tos<String>('chat.fluffy.tos_url', 'https://fluffychat.im/tos'),
  sendTimelineEventTimeout<int>('chat.fluffy.send_timeline_event_timeout', 15),
  webNotificationSound<bool>('chat.fluffy.web_notification_sound', true),
  chatFilter<String>('chat.fluffy.chat_filter', 'allChats'),
  hideRoomsInSpaces<bool>('chat.fluffy.hideRoomsInSpaces', false),
  openSpacesAsChatList<bool>('chat.fluffy.open_spaces_as_chat_list', true),
  suggestContactsFromChats<bool>(
    'chat.fluffy.suggest_contacts_from_chats',
    true,
  ),

  /// Whether chats that look like the same person are offered for merging.
  mergedContactSuggestions<bool>(
    'chat.fluffy.merged_contacts.suggestions',
    true,
  ),

  /// Region for phone numbers written without a country code, for matching
  /// merged contacts: 'US' (also Canada), 'other', or empty to follow the
  /// device's region.
  mergedContactsPhoneRegion<String>(
    'chat.fluffy.merged_contacts.phone_region',
    '',
  ),

  /// Whether the user said no to showing the phone's contacts in New Chat,
  /// so it does not offer again.
  phoneContactsDeclined<bool>('chat.fluffy.new_chat.contacts_declined', false),
  // A MatrixFeaturesMode name: auto, alwaysShow or alwaysHide.
  matrixFeaturesMode<String>('chat.fluffy.matrix_features.mode', 'auto'),
  // JSON object from MatrixFeature name to MatrixFeatureOverride name.
  matrixFeatureOverrides<String>('chat.fluffy.matrix_features.overrides', '{}'),
  showThumbnailsInTimeline<bool>('chat.fluffy.showThumbnailsInTimeline', true),
  // Off on every platform. A tap on a bubble shows its time, so two quick
  // taps would otherwise send a reaction by accident. The key is new so a
  // value stored by the earlier phone default (on) no longer applies.
  doubleTapToReact<bool>('chat.fluffy.double_tap_to_react_v2', false),
  doubleTapReaction<String>('chat.fluffy.double_tap_reaction', '❤️'),
  benchmarksInLogs<bool>('chat.fluffy.benchmarks_in_logs', false),
  autoSendErrorReports<bool?>('chat.fluffy.auto_send_eror_reports', null),
  knownErrorHashes<List<String>>('chat.fluffy.known_crash_hashes', []),
  checkForUpdates<bool>('chat.fluffy.check_for_updates', true),
  lastUpdateCheckDate<String>('chat.fluffy.last_update_check_date', ''),
  fallbackLiveKitInstance<String>('chat.fluffy.fallback_live_kit_instance', '');

  final String key;
  final T _defaultValue;

  const AppSettings(this.key, this._defaultValue);

  /// FluffyChat's purple, the default [colorSchemeSeedInt] before Seam Cobalt.
  static const int legacyColorSchemeSeed = 0xFF5625BA;

  static SharedPreferences get store => _store!;
  static SharedPreferences? _store;

  static Map<String, Object?>? _platformConfiguration;

  T get defaultValue {
    final platformConfig = _platformConfiguration?[name];
    if (platformConfig is T) return platformConfig;
    return _defaultValue;
  }

  static Future<void> reset({bool loadWebConfigFile = true}) async {
    for (final setting in AppSettings.values) {
      await AppSettings.store.remove(setting.key);
    }
    await init(loadWebConfigFile: loadWebConfigFile);
  }

  static Future<SharedPreferences> init({bool loadWebConfigFile = true}) async {
    if (AppSettings._store != null) return AppSettings.store;

    final store = AppSettings._store = await SharedPreferences.getInstance();

    // Migrate wrong datatype for fontSizeFactor
    final fontSizeFactorString = Result(
      () => store.getString(AppSettings.fontSizeFactor.key),
    ).asValue?.value;
    if (fontSizeFactorString != null) {
      Logs().i('Migrate wrong datatype for fontSizeFactor!');
      await store.remove(AppSettings.fontSizeFactor.key);
      final fontSizeFactor = double.tryParse(fontSizeFactorString);
      if (fontSizeFactor != null) {
        await store.setDouble(AppSettings.fontSizeFactor.key, fontSizeFactor);
      }
    }

    // Picking the system colour used to store the default seed, FluffyChat
    // purple. Treat that as unset so the user gets Seam Cobalt.
    if (Result(
          () => store.getInt(AppSettings.colorSchemeSeedInt.key),
        ).asValue?.value ==
        legacyColorSchemeSeed) {
      await store.remove(AppSettings.colorSchemeSeedInt.key);
    }

    if (store.getBool(AppSettings.sendOnEnter.key) == null) {
      await store.setBool(AppSettings.sendOnEnter.key, !PlatformInfos.isMobile);
    }

    // Load configuration from config.json file or MDM:
    if (PlatformInfos.isMobile) {
      _platformConfiguration =
          await ManagedConfigurations().getManagedConfigurations;
    } else if (kIsWeb && loadWebConfigFile) {
      try {
        final configJsonString = utf8.decode(
          (await http.get(Uri.parse('config.json'))).bodyBytes,
        );
        _platformConfiguration =
            json.decode(configJsonString) as Map<String, Object?>;
      } on FormatException catch (_) {
        Logs().v('[ConfigLoader] config.json not found');
      } catch (e) {
        Logs().v('[ConfigLoader] config.json not found', e);
      }
    }

    return store;
  }
}

extension AppSettingsBoolNExtension on AppSettings<bool?> {
  bool? get value {
    final value = Result(() => AppSettings.store.getBool(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value;
  }

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
}

extension AppSettingsBoolExtension on AppSettings<bool> {
  bool get value {
    final value = Result(() => AppSettings.store.getBool(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(bool value) => AppSettings.store.setBool(key, value);
}

extension AppSettingsStringExtension on AppSettings<String> {
  String get value {
    final value = Result(() => AppSettings.store.getString(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(String value) => AppSettings.store.setString(key, value);
}

extension AppSettingsIntExtension on AppSettings<int> {
  int get value {
    final value = Result(() => AppSettings.store.getInt(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(int value) => AppSettings.store.setInt(key, value);
}

extension AppSettingsDoubleExtension on AppSettings<double> {
  double get value {
    final value = Result(() => AppSettings.store.getDouble(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(double value) => AppSettings.store.setDouble(key, value);
}

extension AppSettingsStringListExtension on AppSettings<List<String>> {
  List<String> get value {
    final value = Result(() => AppSettings.store.getStringList(key));
    final error = value.asError;
    if (error != null) {
      Logs().e(
        'Unable to fetch $key from storage. Removing entry...',
        error.error,
        error.stackTrace,
      );
    }
    return value.asValue?.value ?? defaultValue;
  }

  Future<void> setItem(List<String> value) =>
      AppSettings.store.setStringList(key, value);
}
