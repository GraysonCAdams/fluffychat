// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:fluffychat/config/app_config.dart';
import 'package:fluffychat/utils/windows_data_migration.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;

void main() {
  late Directory root;
  late Directory oldDir;
  late Directory newDir;

  void write(Directory dir, String name, String content) {
    final file = File(p.join(dir.path, name));
    file.parent.createSync(recursive: true);
    file.writeAsStringSync(content);
  }

  /// Every file under [dir] with the hash of its content.
  Map<String, String> tree(Directory dir) => {
    if (dir.existsSync())
      for (final file in dir.listSync(recursive: true).whereType<File>())
        p.relative(file.path, from: dir.path): sha256
            .convert(file.readAsBytesSync())
            .toString(),
  };

  setUp(() {
    root = Directory.systemTemp.createTempSync('data_migration');
    oldDir = Directory(p.join(root.path, 'chat.fluffy', 'fluffychat'));
    newDir = Directory(p.join(root.path, 'threeonetwo', 'Seam'));
    write(oldDir, 'FluffyChat-1.sqlite', 'database');
    write(oldDir, 'FluffyChat-1.sqlite-wal', 'journal');
    write(oldDir, 'flutter_secure_storage.dat', 'secrets');
    write(oldDir, 'shared_preferences.json', '{"flutter.a":1}');
    write(oldDir, 'whisper/model.bin', 'model');
  });

  tearDown(() => root.deleteSync(recursive: true));

  test('copies everything into an empty folder and marks it', () async {
    final before = tree(oldDir);

    final result = await migrateData(oldDir: oldDir, newDir: newDir);

    expect(result, DataMigrationResult.migrated);
    final copied = tree(newDir)..remove(dataMigrationMarker);
    expect(copied, before);
    expect(File(p.join(newDir.path, dataMigrationMarker)).existsSync(), isTrue);
    expect(Directory('${newDir.path}.migrating').existsSync(), isFalse);
  });

  test('never changes the old folder', () async {
    final before = tree(oldDir);
    final listing = oldDir.listSync(recursive: true).length;

    await migrateData(oldDir: oldDir, newDir: newDir);

    expect(tree(oldDir), before);
    expect(oldDir.listSync(recursive: true), hasLength(listing));
  });

  test('a start after the first leaves the new folder alone', () async {
    await migrateData(oldDir: oldDir, newDir: newDir);
    write(newDir, 'shared_preferences.json', '{"flutter.b":2}');
    write(oldDir, 'FluffyChat-2.sqlite', 'a newer database');

    final result = await migrateData(oldDir: oldDir, newDir: newDir);

    expect(result, DataMigrationResult.alreadyMigrated);
    expect(
      File(p.join(newDir.path, 'shared_preferences.json')).readAsStringSync(),
      '{"flutter.b":2}',
    );
    expect(File(p.join(newDir.path, 'FluffyChat-2.sqlite')).existsSync(), false);
  });

  test('an account made in the new folder is never overwritten', () async {
    write(newDir, 'Seam-9.sqlite', 'own database');

    final result = await migrateData(oldDir: oldDir, newDir: newDir);

    expect(result, DataMigrationResult.newHasData);
    expect(tree(newDir), {'Seam-9.sqlite': sha256.convert('own database'.codeUnits).toString()});
  });

  test('settings a first start wrote give way to the copy', () async {
    write(newDir, 'shared_preferences.json', '{"flutter.fresh":true}');

    final result = await migrateData(oldDir: oldDir, newDir: newDir);

    expect(result, DataMigrationResult.migrated);
    expect(
      File(p.join(newDir.path, 'shared_preferences.json')).readAsStringSync(),
      '{"flutter.a":1}',
    );
  });

  test('nothing to copy from a folder without data', () async {
    for (final entity in oldDir.listSync()) {
      entity.deleteSync(recursive: true);
    }
    write(oldDir, 'notes.txt', 'not an account');

    expect(
      await migrateData(oldDir: oldDir, newDir: newDir),
      DataMigrationResult.noOldData,
    );
    expect(newDir.existsSync(), isFalse);
    expect(
      await migrateData(
        oldDir: Directory(p.join(root.path, 'missing')),
        newDir: newDir,
      ),
      DataMigrationResult.noOldData,
    );
  });

  test('a copy that fails leaves the new folder empty and the old intact', () async {
    final before = tree(oldDir);
    var copies = 0;

    final result = await migrateData(
      oldDir: oldDir,
      newDir: newDir,
      copier: (from, to) async {
        if (++copies == 3) throw const FileSystemException('disk full');
        await from.copy(to);
      },
    );

    expect(result, DataMigrationResult.failed);
    expect(tree(newDir), isEmpty);
    expect(Directory('${newDir.path}.migrating').existsSync(), isFalse);
    expect(tree(oldDir), before);
  });

  test('old data that changes while copying is not accepted', () async {
    var copies = 0;

    final result = await migrateData(
      oldDir: oldDir,
      newDir: newDir,
      copier: (from, to) async {
        await from.copy(to);
        if (++copies == 1) {
          // The app still running on the old folder writes to it.
          write(oldDir, 'FluffyChat-1.sqlite-wal', 'more journal');
        }
      },
    );

    expect(result, DataMigrationResult.failed);
    expect(tree(newDir), isEmpty);
  });

  test('a corrupt copy is not accepted', () async {
    final result = await migrateData(
      oldDir: oldDir,
      newDir: newDir,
      copier: (from, to) async {
        await from.copy(to);
        if (to.endsWith('flutter_secure_storage.dat')) {
          File(to).writeAsStringSync('garbage');
        }
      },
    );

    expect(result, DataMigrationResult.failed);
    expect(tree(newDir), isEmpty);
  });

  test('is retried by the next start after a failure', () async {
    await migrateData(
      oldDir: oldDir,
      newDir: newDir,
      copier: (_, _) async => throw const FileSystemException('locked'),
    );

    expect(
      await migrateData(oldDir: oldDir, newDir: newDir),
      DataMigrationResult.migrated,
    );
  });

  test('the old folder is where FluffyChat keeps it', () {
    expect(
      oldWindowsDataDirectory({'APPDATA': r'C:\Users\a\AppData\Roaming'})!.path,
      p.join(r'C:\Users\a\AppData\Roaming', 'chat.fluffy', 'fluffychat'),
    );
    expect(oldWindowsDataDirectory({}), isNull);
  });

  group('the Windows runner', () {
    test('names the data folder after Seam', () {
      final rc = File('windows/runner/Runner.rc').readAsStringSync();
      expect(rc, contains('VALUE "CompanyName", "threeonetwo"'));
      expect(rc, contains('VALUE "ProductName", "Seam"'));
    });

    test('holds a single-instance mutex of its own', () {
      final main = File('windows/runner/main.cpp').readAsStringSync();
      expect(main, contains('L"Local\\\\${AppConfig.seamApplicationId}"'));
      expect(main, isNot(contains('im.fluffychat.app')));
    });

    test('activates toasts through its own class id', () {
      expect(
        AppConfig.windowsNotificationGuid,
        isNot('4894dfda-c70a-4ebc-b139-acae55f3988d'),
      );
    });

    test('is installed apart from FluffyChat', () {
      final iss = File('windows/installer.iss').readAsStringSync();
      expect(iss, isNot(contains('4914EA58-B990-4CA5-BFAA-8EAC9A24F6A5')));
      expect(iss, contains('AppName=Seam'));
    });
  });
}
