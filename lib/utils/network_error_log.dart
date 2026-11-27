// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' show ClientException;
import 'package:matrix/matrix.dart';

/// One line about a network error: the host it was talking to, the
/// exception's type and its message. A [SyncConnectionException], which
/// says nothing of its own, is described by the error it wraps.
String networkErrorSummary(Object error, {Uri? endpoint}) {
  final cause = error is SyncConnectionException
      ? error.originalException
      : error;
  final host =
      endpoint?.host ??
      switch (cause) {
        ClientException(:final uri?) => uri.host,
        SocketException(:final address?) => address.host,
        _ => null,
      } ??
      'unknown host';
  final message = switch (cause) {
    SocketException(:final message, :final osError) =>
      osError == null ? message : '$message (${osError.message})',
    ClientException(:final message) => message,
    TimeoutException(:final message, :final duration) =>
      message ?? 'timed out after $duration',
    _ => cause.toString(),
  };
  return 'host=$host ${cause.runtimeType}: $message';
}

/// The last error [logNetworkErrorShown] wrote, so a dialog or snackbar
/// that builds the same error's text again does not log it again.
Object? _lastShown;

/// Logs that [error], a network error, is being shown to the user.
void logNetworkErrorShown(Object error) {
  if (identical(error, _lastShown)) return;
  _lastShown = error;
  Logs().w('Shown as a connection error: ${networkErrorSummary(error)}');
}

/// Logs each failed sync of a client in one line: its server, the error,
/// how many syncs have failed in a row and how long since the last one
/// that worked; and the sync that works again after failures.
class SyncErrorLog {
  final Client client;
  int _failures = 0;
  DateTime? _lastSuccess;
  StreamSubscription<SyncStatusUpdate>? _subscription;

  SyncErrorLog._(this.client) {
    _subscription = client.onSyncStatus.stream.listen(onStatus);
  }

  static SyncErrorLog attach(Client client) => SyncErrorLog._(client);

  @visibleForTesting
  void onStatus(SyncStatusUpdate update) {
    switch (update.status) {
      case SyncStatus.error:
        _failures++;
        final error = update.error?.exception;
        final since = _lastSuccess == null
            ? 'no sync has worked yet'
            : 'last worked ${DateTime.now().difference(_lastSuccess!).inSeconds}s ago';
        Logs().w(
          'Sync failed, $_failures in a row, $since; the SDK retries: '
          '${error == null ? 'no error given' : networkErrorSummary(error, endpoint: client.homeserver)}',
        );
      case SyncStatus.finished:
        if (_failures > 0) {
          Logs().i('Sync works again after $_failures failed');
        }
        _failures = 0;
        _lastSuccess = DateTime.now();
      default:
        break;
    }
  }

  void dispose() => _subscription?.cancel();
}
