// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:collection/collection.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/sign_in_flows/calc_redirect_url.dart';
import 'package:flutter_web_auth_2/flutter_web_auth_2.dart';
import 'package:matrix/matrix.dart';

/// One of the identity providers an SSO server offers (MSC2858), such as
/// GitHub or a company directory.
class SsoIdentityProvider {
  final String id;
  final String name;

  const SsoIdentityProvider({required this.id, required this.name});

  /// The providers listed in the server's `m.login.sso` flow; empty when
  /// it lists none and picks one itself.
  static List<SsoIdentityProvider> of(List<LoginFlow> loginFlows) =>
      (loginFlows
                  .firstWhereOrNull((flow) => flow.type == 'm.login.sso')
                  ?.additionalProperties['identity_providers']
              as List?)
          ?.map(
            (json) => SsoIdentityProvider(
              id: json['id'] as String,
              name: json['name'] as String,
            ),
          )
          .toList() ??
      const [];
}

/// Signs [client] in through the server's SSO page in the browser, with
/// [provider] when the server offers a choice.
Future<void> ssoLoginFlow(
  Client client,
  bool signUp, {
  SsoIdentityProvider? provider,
}) async {
  final (redirectUrl, urlScheme) = calcRedirectUrl(withAuthHtmlPath: true);

  Logs().i('Starting legacy SSO Flow with redirect URL', redirectUrl);

  final url = client.homeserver!.replace(
    path:
        '/_matrix/client/v3/login/sso/redirect${provider == null ? '' : '/${provider.id}'}',
    queryParameters: {
      'redirectUrl': redirectUrl.toString(),
      'action': signUp ? 'register' : 'login',
    },
  );

  final result = await FlutterWebAuth2.authenticate(
    url: url.toString(),
    callbackUrlScheme: urlScheme,
    options: FlutterWebAuth2Options(useWebview: PlatformInfos.isMobile),
  );
  final token = Uri.parse(result).queryParameters['loginToken'];
  if (token?.isEmpty ?? false) return;

  await client.login(
    LoginType.mLoginToken,
    token: token,
    initialDeviceDisplayName: PlatformInfos.appDisplayName,
  );
}
