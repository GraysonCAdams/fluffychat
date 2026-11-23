// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'index_operation.dart';
import 'message_search_hit.dart';
import 'search_query.dart';

/// Web build stand-in for `local_message_index_io.dart`, which needs SQLite
/// through `dart:ffi`. The web app keeps its events in IndexedDB, where no
/// full-text index is available, so [open] reports that there is none and
/// message search falls back to the homeserver alone.
class LocalMessageIndex {
  LocalMessageIndex._();

  static Future<LocalMessageIndex?> open(
    String path, {
    String? cipher,
    Object? factory,
  }) async => null;

  /// Where the index of [client] is stored, or null when it has none.
  static String? pathFor(Client client) => null;

  @visibleForTesting
  static int baseId(String eventId, int timestamp) => 0;

  Future<void> apply(List<IndexOperation> operations, {int? watermark}) async {}

  Future<MessageSearchPage> search(
    SearchQuery query, {
    int? before,
    int limit = 30,
  }) async => MessageSearchPage.empty;

  Future<int> get watermark async => 0;

  Future<List<String>> roomIds() async => const [];

  Future<void> removeRoom(String roomId) async {}

  Future<LocalMessageIndexStats> stats() async =>
      const LocalMessageIndexStats(messages: 0, bytes: 0);

  Future<void> compact() async {}

  Future<void> clear() async {}

  Future<void> close() async {}

  Future<void> delete() async {}
}
