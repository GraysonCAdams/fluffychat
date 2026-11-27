// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';

/// What [migrateData] did.
enum DataMigrationResult {
  /// The data was copied into the new folder.
  migrated,

  /// An earlier start already copied it.
  alreadyMigrated,

  /// The old folder holds no data to copy.
  noOldData,

  /// The new folder already has data of its own, which is never overwritten.
  newHasData,

  /// Something went wrong; the new folder is as it was and the old one
  /// untouched. The next start tries again.
  failed,
}

/// Written into the new folder once the copy is complete.
const dataMigrationMarker = '.migrated_from_fluffychat';

/// The encrypted store of secrets (the database key, the app lock PIN). It
/// is protected for the Windows user, not the app, so a copy opens anywhere
/// that user runs the app.
const _secureStorageFile = 'flutter_secure_storage.dat';

/// Copies one file; a stand-in lets tests make the copy fail.
typedef FileCopier = Future<void> Function(File from, String to);

Future<void> _copy(File from, String to) => from.copy(to);

/// Whether [directory] holds a client database or the secure store, which
/// is what makes an account usable.
bool _hasData(Directory directory) {
  if (!directory.existsSync()) return false;
  return directory.listSync().whereType<File>().any((file) {
    final name = path.basename(file.path);
    return name.endsWith('.sqlite') || name == _secureStorageFile;
  });
}

/// Size and modification time of every file under [directory], by relative
/// path.
Map<String, (int, DateTime)> _snapshot(Directory directory) => {
  for (final file
      in directory.listSync(recursive: true, followLinks: false)
          .whereType<File>())
    path.relative(file.path, from: directory.path): (
      file.lengthSync(),
      file.lastModifiedSync(),
    ),
};

Future<String> _hash(File file) async =>
    (await sha256.bind(file.openRead()).first).toString();

/// Copies the data of [oldDir] into [newDir], once, for an app that moves to
/// a folder of its own. The old folder is only read.
///
/// The files go to a staging folder next to [newDir] first. Their hashes
/// are compared with the originals, and the originals must not have changed
/// since the copy began (an app still running on them would leave a database
/// and its journal out of step). Only then do they replace what [newDir]
/// holds, and the marker goes in last. Any failure removes the staging
/// folder and leaves [newDir] as it was.
///
/// Nothing is copied when [newDir] already holds a database or secure
/// store, so a second start, or an account made in the new folder, is never
/// overwritten.
Future<DataMigrationResult> migrateData({
  required Directory oldDir,
  required Directory newDir,
  FileCopier copier = _copy,
}) async {
  if (path.equals(oldDir.path, newDir.path)) {
    return DataMigrationResult.noOldData;
  }
  if (File(path.join(newDir.path, dataMigrationMarker)).existsSync()) {
    return DataMigrationResult.alreadyMigrated;
  }
  if (!_hasData(oldDir)) return DataMigrationResult.noOldData;
  if (_hasData(newDir)) return DataMigrationResult.newHasData;

  final staging = Directory('${newDir.path}.migrating');
  try {
    if (staging.existsSync()) staging.deleteSync(recursive: true);
    final before = _snapshot(oldDir);
    for (final name in before.keys) {
      final target = path.join(staging.path, name);
      Directory(path.dirname(target)).createSync(recursive: true);
      await copier(File(path.join(oldDir.path, name)), target);
    }

    final after = _snapshot(oldDir);
    if (after.length != before.length ||
        after.entries.any((e) => before[e.key] != e.value)) {
      throw const FileSystemException('The old data changed while copying');
    }
    for (final name in before.keys) {
      final copy = File(path.join(staging.path, name));
      if (!copy.existsSync() ||
          await _hash(copy) != await _hash(File(path.join(oldDir.path, name)))) {
        throw FileSystemException('The copy of $name differs', copy.path);
      }
    }
    File(path.join(staging.path, dataMigrationMarker)).writeAsStringSync(
      jsonEncode({
        'from': oldDir.path,
        'at': DateTime.now().toIso8601String(),
        'files': before.length,
      }),
    );

    // Whatever the new folder holds without data (settings a first start
    // wrote) gives way to the copy. The marker is renamed last.
    newDir.createSync(recursive: true);
    final entries = staging.listSync()
      ..sort((a, b) {
        final aMarker = path.basename(a.path) == dataMigrationMarker ? 1 : 0;
        final bMarker = path.basename(b.path) == dataMigrationMarker ? 1 : 0;
        return aMarker - bMarker;
      });
    for (final entry in entries) {
      final target = path.join(newDir.path, path.basename(entry.path));
      final existing = FileSystemEntity.typeSync(target);
      if (existing == FileSystemEntityType.directory) {
        Directory(target).deleteSync(recursive: true);
      } else if (existing != FileSystemEntityType.notFound) {
        File(target).deleteSync();
      }
      entry.renameSync(target);
    }
    staging.deleteSync(recursive: true);
    return DataMigrationResult.migrated;
  } catch (e, s) {
    Logs().e('Unable to copy the data of FluffyChat', e, s);
    try {
      if (staging.existsSync()) staging.deleteSync(recursive: true);
    } catch (_) {}
    return DataMigrationResult.failed;
  }
}

/// The folder FluffyChat and earlier Seam builds shared:
/// `%APPDATA%\chat.fluffy\fluffychat`, named by the company and product of
/// the executable's version info.
Directory? oldWindowsDataDirectory([Map<String, String>? environment]) {
  final appData = (environment ?? Platform.environment)['APPDATA'];
  if (appData == null) return null;
  return Directory(path.join(appData, 'chat.fluffy', 'fluffychat'));
}

/// Copies the shared folder into Seam's own (the application support
/// directory), before anything opens the database or the settings. Never
/// throws.
Future<DataMigrationResult?> migrateFluffyChatWindowsData() async {
  try {
    final oldDir = oldWindowsDataDirectory();
    if (oldDir == null) return null;
    final newDir = await getApplicationSupportDirectory();
    final result = await migrateData(oldDir: oldDir, newDir: newDir);
    Logs().i('Data of FluffyChat: ${result.name}', newDir.path);
    return result;
  } catch (e, s) {
    Logs().e('Unable to look for the data of FluffyChat', e, s);
    return null;
  }
}
