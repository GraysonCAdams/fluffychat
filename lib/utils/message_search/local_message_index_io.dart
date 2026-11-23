// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';
import 'package:path/path.dart' as p;
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'index_operation.dart';
import 'message_search_hit.dart';
import 'search_query.dart';

/// A full-text index over the message text this device has seen, kept in its
/// own SQLite file next to the SDK database.
///
/// The SDK database stores each event as one JSON string, so finding a word
/// there means reading every stored event. This index answers the same
/// question from an FTS5 table instead, and it holds the decrypted text of
/// encrypted rooms, which the homeserver cannot search.
///
/// Like the SDK database, it is only reached through sqflite's background
/// isolate. Nothing here reads or tokenizes message text on the UI isolate.
class LocalMessageIndex {
  LocalMessageIndex._(this._db, this._factory, this.path);

  final Database _db;
  final DatabaseFactory _factory;
  final String path;

  static const _schemaVersion = 1;
  static const _walSizeLimit = 1024 * 1024;

  /// Opens the index at [path], creating it when missing.
  ///
  /// [cipher] is the SQLCipher key of the SDK database. The index contains
  /// message text in the clear and is encrypted with the same key, so it is
  /// never easier to read than the database it was built from.
  ///
  /// A file that cannot be opened, for example because the SDK database got
  /// a new key, is replaced by an empty index. Everything in it can be read
  /// from the SDK database again.
  ///
  /// Returns null when the bundled SQLite cannot provide the index.
  static Future<LocalMessageIndex?> open(
    String path, {
    String? cipher,
    DatabaseFactory? factory,
  }) async {
    factory ??= databaseFactoryFfi;
    try {
      return await _open(path, cipher, factory);
    } catch (e, s) {
      Logs().w('Unable to open the message search index, replacing it', e, s);
    }
    try {
      await factory.deleteDatabase(path);
      return await _open(path, cipher, factory);
    } catch (e, s) {
      Logs().w('Unable to create the message search index', e, s);
      return null;
    }
  }

  static Future<LocalMessageIndex> _open(
    String path,
    String? cipher,
    DatabaseFactory factory,
  ) async {
    final helper = cipher == null
        ? null
        : SQfLiteEncryptionHelper(factory: factory, path: path, cipher: cipher);
    final db = await factory.openDatabase(
      path,
      options: OpenDatabaseOptions(
        version: _schemaVersion,
        onConfigure: (db) async {
          await helper?.applyPragmaKey(db);
          // Has to be chosen before the first table exists. It lets
          // [compact] hand unused pages back to the file system without
          // rewriting the whole file.
          await db.rawQuery('PRAGMA auto_vacuum = INCREMENTAL');
          // Message text arrives in many small writes. Write-ahead logging
          // spares each of them a full journal sync, and losing the last
          // few after a crash is harmless because they are indexed again
          // from the SDK database.
          await db.rawQuery('PRAGMA journal_mode = WAL');
          await db.rawQuery('PRAGMA synchronous = NORMAL');
          // The log file keeps the size of its busiest moment, which after
          // the first indexing run is several megabytes of nothing. This
          // cuts it back whenever its content has been moved to the index.
          await db.rawQuery('PRAGMA journal_size_limit = $_walSizeLimit');
        },
        onCreate: (db, _) => _createSchema(db),
      ),
    );
    return LocalMessageIndex._(db, factory, path);
  }

  /// Where the index of [client] is stored: beside its SDK database, so both
  /// share one lifetime and one set of platform backup rules. Null when the
  /// client has no SQLite database.
  static String? pathFor(Client client) {
    final database = client.database;
    if (database is! MatrixSdkDatabase) return null;
    final sdkPath = database.database?.path;
    if (sdkPath == null || sdkPath == inMemoryDatabasePath) return null;
    return p.setExtension(sdkPath, '.search.sqlite');
  }

  static Future<void> _createSchema(Database db) async {
    final batch = db.batch();
    _addSchema(batch);
    await batch.commit(noResult: true);
  }

  static void _addSchema(Batch batch) {
    // Room and user IDs are long and repeat in every message of a chat. Each
    // is stored once here and referred to by number, which made the message
    // table a third smaller on the benchmark data.
    batch.execute(
      'CREATE TABLE names ('
      'id INTEGER PRIMARY KEY, '
      'name TEXT NOT NULL UNIQUE)',
    );
    // `id` orders the rows by time, see [baseId]. `ts` is the timestamp
    // shown to the user. `edit_ts` is the timestamp of the edit `body` comes
    // from, 0 for the original text.
    batch.execute(
      'CREATE TABLE messages ('
      'id INTEGER PRIMARY KEY, '
      'event_id TEXT NOT NULL UNIQUE, '
      'room INTEGER NOT NULL, '
      'sender INTEGER NOT NULL, '
      'ts INTEGER NOT NULL, '
      'edit_ts INTEGER NOT NULL DEFAULT 0, '
      'body TEXT NOT NULL)',
    );
    // The FTS table stores no text of its own (content=), only the word
    // index. detail=none and columnsize=0 leave out word positions and
    // lengths, which only phrase queries and relevance ranking need. The
    // prefix indexes keep "starts with" lookups for two and three typed
    // letters from walking a large part of the vocabulary.
    batch.execute(
      'CREATE VIRTUAL TABLE messages_fts USING fts5('
      "body, content='messages', content_rowid='id', "
      "tokenize='unicode61 remove_diacritics 2', "
      "prefix='2 3', detail=none, columnsize=0)",
    );
    batch.execute(
      'CREATE TRIGGER messages_ai AFTER INSERT ON messages BEGIN '
      'INSERT INTO messages_fts(rowid, body) VALUES (new.id, new.body); END',
    );
    batch.execute(
      'CREATE TRIGGER messages_ad AFTER DELETE ON messages BEGIN '
      'INSERT INTO messages_fts(messages_fts, rowid, body) '
      "VALUES ('delete', old.id, old.body); END",
    );
    batch.execute(
      'CREATE TRIGGER messages_au AFTER UPDATE OF body ON messages BEGIN '
      'INSERT INTO messages_fts(messages_fts, rowid, body) '
      "VALUES ('delete', old.id, old.body); "
      'INSERT INTO messages_fts(rowid, body) VALUES (new.id, new.body); END',
    );
    batch.execute('CREATE TABLE meta (k TEXT PRIMARY KEY NOT NULL, v TEXT)');
  }

  static const _slotBits = 4;
  static const _maxTimestamp = (1 << 42) - 1;

  /// The row ID a message gets when no other row has taken it: its timestamp
  /// in the high bits, a hash of its event ID in the low bits.
  ///
  /// FTS5 can walk its matches in row ID order and stop after the first few,
  /// but ordering by any other column makes it collect every match first. On
  /// a word that occurs in a third of all messages that is the difference
  /// between one millisecond and several hundred. With the time in the row
  /// ID, "newest matches first" is that cheap walk, and the last row ID of a
  /// page is the cursor for the next one.
  ///
  /// The hash spreads messages that share a millisecond, which bridges
  /// produce when they import history. It is kept to a few bits because the
  /// index stores the distance between the row IDs of consecutive matches,
  /// and larger row IDs make every one of those entries longer.
  @visibleForTesting
  static int baseId(String eventId, int timestamp) {
    // FNV-1a. The hash only has to spread, and a fixed function keeps row
    // IDs the same between runs.
    var hash = 0x811c9dc5;
    for (final unit in eventId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    final slot = hash & ((1 << _slotBits) - 1);
    return (timestamp.clamp(0, _maxTimestamp) << _slotBits) | slot;
  }

  /// Inserts a message, or updates its text when the event is already known.
  ///
  /// When the wanted row ID is taken by another event, the row goes to the
  /// first free ID after it. An existing row only takes the new text when it
  /// comes from the same or a newer edit, so an original that is indexed
  /// after its edit does not bring the old wording back.
  static const _upsert =
      'INSERT INTO messages (id, event_id, room, sender, ts, edit_ts, body) '
      'VALUES ('
      '(SELECT CASE WHEN NOT EXISTS (SELECT 1 FROM messages WHERE id = ?1) '
      'THEN ?1 ELSE (SELECT min(m.id) + 1 FROM messages m WHERE m.id >= ?1 '
      'AND NOT EXISTS (SELECT 1 FROM messages n WHERE n.id = m.id + 1)) END), '
      '?2, (SELECT id FROM names WHERE name = ?3), '
      '(SELECT id FROM names WHERE name = ?4), ?5, ?6, ?7) '
      'ON CONFLICT (event_id) DO UPDATE SET '
      'body = excluded.body, edit_ts = excluded.edit_ts '
      'WHERE excluded.edit_ts >= messages.edit_ts '
      'AND excluded.body != messages.body';

  static const _addName = 'INSERT OR IGNORE INTO names (name) VALUES (?)';

  /// The room and user IDs known to be in the `names` table, so that only
  /// the first message of a room or sender has to make sure of it.
  final Set<String> _storedNames = {};

  static const _watermarkKey = 'sdk_events_rowid';

  /// Applies [operations] in order, in one transaction.
  ///
  /// [watermark] records how far the SDK database has been read, see
  /// [watermark]. It is written in the same transaction, so the index never
  /// claims to have read events it did not store.
  Future<void> apply(List<IndexOperation> operations, {int? watermark}) async {
    if (operations.isEmpty && watermark == null) return;
    final batch = _db.batch();
    final newNames = <String>{};
    for (final operation in operations) {
      switch (operation) {
        case IndexMessage():
          for (final name in [operation.roomId, operation.senderId]) {
            if (_storedNames.contains(name) || !newNames.add(name)) continue;
            batch.execute(_addName, [name]);
          }
          batch.execute(_upsert, [
            baseId(operation.eventId, operation.timestamp),
            operation.eventId,
            operation.roomId,
            operation.senderId,
            operation.timestamp,
            operation.editTimestamp,
            operation.body,
          ]);
        case RemoveMessage():
          batch.delete(
            'messages',
            where: 'event_id = ?',
            whereArgs: [operation.eventId],
          );
      }
    }
    if (watermark != null) {
      batch.insert('meta', {
        'k': _watermarkKey,
        'v': '$watermark',
      }, conflictAlgorithm: ConflictAlgorithm.replace);
    }
    await batch.commit(noResult: true);
    // Only now is it certain that the names were written.
    _storedNames.addAll(newNames);
  }

  /// The row ID in the SDK's event table up to which stored events have been
  /// indexed. 0 for a new index.
  Future<int> get watermark async {
    final rows = await _db.query(
      'meta',
      columns: ['v'],
      where: 'k = ?',
      whereArgs: [_watermarkKey],
    );
    return int.tryParse(rows.firstOrNull?['v'] as String? ?? '') ?? 0;
  }

  /// Returns up to [limit] messages containing every term of [query], newest
  /// first. [before] is the cursor of the page before.
  Future<MessageSearchPage> search(
    SearchQuery query, {
    int? before,
    int limit = 30,
  }) async {
    final rows = await _db.rawQuery(
      'SELECT m.id, m.event_id, r.name AS room_id, s.name AS sender, m.ts, '
      'm.body FROM messages m '
      'JOIN names r ON r.id = m.room JOIN names s ON s.id = m.sender '
      'WHERE m.id IN (SELECT rowid FROM messages_fts '
      'WHERE messages_fts MATCH ? AND rowid < ? '
      'ORDER BY rowid DESC LIMIT ?) ORDER BY m.id DESC',
      [query.ftsMatch, before ?? double.maxFinite.toInt(), limit],
    );
    return MessageSearchPage(
      hits: [
        for (final row in rows)
          MessageSearchHit(
            eventId: row['event_id']! as String,
            roomId: row['room_id']! as String,
            senderId: row['sender']! as String,
            body: row['body']! as String,
            timestamp: DateTime.fromMillisecondsSinceEpoch(row['ts']! as int),
          ),
      ],
      nextCursor: rows.length < limit ? null : rows.last['id']! as int,
    );
  }

  /// The rooms that have messages in the index.
  ///
  /// This and [removeRoom] read the whole table. They run once per app start
  /// at most, which does not justify an index on the room that every message
  /// would pay for in file size.
  Future<List<String>> roomIds() async {
    final rows = await _db.rawQuery(
      'SELECT name FROM names '
      'WHERE id IN (SELECT DISTINCT room FROM messages)',
    );
    return [for (final row in rows) row['name']! as String];
  }

  /// Forgets every message of a room, for example after leaving it.
  Future<void> removeRoom(String roomId) => _db.rawDelete(
    'DELETE FROM messages '
    'WHERE room = (SELECT id FROM names WHERE name = ?)',
    [roomId],
  );

  /// Returns disk space the index no longer needs to the file system.
  ///
  /// Filling the index leaves unused pages behind, because FTS5 writes small
  /// segments first and merges them into larger ones later. After the first
  /// indexing run they make up a quarter of the file.
  Future<void> compact() async {
    await _db.rawQuery('PRAGMA incremental_vacuum');
    await _db.rawQuery('PRAGMA wal_checkpoint(TRUNCATE)');
  }

  Future<LocalMessageIndexStats> stats() async {
    final rows = await _db.rawQuery('SELECT count(*) AS n FROM messages');
    var bytes = 0;
    // The write-ahead log is part of what the index occupies.
    for (final file in [File(path), File('$path-wal')]) {
      if (file.existsSync()) bytes += file.lengthSync();
    }
    return LocalMessageIndexStats(
      messages: rows.first['n']! as int,
      bytes: bytes,
    );
  }

  /// Empties the index and gives its disk space back.
  Future<void> clear() async {
    final batch = _db.batch();
    // Dropping the tables is quicker than deleting row by row, which would
    // run the FTS triggers once per message.
    batch.execute('DROP TABLE messages_fts');
    batch.execute('DROP TABLE messages');
    batch.execute('DROP TABLE names');
    batch.execute('DROP TABLE meta');
    // Created again in the same transaction, so nothing that reads the index
    // in between finds it without its tables.
    _addSchema(batch);
    await batch.commit(noResult: true);
    _storedNames.clear();
    await compact();
  }

  Future<void> close() => _db.close();

  /// Closes the index and removes its files.
  Future<void> delete() async {
    await _db.close();
    await _factory.deleteDatabase(path);
  }
}
