// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/services.dart';

/// The APNs device token of this install and the APNs environment it is
/// valid in.
class ApnsRegistration {
  /// The device token as lowercase hex, the form APNs' HTTP/2 API takes.
  final String token;

  /// `sandbox` on a simulator or under a development provisioning profile,
  /// `production` otherwise. A token only works against the APNs host of its
  /// own environment.
  final String environment;

  const ApnsRegistration({required this.token, required this.environment});

  bool get isSandbox => environment == 'sandbox';
}

/// Asks iOS for the APNs device token through the channel that
/// ios/Runner/ApnsTokenChannel.swift serves.
class ApplePush {
  static const _channel = MethodChannel('dev.threeonetwo.seam/apns');

  /// Registers for remote notifications and returns the device token, or
  /// null when the system refuses, which it does without the push
  /// entitlement or without a network path to APNs.
  static Future<ApnsRegistration?> requestToken() async {
    try {
      final answer = await _channel.invokeMapMethod<String, String>(
        'requestToken',
      );
      final token = answer?['token'];
      final environment = answer?['environment'];
      if (token == null || token.isEmpty || environment == null) return null;
      return ApnsRegistration(token: token, environment: environment);
    } on PlatformException {
      return null;
    } on MissingPluginException {
      return null;
    }
  }
}
