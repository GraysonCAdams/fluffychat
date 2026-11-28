// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/config/setting_keys.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

/// Whether an account has agreed to the current Seam Terms of use.
///
/// Agreement is kept in two places: on the device in [AppSettings]
/// ([AppSettings.termsAcceptedVersion], [AppSettings.termsAcceptedAt]),
/// written when the box on the sign-in page is ticked or the terms dialog
/// is agreed to; and in the account's data under [accountDataType] as
/// `{version, accepted_at}`, so a second device signed in to the same
/// account does not ask again. Either one at [currentVersion] or newer
/// counts. The value is true once agreed, and the composer stays disabled
/// until it is.
class TermsAcceptance extends ValueNotifier<bool> {
  /// The effective date of the terms at https://seam.312.dev/terms. Raising
  /// it asks everyone to agree again on their next launch.
  static const String currentVersion = '2026-11-25';

  static const String accountDataType = 'dev.threeonetwo.seam.terms';

  static final Map<Client, TermsAcceptance> _byClient = {};

  static TermsAcceptance of(Client client) =>
      _byClient[client] ??= TermsAcceptance._(client);

  /// Drops the state for a client that signed out.
  static void disposeFor(Client client) {
    _byClient.remove(client)?._accountDataSub.cancel();
  }

  final Client client;
  // Cancelled in disposeFor and resetForTest.
  // ignore: cancel_subscriptions
  late final StreamSubscription<SyncUpdate> _accountDataSub;

  TermsAcceptance._(this.client) : super(false) {
    value = _accepted;
    _accountDataSub = client.onSync.stream
        .where(
          (update) =>
              update.accountData?.any((e) => e.type == accountDataType) ??
              false,
        )
        .listen((_) => _refresh());
  }

  /// Versions are dates, `YYYY-MM-DD`, so they order as strings.
  static bool covers(String? version) =>
      version != null && version.compareTo(currentVersion) >= 0;

  static bool get acceptedOnDevice =>
      covers(AppSettings.termsAcceptedVersion.value);

  bool get acceptedOnAccount => covers(_accountVersion);

  String? get _accountVersion =>
      client.accountData[accountDataType]?.content.tryGet<String>('version');

  bool get _accepted => acceptedOnDevice || acceptedOnAccount;

  /// Records agreement to [currentVersion] on this device.
  static Future<void> recordOnDevice({DateTime? now}) async {
    await AppSettings.termsAcceptedVersion.setItem(currentVersion);
    await AppSettings.termsAcceptedAt.setItem(
      (now ?? DateTime.now()).millisecondsSinceEpoch,
    );
  }

  void _refresh() {
    if (acceptedOnAccount && !acceptedOnDevice) {
      // Agreed on another device: keep that record here too.
      AppSettings.termsAcceptedVersion.setItem(_accountVersion!);
      final at = client.accountData[accountDataType]?.content.tryGet<int>(
        'accepted_at',
      );
      if (at != null) AppSettings.termsAcceptedAt.setItem(at);
    }
    value = _accepted;
  }

  /// The user agreed in the terms dialog. The account copy is written on a
  /// best-effort basis: if it fails, [settle] writes it on the next launch.
  Future<void> accept({DateTime? now}) => lastAccept = _accept(now: now);

  /// The latest [accept], account write included, so a test can wait for
  /// it to finish.
  @visibleForTesting
  Future<void>? lastAccept;

  Future<void> _accept({DateTime? now}) async {
    await recordOnDevice(now: now);
    value = true;
    try {
      await syncToAccount();
    } catch (e, s) {
      Logs().w('Could not store terms acceptance in account data', e, s);
    }
  }

  /// Copies this device's agreement to the account unless the account
  /// already has the current version.
  Future<void> syncToAccount() async {
    final userId = client.userID;
    if (userId == null || !acceptedOnDevice || acceptedOnAccount) return;
    await client.setAccountData(userId, accountDataType, {
      'version': AppSettings.termsAcceptedVersion.value,
      'accepted_at': AppSettings.termsAcceptedAt.value,
    });
  }

  /// Waits until the account's data is known (the stored copy, and the
  /// first sync for an account new to this device), copies the device's
  /// agreement to the account if it is missing there, and returns whether
  /// the account has agreed. For a signed-out client it returns at once,
  /// going by this device's record alone.
  Future<bool> settle({
    Duration firstSyncTimeout = const Duration(seconds: 30),
  }) async {
    // A signed-out client has no account data to wait for or write to.
    if (!client.isLogged()) {
      _refresh();
      return value;
    }
    await client.accountDataLoading;
    if (client.prevBatch == null) {
      try {
        await client.onSync.stream.first.timeout(firstSyncTimeout);
      } on TimeoutException {
        Logs().w('No first sync yet, deciding on terms from what is stored');
      }
    }
    _refresh();
    try {
      await syncToAccount();
    } catch (e, s) {
      Logs().w('Could not store terms acceptance in account data', e, s);
    }
    return value;
  }

  @visibleForTesting
  static void resetForTest() {
    for (final terms in _byClient.values) {
      terms._accountDataSub.cancel();
    }
    _byClient.clear();
  }
}
