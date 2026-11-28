// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

enum LoginErrorKind {
  /// The server rejected the username or password.
  wrongCredentials,

  /// Too many attempts; [LoginError.retryAfter] says how long to wait,
  /// when the server says.
  rateLimited,

  /// The server did not answer.
  unreachable,

  /// Anything else, shown as the server's own [LoginError.message].
  other,
}

/// What went wrong when signing in with a password, sorted into the cases
/// the password page shows differently.
class LoginError {
  final LoginErrorKind kind;
  final Duration? retryAfter;
  final String? message;

  const LoginError(this.kind, {this.retryAfter, this.message});

  static LoginError of(Object error) {
    if (error is MatrixException) {
      switch (error.error) {
        case MatrixError.M_FORBIDDEN:
          return const LoginError(LoginErrorKind.wrongCredentials);
        case MatrixError.M_LIMIT_EXCEEDED:
          return LoginError(
            LoginErrorKind.rateLimited,
            retryAfter: _retryAfter(error),
          );
        default:
          return LoginError(LoginErrorKind.other, message: error.errorMessage);
      }
    }
    if (error is http.ClientException || error is TimeoutException) {
      return const LoginError(LoginErrorKind.unreachable);
    }
    return LoginError(LoginErrorKind.other, message: error.toString());
  }

  /// The Retry-After header (seconds), which newer servers send, or the
  /// older retry_after_ms field.
  static Duration? _retryAfter(MatrixException error) {
    final header = int.tryParse(error.response?.headers['retry-after'] ?? '');
    if (header != null) return Duration(seconds: header);
    final ms = error.retryAfterMs;
    return ms == null ? null : Duration(milliseconds: ms);
  }
}

/// A wait as the sign-in button counts it down: `0:28`, `1:05`.
String formatCountdown(Duration duration) {
  final seconds = (duration.inMilliseconds / 1000).ceil();
  return '${seconds ~/ 60}:${(seconds % 60).toString().padLeft(2, '0')}';
}
