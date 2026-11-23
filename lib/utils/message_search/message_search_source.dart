// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:flutter/foundation.dart';

import 'message_search_hit.dart';
import 'search_query.dart';

/// A place messages can be searched in: the homeserver or the local index.
abstract class MessageSearchSource {
  /// Returns one page of hits for [query], newest first.
  ///
  /// [cursor] is the [MessageSearchPage.nextCursor] of the page before, or
  /// null for the first page. A source that cannot search right now throws,
  /// and the caller keeps what the other sources found.
  Future<MessageSearchPage> search(SearchQuery query, {Object? cursor});

  /// Notifies when the source may hold results it did not hold before, so a
  /// search that already ran is worth repeating. Null when that never
  /// happens.
  Listenable? get changes => null;
}
