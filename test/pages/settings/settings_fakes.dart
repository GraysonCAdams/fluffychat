// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/device_settings/device_settings.dart';
import 'package:fluffychat/pages/settings/settings.dart';
import 'package:fluffychat/pages/settings_3pid/settings_3pid.dart';
import 'package:fluffychat/pages/settings_chat/settings_chat.dart';
import 'package:fluffychat/pages/settings_chat/settings_swipe_actions.dart';
import 'package:fluffychat/pages/settings_homeserver/settings_homeserver.dart';
import 'package:fluffychat/pages/settings_ignore_list/settings_ignore_list.dart';
import 'package:fluffychat/pages/settings_matrix_features/settings_matrix_features.dart';
import 'package:fluffychat/pages/settings_merged_contacts/settings_merged_contacts.dart';
import 'package:fluffychat/pages/settings_notifications/settings_notifications.dart';
import 'package:fluffychat/pages/settings_password/settings_password.dart';
import 'package:fluffychat/pages/settings_security/settings_security.dart';
import 'package:fluffychat/pages/settings_style/settings_style.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/theme_builder.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat_list/chat_list_fakes.dart';

/// Answers every request with a Matrix "not found" error, so nothing in a
/// settings page waits on the network.
class NotFoundHttp extends http.BaseClient {
  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async =>
      http.StreamedResponse(
        Stream.value(
          utf8.encode(
            jsonEncode({'errcode': 'M_NOT_FOUND', 'error': 'Not found'}),
          ),
        ),
        404,
        headers: {'content-type': 'application/json'},
      );
}

/// A synced-looking client that answers what the settings pages ask the
/// homeserver for: the profile, the account management link, capabilities,
/// devices, pushers, the well-known files and the recovery addresses.
class FakeSettingsClient extends FakeChatListClient {
  FakeSettingsClient(super.clientName, {required super.database});

  static const displayName = 'Gray';
  static const thisDeviceId = 'THISDEVICE';

  @override
  String? get deviceID => thisDeviceId;

  @override
  Future<Profile> getProfileFromUserId(
    String userId, {
    bool? getFromRooms,
    bool? cache,
    Duration timeout = const Duration(seconds: 30),
    Duration maxCacheAge = const Duration(days: 1),
  }) async => Profile(userId: userId, displayName: displayName);

  @override
  Future<GetAuthMetadataResponse> getAuthMetadata({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async => GetAuthMetadataResponse(
    accountManagementUri: Uri.parse('https://x/account'),
    authorizationEndpoint: Uri.parse('https://x/authorize'),
    codeChallengeMethodsSupported: const [],
    grantTypesSupported: const [],
    issuer: Uri.parse('https://x/'),
    registrationEndpoint: Uri.parse('https://x/register'),
    responseModesSupported: const [],
    responseTypesSupported: const [],
    revocationEndpoint: Uri.parse('https://x/revoke'),
    tokenEndpoint: Uri.parse('https://x/token'),
  );

  /// Nothing is stored on the server, the cross-signing keys included.
  @override
  Future<Map<String, Object?>> getAccountData(String userId, String type) =>
      throw MatrixException.fromJson({
        'errcode': 'M_NOT_FOUND',
        'error': 'Not found',
      });

  @override
  Future<Capabilities> getCapabilities() async => Capabilities();

  @override
  Future<List<Device>?> getDevices() async => [
    Device(
      deviceId: thisDeviceId,
      displayName: 'Seam Android',
      lastSeenTs: DateTime(2026, 11, 20).millisecondsSinceEpoch,
    ),
    Device(
      deviceId: 'OTHERDEVICE',
      displayName: 'Seam Windows',
      lastSeenTs: DateTime(2026, 11, 18).millisecondsSinceEpoch,
    ),
  ];

  @override
  Future<List<Pusher>?> getPushers() async => [
    Pusher(
      appId: 'network.seam.app',
      pushkey: 'key',
      appDisplayName: 'Seam',
      data: PusherData(url: Uri.parse('https://push.x/_matrix/push/v1/notify')),
      deviceDisplayName: 'Pixel 10',
      kind: 'http',
      lang: 'en',
    ),
  ];

  @override
  Future<DiscoveryInformation> getWellknown({
    Duration cacheLifetime = const Duration(days: 3),
    bool throwOnUpdateFailure = false,
  }) async => DiscoveryInformation(
    mHomeserver: HomeserverInformation(baseUrl: Uri.parse('https://matrix.x')),
    mIdentityServer: IdentityServerInformation(
      baseUrl: Uri.parse('https://identity.x'),
    ),
  );

  @override
  Future<GetWellknownSupportResponse> getWellknownSupport() async =>
      GetWellknownSupportResponse(
        supportPage: Uri.parse('https://x/support'),
        contacts: [Contact(role: Role.mRoleAdmin, emailAddress: 'admin@x')],
      );

  @override
  Future<List<ThirdPartyIdentifier>?> getAccount3PIDs() async => [
    ThirdPartyIdentifier(
      addedAt: 0,
      address: 'gray@example.org',
      medium: ThirdPartyIdentifierMedium.email,
      validatedAt: 0,
    ),
  ];
}

/// The push rule IDs [setUpFakeSettings] stores, by kind.
const fakePushRules = {
  'override': ['.m.rule.master', '.m.rule.invite_for_me'],
  'underride': ['.m.rule.message', '.m.rule.encrypted'],
};

/// The user [setUpFakeSettings] puts on the ignore list.
const fakeIgnoredUser = '@spam:x';

/// A fresh [FakeSettingsClient] with push rules and an ignored user.
Future<FakeSettingsClient> setUpFakeSettings(String name) async {
  final client = await setUpFakeChatList<FakeSettingsClient>(
    name,
    create: (name, database) => FakeSettingsClient(name, database: database),
  );
  client.homeserver = Uri.parse('https://x');
  client.httpClient = NotFoundHttp();
  client.accountData['m.push_rules'] = BasicEvent(
    type: 'm.push_rules',
    content: {
      'global': {
        for (final MapEntry(key: kind, value: ids) in fakePushRules.entries)
          kind: [
            for (final id in ids)
              {
                'rule_id': id,
                'default': true,
                'enabled': id != '.m.rule.master',
                'actions': ['notify'],
                'conditions': <Object?>[],
              },
          ],
      },
    },
  );
  client.accountData['m.ignored_user_list'] = BasicEvent(
    type: 'm.ignored_user_list',
    content: {
      'ignored_users': {fakeIgnoredUser: <String, Object?>{}},
    },
  );
  return client;
}

/// Counts the routes pushed on the router's navigator: the dialogs and
/// sheets the settings actions open.
class PushCounter extends NavigatorObserver {
  int pushes = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;
}

/// The settings pages on the paths the app serves them at. `/rooms`,
/// `/backup` and the add-account flow are placeholders that name
/// themselves.
GoRouter fakeSettingsRouter(
  String location, {
  NavigatorObserver? observer,
}) => GoRouter(
  initialLocation: location,
  observers: [?observer],
  routes: [
    GoRoute(path: '/', builder: (_, _) => const Text('root')),
    GoRoute(path: '/backup', builder: (_, _) => const Text('backup')),
    GoRoute(
      path: '/rooms',
      builder: (_, _) => const Text('chat list'),
      routes: [
        GoRoute(
          path: 'settings',
          builder: (_, _) => const Settings(),
          routes: [
            GoRoute(
              path: 'notifications',
              builder: (_, _) => const SettingsNotifications(),
            ),
            GoRoute(path: 'style', builder: (_, _) => const SettingsStyle()),
            GoRoute(
              path: 'devices',
              builder: (_, _) => const DevicesSettings(),
            ),
            GoRoute(
              path: 'chat',
              builder: (_, _) => const SettingsChat(),
              routes: [
                GoRoute(
                  path: 'merged_contacts',
                  builder: (_, _) => const SettingsMergedContacts(),
                ),
                GoRoute(
                  path: 'swipe_actions',
                  builder: (_, _) => const SettingsSwipeActions(),
                ),
                GoRoute(
                  path: 'matrix_features',
                  builder: (_, _) => const SettingsMatrixFeatures(),
                ),
                GoRoute(
                  path: 'emotes',
                  builder: (_, _) => const Text('emotes'),
                ),
              ],
            ),
            GoRoute(
              path: 'addaccount',
              builder: (_, _) => const Text('add account'),
            ),
            GoRoute(
              path: 'homeserver',
              builder: (_, _) => const SettingsHomeserver(),
            ),
            GoRoute(
              path: 'security',
              builder: (_, _) => const SettingsSecurity(),
              routes: [
                GoRoute(
                  path: 'password',
                  builder: (_, _) => const SettingsPassword(),
                ),
                GoRoute(
                  path: 'ignorelist',
                  builder: (_, _) => const SettingsIgnoreList(),
                ),
                GoRoute(path: '3pid', builder: (_, _) => const Settings3Pid()),
              ],
            ),
          ],
        ),
      ],
    ),
  ],
);

/// Shows [router] over [client]. [builder] wraps the pages, for a theme.
Future<void> pumpFakeSettings(
  WidgetTester tester,
  Client client,
  GoRouter router, {
  TransitionBuilder? builder,
  ThemeData? theme,
}) async {
  final prefs = await SharedPreferences.getInstance();
  await tester.pumpWidget(
    Provider<MatrixState>.value(
      value: FakeMatrix(client, prefs),
      // The style page reads the theme mode and colour from its controller.
      child: ThemeBuilder(
        store: prefs,
        builder: (context, _, _) => MaterialApp.router(
          theme: theme,
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          builder: builder,
          routerConfig: router,
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

/// Ends a test with nothing pending.
Future<void> finishFakeSettings(WidgetTester tester, Client client) async {
  await tester.pumpWidget(const SizedBox());
  tearDownFakeChatList(client);
  await tester.pump(const Duration(seconds: 11));
}
