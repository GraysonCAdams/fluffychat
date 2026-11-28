// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

class BootstrapViewModelState {
  String? recoveryKey;
  bool isLoading = false;
  Object? unlockWithError;
  ({
    bool connected,
    bool crossSigningEnabled,
    bool initialized,
    bool keyBackupEnabled,
  })?
  cryptoIdentityState;
  bool reset = false;
  KeyVerification? keyVerification;
  List<DeviceKeys>? connectedDevices;
  bool obscureText = true;
  bool waitingForSecrets = false;
  bool noSecretsreceived = false;

  bool newPassphraseEqualsRepeatPassphrase = false;
  bool newPassphraseLongEnough = false;
  bool newPassphraseUpperAndLowerCase = false;
  bool newPassphraseSpecialCharacters = false;
  bool newPassphraseNumbers = false;
  bool passphraseOrRecoveryKeyEntered = false;
  bool recoveryKeyDownloaded = false;
  bool recoveryKeyStoredInSecureStorage = false;

  /// On the confirm-it's-you step: typing the recovery key rather than
  /// using another device.
  bool enteringKey = false;

  /// A recovery key this device kept in its secure storage, offered on the
  /// recovery key step.
  String? savedRecoveryKey;

  /// Set up with a passphrase rather than the key alone.
  bool choosingPassphrase = false;
  bool recoveryKeyCopied = false;

  /// After "I've saved it": the step that asks [askedGroup] of the key.
  bool checkingKey = false;
  int? askedGroup;
  bool groupMismatch = false;
  bool setupFinished = false;

  /// This device became confirmed in this run of the steps (by another
  /// device or the recovery key), so the steps end on a confirmation
  /// rather than leaving at once.
  bool justConfirmed = false;

  /// Whether the new recovery key went anywhere: copied, shared, saved to
  /// a file or into secure storage.
  bool get recoveryKeyKept =>
      recoveryKeyCopied ||
      recoveryKeyDownloaded ||
      recoveryKeyStoredInSecureStorage;
}
