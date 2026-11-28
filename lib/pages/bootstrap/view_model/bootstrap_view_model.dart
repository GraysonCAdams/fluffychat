// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:fluffychat/pages/bootstrap/widgets/recovery_key_grid.dart';
import 'package:fluffychat/utils/error_reporter.dart';
import 'package:fluffychat/utils/localized_exception_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';

import 'bootstrap_state.dart';

/// The steps of encryption setup after sign-in, in the order a new
/// account (protect to setupDone) or a new device of an existing one
/// (confirmIdentity to confirmed) meets them.
enum BootstrapStep {
  loading,
  protect,
  passphrase,
  saveKey,
  checkKey,
  setupDone,
  confirmIdentity,
  waitingForDevice,
  enterKey,
  confirmed,

  /// Already set up on this device: straight on to the chats.
  leave,
}

/// What the setup steps ask of the account's encryption, apart so tests can
/// answer for an account whose crypto identity is set up elsewhere.
class BootstrapCrypto {
  final Client client;
  const BootstrapCrypto(this.client);

  Future<CryptoIdentityState> state() => client.getCryptoIdentityState();

  /// This account's other devices that are confirmed through its master
  /// key, so they can vouch for this one.
  Future<List<DeviceKeys>> confirmedDevices() async {
    await client.updateUserDeviceKeys();
    return client.userDeviceKeys[client.userID!]?.deviceKeys.values
            .where(
              (device) =>
                  device.hasValidSignatureChain(verifiedByTheirMasterKey: true),
            )
            .toList() ??
        [];
  }

  /// Asks the account's other devices to confirm this one.
  Future<KeyVerification?> requestVerification() =>
      client.userDeviceKeys[client.userID!]!.startVerification();
}

typedef CryptoIdentityState = ({
  bool connected,
  bool crossSigningEnabled,
  bool initialized,
  bool keyBackupEnabled,
});

class BootstrapViewModel extends ValueNotifier<BootstrapViewModelState> {
  final Client client;
  final bool reset;
  final BootstrapCrypto crypto;

  final TextEditingController enterPassphraseOrRecovController =
      TextEditingController();
  final TextEditingController newPassphraseController = TextEditingController();
  final TextEditingController repeatPassphraseController =
      TextEditingController();
  final ScrollController devicesScrollController = ScrollController();

  BootstrapViewModel({
    required this.client,
    required this.reset,
    BootstrapCrypto? crypto,
  }) : crypto = crypto ?? BootstrapCrypto(client),
       super(BootstrapViewModelState()..reset = reset) {
    _init();
  }

  @override
  void dispose() {
    _cancelKeyVerification();
    checkGroupController.dispose();
    enterPassphraseOrRecovController.dispose();
    newPassphraseController.dispose();
    repeatPassphraseController.dispose();
    devicesScrollController.dispose();
    super.dispose();
  }

  void _checkCanCreatePassphrase([_]) {
    final passphrase = newPassphraseController.text;
    value.newPassphraseEqualsRepeatPassphrase =
        passphrase.isNotEmpty && passphrase == repeatPassphraseController.text;
    value.newPassphraseLongEnough = passphrase.length >= 12;
    value.newPassphraseUpperAndLowerCase =
        passphrase.contains(RegExp(r'[A-Z]')) &&
        passphrase.contains(RegExp(r'[a-z]'));
    value.newPassphraseSpecialCharacters = passphrase.contains(
      RegExp(r'[!@#$%^&*(),.?":{}|<>]'),
    );
    value.newPassphraseNumbers = passphrase.contains(RegExp(r'\d'));
    notifyListeners();
  }

  /// "Use another device": asks the account's confirmed devices to
  /// confirm this one. Nothing is sent before this is chosen.
  Future<void> useAnotherDevice() async {
    value.enteringKey = false;
    value.noSecretsreceived = false;
    value.keyVerification = await crypto.requestVerification();
    value.keyVerification?.onUpdate = _onKeyVerificationUpdate;
    notifyListeners();
  }

  Future<void> retryKeyVerification() => useAnotherDevice();

  /// Which step to show.
  BootstrapStep get step {
    final state = value;
    final identity = state.cryptoIdentityState;
    if (identity == null) return BootstrapStep.loading;
    if (!identity.initialized || state.reset) {
      if (state.recoveryKey == null) {
        return state.choosingPassphrase
            ? BootstrapStep.passphrase
            : BootstrapStep.protect;
      }
      if (state.setupFinished) return BootstrapStep.setupDone;
      return state.checkingKey ? BootstrapStep.checkKey : BootstrapStep.saveKey;
    }
    if (identity.connected) {
      return state.justConfirmed
          ? BootstrapStep.confirmed
          : BootstrapStep.leave;
    }
    if (state.enteringKey) return BootstrapStep.enterKey;
    if (state.keyVerification != null) return BootstrapStep.waitingForDevice;
    return BootstrapStep.confirmIdentity;
  }

  void choosePassphrase(bool choosing) {
    value.choosingPassphrase = choosing;
    notifyListeners();
  }

  void markKeyCopied() {
    value.recoveryKeyCopied = true;
    notifyListeners();
  }

  final TextEditingController checkGroupController = TextEditingController();

  /// Asks for one group of the key back, never the first, which people
  /// remember best.
  void startKeyCheck() {
    final groups = RecoveryKeyGrid.groupsOf(value.recoveryKey!).length;
    value.askedGroup = groups < 2 ? 0 : 1 + Random().nextInt(groups - 1);
    value.checkingKey = true;
    value.groupMismatch = false;
    checkGroupController.clear();
    notifyListeners();
  }

  void checkGroup() {
    final groups = RecoveryKeyGrid.groupsOf(value.recoveryKey!);
    final asked = groups[value.askedGroup!];
    if (checkGroupController.text.trim() == asked) {
      value.setupFinished = true;
    } else {
      value.groupMismatch = true;
    }
    notifyListeners();
  }

  void backToKey() {
    value.checkingKey = false;
    notifyListeners();
  }

  void enterRecoveryKey(bool entering) {
    _cancelKeyVerification();
    value.keyVerification = null;
    value.enteringKey = entering;
    value.unlockWithError = null;
    notifyListeners();
  }

  Future<void> useSavedKey(BuildContext context) async {
    final key = value.savedRecoveryKey;
    if (key == null) return;
    enterPassphraseOrRecovController.text = key;
    await unlock(context);
  }

  Future<void> pasteKey() async {
    final data = await Clipboard.getData(Clipboard.kTextPlain);
    final text = data?.text;
    if (text == null || text.isEmpty) return;
    enterPassphraseOrRecovController.text = text.trim();
  }

  KeyVerification? _verificationShownFor;

  /// True once per verification request, so its pages open a single time.
  bool takeVerificationPrompt() {
    final request = value.keyVerification;
    if (request == null || identical(request, _verificationShownFor)) {
      return false;
    }
    _verificationShownFor = request;
    return true;
  }

  /// Leaves the steps for the chat list without finishing them.
  void leave(BuildContext context) => context.go('/rooms');

  Future<void> _init() async {
    final state = value.cryptoIdentityState = await crypto.state();
    newPassphraseController.addListener(_checkCanCreatePassphrase);
    repeatPassphraseController.addListener(_checkCanCreatePassphrase);
    enterPassphraseOrRecovController.addListener(
      _passphraseOrRecoveryKeyEntered,
    );
    if (state.initialized) {
      if (state.connected) return notifyListeners();

      // The devices are offered on the confirm step; a request goes out
      // only when "Use another device" is chosen (useAnotherDevice).
      value.connectedDevices = await crypto.confirmedDevices();
      if (supportsSecureStorage) {
        try {
          final keyFromSecureStorage = await FlutterSecureStorage().read(
            key: _secureStorageKey,
          );
          value.savedRecoveryKey = keyFromSecureStorage;
        } catch (e, s) {
          Logs().e('Unable to read key from secure storage', e, s);
        }
      }
    }
    notifyListeners();
  }

  void _passphraseOrRecoveryKeyEntered() {
    final passphraseOrRecoveryKeyEntered =
        enterPassphraseOrRecovController.text.isNotEmpty;
    if (value.passphraseOrRecoveryKeyEntered !=
        passphraseOrRecoveryKeyEntered) {
      value.passphraseOrRecoveryKeyEntered = passphraseOrRecoveryKeyEntered;
      notifyListeners();
    }
  }

  Future<void> _onKeyVerificationUpdate() async {
    if (value.keyVerification?.state == KeyVerificationState.done) {
      value.waitingForSecrets = true;
      value.noSecretsreceived = false;
      notifyListeners();
      value.cryptoIdentityState = await crypto.state();
      var tries = 0;
      const max = 10;
      while (value.cryptoIdentityState?.connected != true) {
        Logs().d('Waiting for secrets... [$tries/$max]');
        if (tries >= max) break;
        await Future.delayed(const Duration(seconds: 1));
        value.cryptoIdentityState = await crypto.state();
        tries++;
      }

      if (value.cryptoIdentityState?.connected != true) {
        value.waitingForSecrets = false;
        value.noSecretsreceived = true;
      } else {
        value.justConfirmed = true;
      }
    }
    notifyListeners();
  }

  Future<void> setOrSkipPassphrase(
    String? passphrase,
    BuildContext context,
  ) async {
    value.isLoading = true;
    notifyListeners();
    try {
      final state = await crypto.state();
      if (state.connected) {
        Logs().i('Download the key backup...');
        await client.encryption!.keyManager.loadAllKeys();
      }

      Logs().i('Init crypto identity...');
      value.recoveryKey = await client.initCryptoIdentity(
        passphrase: passphrase,
      );

      if (state.connected) {
        Logs().i('Mark all megolm sessions as needing upload...');
        await client.database.markInboundGroupSessionsAsNeedingUpload();
      }
    } catch (e, s) {
      if (!context.mounted) return;
      ErrorReporter(
        context,
        'Unable to init crypto identity',
      ).onErrorCallback(e, s);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
      value.isLoading = false;
    }
    notifyListeners();
  }

  void _cancelKeyVerification() {
    final keyVerification = value.keyVerification;
    if (keyVerification != null &&
        keyVerification.state != KeyVerificationState.done &&
        keyVerification.state != KeyVerificationState.error) {
      keyVerification.cancel();
    }
  }

  bool get supportsSecureStorage =>
      PlatformInfos.isMobile || PlatformInfos.isDesktop;

  Future<void> unlock(BuildContext context) async {
    final key = enterPassphraseOrRecovController.text.trim();
    if (key.isEmpty) return;

    _cancelKeyVerification();

    value.unlockWithError = null;
    value.isLoading = true;
    notifyListeners();
    try {
      await client.restoreCryptoIdentity(key);
      value.isLoading = false;
      final state = value.cryptoIdentityState = await crypto.state();
      value.justConfirmed = state.connected;
      notifyListeners();
      return;
    } catch (e, s) {
      if (e is! InvalidPassphraseException) {
        const errorMessage = 'Unexpected error on unlock passphrase';
        if (context.mounted) {
          ErrorReporter(context, errorMessage).onErrorCallback(e, s);
        } else {
          Logs().wtf(errorMessage, e, s);
        }
      }
      value.isLoading = false;
      value.unlockWithError = e;
      notifyListeners();
      if (supportsSecureStorage) {
        await FlutterSecureStorage().delete(key: _secureStorageKey);
      }
      return;
    }
  }

  void goToRoomsPageAfterSuccess(BuildContext context) {
    for (final room in client.rooms) {
      final lastEvent = room.lastEvent;
      if (lastEvent == null ||
          lastEvent.messageType != MessageTypes.BadEncrypted ||
          lastEvent.content['can_request_session'] != true) {
        continue;
      }
      final sessionId = lastEvent.content.tryGet<String>('session_id');
      final senderKey = lastEvent.content.tryGet<String>('sender_key');
      if (sessionId != null && senderKey != null) {
        client.encryption?.keyManager.maybeAutoRequest(
          room,
          sessionId,
          senderKey,
        );
      }
    }
    context.go('/rooms');
  }

  void toggleObscureText() {
    value.obscureText = !value.obscureText;
    notifyListeners();
  }

  void startResetAccount() {
    value.reset = true;
    notifyListeners();
  }

  String get _secureStorageKey => 'ssss_recovery_key_${client.userID}';

  Future<void> openRecoveryKeyFile(BuildContext context) async {
    final result = await FilePicker.pickFile(
      allowedExtensions: ['txt'],
      type: FileType.custom,
    );
    final file = result?.xFile;
    if (file == null) return;
    try {
      final key = await file.readAsString();
      enterPassphraseOrRecovController.text = key;
    } catch (e, s) {
      Logs().d('Unable to read recovery key file', e, s);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(e.toLocalizedString(context))));
      }
    }
    if (context.mounted) await unlock(context);
  }

  Future<void> toggleRecoveryKeyDownloaded(
    bool? downloaded,
    BuildContext context,
  ) async {
    final path = await FilePicker.saveFile(
      fileName: 'Seam-Recovery-Key-${DateTime.now().toIso8601String()}.txt',
      bytes: Uint8List.fromList(value.recoveryKey!.codeUnits),
    );
    if (path == null) return;
    value.recoveryKeyDownloaded = downloaded == true;
    notifyListeners();
  }

  Future<void> toggleRecoveryKeyStoredInSecureStorage(bool? stored) async {
    if (stored == true) {
      await FlutterSecureStorage().write(
        key: _secureStorageKey,
        value: value.recoveryKey,
      );
    } else {
      await FlutterSecureStorage().delete(key: _secureStorageKey);
    }
    value.recoveryKeyStoredInSecureStorage = stored == true;
    notifyListeners();
  }
}
