// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import 'index_operation.dart';
import 'local_message_index.dart';

/// Reads the events the SDK has stored and brings a [LocalMessageIndex] up to
/// date with them.
///
/// The SDK keeps every timeline event it received in the table `box_events`,
/// one row per event with the event JSON in the column `v`. Events of
/// encrypted rooms are stored decrypted. This is where the index gets
/// everything it did not see arrive: messages from before the index existed,
/// messages stored while the app was in the background, and messages that
/// could only be decrypted after they were stored.
class StoredEventScanner {
  StoredEventScanner(this._sdkDatabase, this._index);

  final Database _sdkDatabase;
  final LocalMessageIndex _index;

  /// How many rows of the SDK table one step looks at. A step is one query
  /// and one write in sqflite's background isolate, and its result is copied
  /// to the UI isolate. Small steps keep that copy far below a frame, and let
  /// the SDK's own database work run in between.
  static const stepSize = 400;

  /// How far below the watermark every run starts again.
  ///
  /// The SDK rewrites an event by replacing its row, for example when it
  /// decrypts it later or when it is redacted. SQLite gives the replacement
  /// a row ID above all others, so it shows up above the watermark by
  /// itself. Deleted rows are different: when the newest rows are deleted,
  /// their IDs are free again and the next events stored take them, at or
  /// below the watermark. Reading this many rows again finds those, and
  /// indexing a row twice changes nothing.
  ///
  /// Events that took the place of more deleted rows than this are missed by
  /// this run. Those that arrive while the app is running are indexed from
  /// the event streams regardless.
  static const overlap = 400;

  /// The columns are extracted inside SQLite, so the JSON of an event is
  /// never decoded in Dart, and rows that cannot matter are not returned at
  /// all.
  static const _select =
      'SELECT rowid AS r, '
      "json_extract(v, '\$.type') AS type, "
      "json_extract(v, '\$.event_id') AS event_id, "
      "json_extract(v, '\$.room_id') AS room_id, "
      "json_extract(v, '\$.sender') AS sender, "
      "json_extract(v, '\$.origin_server_ts') AS ts, "
      "json_extract(v, '\$.content.body') AS body, "
      "json_extract(v, '\$.redacts') AS redacts, "
      "json_extract(v, '\$.unsigned.redacted_because') IS NOT NULL AS redacted, "
      "json_extract(v, '\$.content.\"m.relates_to\".rel_type') AS rel_type, "
      "json_extract(v, '\$.content.\"m.relates_to\".event_id') AS rel_event, "
      "json_extract(v, '\$.content.\"m.new_content\".body') AS new_body "
      'FROM box_events WHERE rowid > ? AND rowid <= ? '
      "AND json_extract(v, '\$.type') IN ('m.room.message', 'm.room.redaction') "
      'ORDER BY rowid';

  /// Indexes what the SDK stored since the last run.
  ///
  /// Returns true when there were rows above the watermark, which means the
  /// index may now find messages it could not find before. [isCancelled] is
  /// asked between steps so a long first run stops when the account goes
  /// away.
  Future<bool> catchUp({bool Function()? isCancelled}) async {
    final maxRow = await _maxRowId();
    var watermark = await _index.watermark;
    // Fewer rows than were already read: the SDK emptied its store, as it
    // does on "clear cache". Row IDs start over, so reading does as well.
    if (maxRow < watermark) watermark = 0;
    final hadNewRows = maxRow > watermark;
    var from = watermark - overlap;
    if (from < 0) from = 0;
    while (from < maxRow) {
      if (isCancelled?.call() ?? false) return hadNewRows;
      final to = from + stepSize < maxRow ? from + stepSize : maxRow;
      final rows = await _sdkDatabase.rawQuery(_select, [from, to]);
      await _index.apply([
        for (final row in rows) ?_operationFor(row),
      ], watermark: to);
      from = to;
    }
    if (maxRow != await _index.watermark) {
      await _index.apply(const [], watermark: maxRow);
    }
    return hadNewRows;
  }

  Future<int> _maxRowId() async {
    final rows = await _sdkDatabase.rawQuery(
      'SELECT max(rowid) AS r FROM box_events',
    );
    return rows.firstOrNull?['r'] as int? ?? 0;
  }

  static IndexOperation? _operationFor(Map<String, Object?> row) =>
      IndexOperation.fromEvent(
        type: _string(row['type']),
        eventId: _string(row['event_id']),
        roomId: _string(row['room_id']),
        senderId: _string(row['sender']),
        timestamp: row['ts'] is int ? row['ts']! as int : null,
        body: _string(row['body']),
        redacts: _string(row['redacts']),
        isRedacted: row['redacted'] == 1,
        relationType: _string(row['rel_type']),
        relatesToEventId: _string(row['rel_event']),
        replacementBody: _string(row['new_body']),
      );

  static String? _string(Object? value) => value is String ? value : null;
}
