// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:matrix/matrix.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// A client logged in to the SDK's fake homeserver, with the rooms and
/// events of its canned sync.
///
/// It runs without end-to-end encryption, so unlike `prepareTestClient` it
/// does not need the vodozemac library built for the test host. Message
/// search never touches encryption: it only sees events after the SDK has
/// decrypted them.
///
/// [databasePath] puts the SDK database in a file. The default keeps it in
/// memory.
Future<Client> createSearchTestClient({String? databasePath}) async {
  final client = Client(
    'Message Search Test',
    httpClient: FakeMatrixApi(),
    database: await MatrixSdkDatabase.init(
      'Message Search Test',
      database: await databaseFactoryFfi.openDatabase(
        databasePath ?? inMemoryDatabasePath,
        options: OpenDatabaseOptions(singleInstance: false),
      ),
      sqfliteFactory: databaseFactoryFfi,
    ),
  );
  await client.init(
    newHomeserver: Uri.parse('https://fakeserver.notexisting'),
    newDeviceID: 'ABCD1234',
    newDeviceName: 'Message Search Test',
    newToken: '1234',
    newUserID: '@test:fakeServer.notExisting',
  );
  client.backgroundSync = false;
  return client;
}
