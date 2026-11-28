// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:matrix/matrix.dart';

/// A client's sync status as the app shows it, which leaves out the failures
/// of syncs the system broke off while the app was away.
///
/// A phone cuts a background app's connections, so the sync running when
/// the app leaves the screen fails with a connection error. Shown as it is,
/// that error would greet the user on every return, before the sync the
/// client starts on resume has had a chance. So a failure while the app is
/// not resumed is held back. On resume it shows only when a sync after the
/// resume fails, or when no sync succeeds within [grace]. While the app is
/// on screen, failures show as they come.
class ShownSyncStatus extends ChangeNotifier {
  final Client client;

  ShownSyncStatus._(this.client) {
    _resumed = _isResumed(WidgetsBinding.instance.lifecycleState);
    _latest = _accept(client.onSyncStatus.value);
    _subscription = client.onSyncStatus.stream.listen((status) {
      if (_track(status)) notifyListeners();
    });
    _lifecycle = AppLifecycleListener(onStateChange: _onLifecycle);
  }

  static final Expando<ShownSyncStatus> _instances = Expando();

  static ShownSyncStatus of(Client client) =>
      _instances[client] ??= ShownSyncStatus._(client);

  /// Stops watching [client], for tests that take it down.
  @visibleForTesting
  static void disposeFor(Client client) {
    _instances[client]?.dispose();
    _instances[client] = null;
  }

  /// How long after a resume a held back failure waits for a sync to
  /// succeed before it shows.
  static const grace = Duration(seconds: 5);

  late bool _resumed;
  StreamSubscription<SyncStatusUpdate>? _subscription;
  AppLifecycleListener? _lifecycle;
  Timer? _graceTimer;

  /// The latest status that may show; a held back failure is not one.
  SyncStatusUpdate? _latest;

  /// The latest failure to show, kept until a sync succeeds. Each retry
  /// first reports that it is waiting for a response, which is no error, so
  /// going by [latest] alone would hide a failure between retries.
  SyncStatusUpdate? _failure;

  /// A failure held back while the app was away, or from before it went.
  SyncStatusUpdate? _held;

  /// The latest status that may show: waiting for the server while nothing
  /// else has been reported.
  SyncStatusUpdate get latest =>
      _latest ?? const SyncStatusUpdate(SyncStatus.waitingForResponse);

  /// The failure to show until a sync succeeds, or null.
  SyncStatusUpdate? get failure => _failure;

  static bool _isResumed(AppLifecycleState? state) =>
      state == null || state == AppLifecycleState.resumed;

  SyncStatusUpdate? _accept(SyncStatusUpdate? status) =>
      status?.status == SyncStatus.error && !_resumed ? null : status;

  /// Takes in [status]. Returns whether what shows changed.
  bool _track(SyncStatusUpdate status) {
    if (status.status == SyncStatus.error && !_resumed) {
      _held = status;
      return false;
    }
    if (status.status == SyncStatus.finished) {
      _graceTimer?.cancel();
      _held = null;
      _failure = null;
    }
    if (status.status == SyncStatus.error) _failure = status;
    _latest = status;
    return true;
  }

  void _onLifecycle(AppLifecycleState state) {
    final resumed = _isResumed(state);
    if (resumed == _resumed) return;
    _resumed = resumed;
    if (!resumed) return;
    // Back on screen: what failed before or while away waits for the syncs
    // from now on.
    _held = _failure ?? _held;
    _failure = null;
    if (_latest?.status == SyncStatus.error) _latest = null;
    _graceTimer?.cancel();
    if (_held != null) {
      _graceTimer = Timer(grace, () {
        final held = _held;
        if (held == null) return;
        _failure = held;
        _held = null;
        notifyListeners();
      });
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _graceTimer?.cancel();
    _subscription?.cancel();
    _lifecycle?.dispose();
    super.dispose();
  }
}
