// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';

/// How a homeserver signs people in, as the server step and the flows
/// after it see it.
enum SignInMethod {
  /// Matrix native OIDC (MSC2964, the Matrix Authentication Service): the
  /// server's own page in the browser.
  oidc,

  /// Single sign-on (`m.login.sso`): also the server's page in the browser,
  /// possibly with a choice of identity providers.
  sso,

  /// Username and password in the app.
  password;

  /// Whether signing in leaves the app for the browser.
  bool get usesBrowser => this != password;

  /// [loginFlows] and [authMetadata] as `Client.checkHomeserver` returns
  /// them. OIDC wins when the server offers it and [preferOidc] is set
  /// (AppSettings.enableMatrixNativeOIDC), then SSO, then password.
  static SignInMethod of(
    List<LoginFlow> loginFlows,
    GetAuthMetadataResponse? authMetadata, {
    required bool preferOidc,
  }) {
    if (authMetadata != null && preferOidc) return oidc;
    if (loginFlows.any((flow) => flow.type == 'm.login.sso')) return sso;
    return password;
  }
}
