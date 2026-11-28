// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/pages/bootstrap/view_model/bootstrap_view_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/encryption.dart';
import 'package:matrix/matrix.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/message_search/search_test_client.dart';

/// A new account: no crypto identity yet.
class _NewAccount extends BootstrapCrypto {
  _NewAccount(super.client);

  @override
  Future<CryptoIdentityState> state() async => (
    connected: false,
    crossSigningEnabled: false,
    initialized: false,
    keyBackupEnabled: false,
  );

  @override
  Future<List<DeviceKeys>> confirmedDevices() async => [];
}

/// An account whose crypto identity exists but is not on this device yet,
/// with one other confirmed device.
class _ExistingIdentity extends BootstrapCrypto {
  _ExistingIdentity(super.client);

  int requests = 0;

  @override
  Future<CryptoIdentityState> state() async => (
    connected: false,
    crossSigningEnabled: true,
    initialized: true,
    keyBackupEnabled: true,
  );

  @override
  Future<List<DeviceKeys>> confirmedDevices() async => [
    DeviceKeys.fromJson({
      'user_id': client.userID,
      'device_id': 'PIXEL10',
      'algorithms': ['m.megolm.v1.aes-sha2'],
      'keys': <String, Object?>{},
      'signatures': <String, Object?>{},
      'unsigned': {'device_display_name': 'Pixel 10'},
    }, client),
  ];

  @override
  Future<KeyVerification?> requestVerification() async {
    requests++;
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
  });
  setUp(() async => client = await createSearchTestClient());
  tearDown(() => client.dispose(closeDatabase: true));

  test('opening the confirm step sends no verification request', () async {
    final crypto = _ExistingIdentity(client);
    final viewModel = BootstrapViewModel(
      client: client,
      reset: false,
      crypto: crypto,
    );
    while (viewModel.value.connectedDevices == null) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(viewModel.value.connectedDevices, hasLength(1));
    expect(crypto.requests, 0);

    await viewModel.useAnotherDevice();
    expect(crypto.requests, 1);
    viewModel.dispose();
  });

  Future<BootstrapViewModel> settled(BootstrapCrypto crypto) async {
    final viewModel = BootstrapViewModel(
      client: client,
      reset: false,
      crypto: crypto,
    );
    while (viewModel.step == BootstrapStep.loading ||
        (crypto is _ExistingIdentity &&
            viewModel.value.connectedDevices == null)) {
      await Future<void>.delayed(const Duration(milliseconds: 10));
    }
    return viewModel;
  }

  test(
    'a new key must go somewhere, then one group of it comes back',
    () async {
      final viewModel = await settled(_NewAccount(client));
      expect(viewModel.step, BootstrapStep.protect);
      viewModel.choosePassphrase(true);
      expect(viewModel.step, BootstrapStep.passphrase);
      viewModel.choosePassphrase(false);

      const key = 'EsTj 3yST y93F SLpB jJsz eAXc 2XzA ygD3 w69H fGaN TKBj jXEd';
      viewModel.value.recoveryKey = key;
      expect(viewModel.step, BootstrapStep.saveKey);
      expect(viewModel.value.recoveryKeyKept, isFalse);
      viewModel.markKeyCopied();
      expect(viewModel.value.recoveryKeyKept, isTrue);

      viewModel.startKeyCheck();
      expect(viewModel.step, BootstrapStep.checkKey);
      final asked = viewModel.value.askedGroup!;
      expect(asked, inInclusiveRange(1, 11), reason: 'never the first group');

      viewModel.checkGroupController.text = 'nope';
      viewModel.checkGroup();
      expect(viewModel.value.groupMismatch, isTrue);
      expect(viewModel.step, BootstrapStep.checkKey);

      viewModel.checkGroupController.text = key.split(' ')[asked];
      viewModel.checkGroup();
      expect(viewModel.step, BootstrapStep.setupDone);
      viewModel.dispose();
    },
  );

  test('an existing identity offers both ways to confirm', () async {
    final viewModel = await settled(_ExistingIdentity(client));
    expect(viewModel.step, BootstrapStep.confirmIdentity);
    viewModel.enterRecoveryKey(true);
    expect(viewModel.step, BootstrapStep.enterKey);
    viewModel.enterRecoveryKey(false);
    expect(viewModel.step, BootstrapStep.confirmIdentity);
    viewModel.dispose();
  });
}
