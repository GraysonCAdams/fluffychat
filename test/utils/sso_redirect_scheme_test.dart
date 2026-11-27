// SPDX-FileCopyrightText: 2026 Grayson Adams
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter_test/flutter_test.dart';

/// OIDC (MSC2966, RFC 8252 section 7.1) requires a native client's
/// private-use redirect scheme to start with its client_uri host in
/// reverse-DNS order, and matrix.org refuses the registration otherwise
/// (invalid_redirect_uri).
void main() {
  final host = Uri.parse(AppSettings.website.defaultValue).host;
  final reversed = host.split('.').reversed.join('.');

  bool matchesClientUri(String scheme) =>
      scheme == reversed || scheme.startsWith('$reversed.');

  test('the client_uri is Seam\'s site', () {
    expect(host, 'seam.312.dev');
    expect(reversed, 'dev.312.seam');
  });

  test('every build mode\'s SSO scheme starts with the reversed host', () {
    for (final scheme in [
      AppConfig.releaseSsoUrlScheme,
      AppConfig.developmentSsoUrlScheme,
      AppConfig.appSsoUrlScheme,
    ]) {
      expect(matchesClientUri(scheme), isTrue, reason: scheme);
    }
    // The release app and a debug build on one phone must not both claim
    // the redirect.
    expect(
      AppConfig.releaseSsoUrlScheme,
      isNot(AppConfig.developmentSsoUrlScheme),
    );
  });

  test('the check fails for a scheme off the client_uri host', () {
    expect(matchesClientUri('dev.threeonetwo.seam.auth'), isFalse);
    expect(matchesClientUri('im.fluffychat.auth'), isFalse);
    expect(matchesClientUri('dev.312.seamless.auth'), isFalse);
  });

  test('the Android manifest placeholders match AppConfig per build type', () {
    final gradle = File('android/app/build.gradle.kts').readAsStringSync();
    String ssoSchemeIn(String block) {
      final start = gradle.indexOf(block);
      expect(start, isNot(-1), reason: block);
      final match = RegExp(
        r'manifestPlaceholders\["appSsoUrlScheme"\] = "([^"]+)"',
      ).firstMatch(gradle.substring(start));
      return match!.group(1)!;
    }

    // defaultConfig is what release builds use; debug and profile override
    // it.
    expect(ssoSchemeIn('defaultConfig {'), AppConfig.releaseSsoUrlScheme);
    expect(ssoSchemeIn('debug {'), AppConfig.developmentSsoUrlScheme);
    expect(
      ssoSchemeIn('getByName("profile") {'),
      AppConfig.developmentSsoUrlScheme,
    );
  });
}
