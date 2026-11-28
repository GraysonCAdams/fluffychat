// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/pages/login/login_error.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:matrix/matrix.dart';

void main() {
  test('a rejected password', () {
    final error = LoginError.of(
      MatrixException.fromJson({
        'errcode': 'M_FORBIDDEN',
        'error': 'Invalid username or password',
      }),
    );
    expect(error.kind, LoginErrorKind.wrongCredentials);
  });

  test('rate limited, with the wait from retry_after_ms', () {
    final error = LoginError.of(
      MatrixException.fromJson({
        'errcode': 'M_LIMIT_EXCEEDED',
        'retry_after_ms': 27400,
      }),
    );
    expect(error.kind, LoginErrorKind.rateLimited);
    expect(error.retryAfter, const Duration(milliseconds: 27400));
  });

  test('rate limited, with the wait from the Retry-After header', () {
    final error = LoginError.of(
      MatrixException(
        http.Response(
          '{"errcode":"M_LIMIT_EXCEEDED"}',
          429,
          headers: {'retry-after': '65'},
        ),
      ),
    );
    expect(error.retryAfter, const Duration(seconds: 65));
  });

  test('rate limited without a wait', () {
    final error = LoginError.of(
      MatrixException.fromJson({'errcode': 'M_LIMIT_EXCEEDED'}),
    );
    expect(error.kind, LoginErrorKind.rateLimited);
    expect(error.retryAfter, isNull);
  });

  test('no answer from the server', () {
    expect(
      LoginError.of(http.ClientException('Connection refused')).kind,
      LoginErrorKind.unreachable,
    );
    expect(
      LoginError.of(TimeoutException('slow')).kind,
      LoginErrorKind.unreachable,
    );
  });

  test('anything else shows the server message', () {
    final error = LoginError.of(
      MatrixException.fromJson({
        'errcode': 'M_USER_DEACTIVATED',
        'error': 'This account has been deactivated',
      }),
    );
    expect(error.kind, LoginErrorKind.other);
    expect(error.message, 'This account has been deactivated');
  });

  test('countdown', () {
    expect(formatCountdown(const Duration(milliseconds: 27400)), '0:28');
    expect(formatCountdown(const Duration(seconds: 65)), '1:05');
    expect(formatCountdown(Duration.zero), '0:00');
  });
}
