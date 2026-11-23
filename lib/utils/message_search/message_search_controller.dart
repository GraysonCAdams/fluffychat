// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:matrix/matrix.dart';

import 'message_search_hit.dart';
import 'message_search_source.dart';
import 'search_query.dart';

/// Runs one message search across several [MessageSearchSource]s and keeps
/// the merged result list for the UI.
///
/// Every source answers on its own schedule. Hits are published as soon as
/// any source delivers them, so a fast local index is not held back by a slow
/// homeserver or the other way round.
class MessageSearchController extends ChangeNotifier {
  MessageSearchController(
    List<MessageSearchSource> sources, {
    this.debounce = const Duration(milliseconds: 250),
  }) : _sources = [for (final source in sources) _SourceState(source)] {
    for (final state in _sources) {
      state.source.changes?.addListener(state.onChanged = () => _rerun(state));
    }
  }

  /// How long typing has to pause before a search starts. Without it every
  /// keystroke would start a request that the next keystroke makes useless.
  final Duration debounce;

  final List<_SourceState> _sources;
  Timer? _debounceTimer;
  bool _disposed = false;

  /// Counts query changes. Sources cannot be interrupted once asked, so an
  /// answer is checked against this number and dropped when the query moved
  /// on in the meantime.
  int _generation = 0;

  /// The query the current [hits] belong to. Null while the input is too
  /// short to search for.
  SearchQuery? get query => _query;
  SearchQuery? _query;

  /// Hits of all sources, newest first, each event once.
  List<MessageSearchHit> get hits => _hits;
  List<MessageSearchHit> _hits = const [];

  /// Words to emphasise in the hits: the query terms plus whatever word forms
  /// the homeserver said it matched.
  Set<String> get highlights => _highlights;
  Set<String> _highlights = const {};

  /// Counts the pages merged into [hits] for the current query. A list
  /// footer that asks for the next page uses it to tell that a page arrived
  /// even when it added no new rows.
  int get loadedPages => _loadedPages;
  int _loadedPages = 0;

  /// True from the moment the input changes until every source answered.
  bool get isLoading =>
      _debounceTimer != null || _sources.any((state) => state.loading);

  /// True when at least one source has another page.
  bool get hasMore => _sources.any((state) => state.cursor != null);

  /// True when no source could answer the current query, as opposed to
  /// answering that nothing matches.
  bool get failed => _query != null && _sources.every((state) => state.failed);

  /// Takes the current content of the search field.
  void setInput(String input) {
    final query = SearchQuery.parse(input);
    if (query == _query) return;
    _generation++;
    _debounceTimer?.cancel();
    _debounceTimer = null;
    _query = query;
    _hits = const [];
    _loadedPages = 0;
    _highlights = {...?query?.terms};
    for (final state in _sources) {
      state.reset();
    }
    if (query != null) {
      _debounceTimer = Timer(debounce, () {
        _debounceTimer = null;
        for (final state in _sources) {
          _fetch(state, query, _generation);
        }
        notifyListeners();
      });
    }
    notifyListeners();
  }

  /// Fetches the next page from every source that has one.
  void loadMore() {
    final query = _query;
    if (query == null || _debounceTimer != null) return;
    var started = false;
    for (final state in _sources) {
      if (state.loading || state.cursor == null) continue;
      _fetch(state, query, _generation, cursor: state.cursor);
      started = true;
    }
    if (started) notifyListeners();
  }

  /// Repeats the first page of a source that reported new content, and merges
  /// what it finds into the hits already shown.
  void _rerun(_SourceState state) {
    final query = _query;
    if (_disposed || query == null || _debounceTimer != null) return;
    if (state.loading) {
      state.rerunAfterLoad = true;
      return;
    }
    _fetch(state, query, _generation, isRerun: true);
    notifyListeners();
  }

  Future<void> _fetch(
    _SourceState state,
    SearchQuery query,
    int generation, {
    Object? cursor,
    bool isRerun = false,
  }) async {
    state.loading = true;
    MessageSearchPage? page;
    try {
      page = await state.source.search(query, cursor: cursor);
    } catch (e, s) {
      Logs().w('Message search failed in ${state.source.runtimeType}', e, s);
    }
    if (_disposed || generation != _generation) return;
    state.loading = false;
    if (page == null) {
      // A failed first page leaves the source without results. A failed
      // later page keeps its cursor so scrolling further tries again.
      if (cursor == null && !isRerun) state.failed = true;
    } else {
      state.failed = false;
      // A repeated first page must not move the source back to its start
      // when later pages were already loaded.
      if (!isRerun || !state.loadedFirstPage) state.cursor = page.nextCursor;
      state.loadedFirstPage = true;
      _loadedPages++;
      _hits = mergeHits(_hits, page.hits);
      if (page.highlights.isNotEmpty) {
        _highlights = {
          ..._highlights,
          for (final word in page.highlights) word.toLowerCase(),
        };
      }
    }
    if (state.rerunAfterLoad) {
      state.rerunAfterLoad = false;
      _rerun(state);
    }
    notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _debounceTimer?.cancel();
    for (final state in _sources) {
      final onChanged = state.onChanged;
      if (onChanged != null) state.source.changes?.removeListener(onChanged);
    }
    super.dispose();
  }
}

class _SourceState {
  _SourceState(this.source);

  final MessageSearchSource source;
  VoidCallback? onChanged;
  bool loading = false;
  bool failed = false;
  bool loadedFirstPage = false;
  bool rerunAfterLoad = false;
  Object? cursor;

  void reset() {
    loading = false;
    failed = false;
    loadedFirstPage = false;
    rerunAfterLoad = false;
    cursor = null;
  }
}
