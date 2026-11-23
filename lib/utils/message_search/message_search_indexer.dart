// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/matrix_sdk_extensions/flutter_matrix_dart_sdk_database/builder.dart';
import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'index_operation.dart';
import 'local_message_index.dart';
import 'message_search_hit.dart';
import 'message_search_source.dart';
import 'search_query.dart';
import 'stored_event_scanner.dart';

/// Keeps the [LocalMessageIndex] of one account up to date.
///
/// Messages reach the index two ways. Events that arrive while the app runs
/// are taken from the client's event streams, already decrypted. Everything
/// else is read from the SDK database by a [StoredEventScanner].
class MessageSearchIndexer {
  MessageSearchIndexer._(this.client);

  final Client client;

  static final _indexers = Expando<MessageSearchIndexer>();

  /// The indexer of [client]. It does nothing until [start] is called.
  static MessageSearchIndexer of(Client client) =>
      _indexers[client] ??= MessageSearchIndexer._(client);

  /// Notifies when stored events were added that the index did not hold
  /// before, so a search that already ran may now find more.
  Listenable get changes => _changes;
  final _IndexChanges _changes = _IndexChanges();

  Future<LocalMessageIndex?>? _index;
  final List<StreamSubscription<Object?>> _subscriptions = [];
  final List<IndexOperation> _pending = [];
  Timer? _flushTimer;
  Future<void> _writes = Future.value();
  Future<void>? _catchUp;
  bool _stopped = false;

  /// Live events are written in batches this far apart. An initial sync can
  /// deliver thousands of events within seconds, and one transaction for all
  /// of them costs far less than one each.
  static const _flushDelay = Duration(seconds: 1);

  /// Begins indexing. Safe to call more than once.
  void start() {
    if (_index != null || _stopped) return;
    _index = _open();
    _subscriptions
      ..add(client.onTimelineEvent.stream.listen(_onEvent))
      ..add(client.onHistoryEvent.stream.listen(_onEvent))
      ..add(
        client.onLoginStateChanged.stream
            .where((state) => state == LoginState.loggedOut)
            .listen((_) => _removeIndex()),
      );
    unawaited(catchUp());
  }

  /// The index, or null on platforms and accounts that have none.
  Future<LocalMessageIndex?> get index => _index ?? Future.value();

  Future<LocalMessageIndex?> _open() async {
    final path = LocalMessageIndex.pathFor(client);
    if (path == null) return null;
    // Without knowing how the SDK database is protected, the index is not
    // created at all. Storing message text unencrypted next to an encrypted
    // database would undo that protection.
    if (!databaseCiphers.containsKey(client.clientName)) {
      Logs().w('No database cipher known for ${client.clientName}');
      return null;
    }
    return LocalMessageIndex.open(
      path,
      cipher: databaseCiphers[client.clientName],
    );
  }

  void _onEvent(Event event) {
    final operation = IndexOperation.fromEventJson(event.toJson());
    if (operation == null) return;
    _pending.add(operation);
    _flushTimer ??= Timer(_flushDelay, flush);
  }

  /// Writes the live events collected so far.
  Future<void> flush() {
    _flushTimer?.cancel();
    _flushTimer = null;
    if (_pending.isEmpty) return _writes;
    final operations = List.of(_pending);
    _pending.clear();
    return _serialized((index) => index.apply(operations));
  }

  /// Runs [action] after every write that was requested before it. The index
  /// is written from live events, from the scanner and from the settings
  /// page, and a rebuild must not interleave with either of the others.
  Future<void> _serialized(
    Future<void> Function(LocalMessageIndex index) action,
  ) => _writes = _writes.then((_) async {
    final index = await this.index;
    if (index == null || _stopped) return;
    try {
      await action(index);
    } catch (e, s) {
      Logs().w('Writing the message search index failed', e, s);
    }
  });

  /// Indexes what the SDK database holds beyond what is indexed already.
  /// Calls made while a run is active share that run.
  Future<void> catchUp() => _catchUp ??= _runCatchUp().whenComplete(() {
    _catchUp = null;
  });

  bool get isCatchingUp => _catchUp != null;

  Future<void> _runCatchUp() async {
    final database = client.database;
    final sdkDatabase = database is MatrixSdkDatabase
        ? database.database
        : null;
    if (sdkDatabase == null) return;
    var foundNew = false;
    await _serialized((index) async {
      foundNew = await StoredEventScanner(
        sdkDatabase,
        index,
      ).catchUp(isCancelled: () => _stopped);
      await _forgetLeftRooms(index);
    });
    if (foundNew && !_stopped) _changes.notify();
  }

  /// Drops the messages of rooms the account is no longer in.
  Future<void> _forgetLeftRooms(LocalMessageIndex index) async {
    // Before the first sync the room list is not loaded, and every room
    // would look like one that was left.
    if (client.prevBatch == null || client.rooms.isEmpty) return;
    for (final roomId in await index.roomIds()) {
      if (client.getRoomById(roomId) == null) await index.removeRoom(roomId);
    }
  }

  /// Size of the index for the settings page. Null when there is no index.
  Future<LocalMessageIndexStats?> stats() async {
    await flush();
    return (await index)?.stats();
  }

  /// Empties the index and fills it again from the SDK database.
  Future<void> rebuild() async {
    _pending.clear();
    await _serialized((index) => index.clear());
    await catchUp();
  }

  /// Logging out deletes the SDK database. The index holds the same message
  /// text and goes with it.
  Future<void> _removeIndex() async {
    final index = await this.index;
    _stopped = true;
    _flushTimer?.cancel();
    _pending.clear();
    for (final subscription in _subscriptions) {
      unawaited(subscription.cancel());
    }
    _subscriptions.clear();
    await _writes;
    try {
      await index?.delete();
    } catch (e, s) {
      Logs().w('Unable to delete the message search index', e, s);
    }
  }
}

class _IndexChanges extends ChangeNotifier {
  void notify() => notifyListeners();
}

/// Searches the [LocalMessageIndex] of an account.
///
/// This is the only search that sees encrypted rooms, and the only one that
/// works offline. It finds what this device has received, which for a room
/// that was never opened is its most recent messages only.
class LocalMessageSearch extends MessageSearchSource {
  LocalMessageSearch(this.indexer, {this.pageSize = 30});

  final MessageSearchIndexer indexer;
  final int pageSize;

  @override
  Listenable get changes => indexer.changes;

  @override
  Future<MessageSearchPage> search(SearchQuery query, {Object? cursor}) async {
    final index = await indexer.index;
    if (index == null) return MessageSearchPage.empty;
    if (cursor == null) {
      // Messages that arrived a moment ago should be found. While stored
      // events are still being read, their write would queue behind that
      // run, so it is not waited for.
      if (!indexer.isCatchingUp) await indexer.flush();
      // Not awaited either: the first run on a device can take a while, and
      // the search answers from what is indexed so far. The indexer
      // announces through [changes] when there is more.
      unawaited(indexer.catchUp());
    }
    return index.search(query, before: cursor as int?, limit: pageSize);
  }
}
