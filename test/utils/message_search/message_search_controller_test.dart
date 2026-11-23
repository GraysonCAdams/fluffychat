// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:fluffychat/utils/message_search/message_search_controller.dart';
import 'package:fluffychat/utils/message_search/message_search_hit.dart';
import 'package:fluffychat/utils/message_search/message_search_source.dart';
import 'package:fluffychat/utils/message_search/search_query.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';

MessageSearchHit hit(String id, int ts) => MessageSearchHit(
  eventId: id,
  roomId: '!room:example.org',
  senderId: '@naveen:example.org',
  body: 'body of $id',
  timestamp: DateTime.fromMillisecondsSinceEpoch(ts),
);

/// A source whose answers the test hands out by hand, one per request.
class FakeSource extends MessageSearchSource {
  final requests = <({SearchQuery query, Object? cursor})>[];
  final _pending = <Completer<MessageSearchPage>>[];
  final ChangeNotifier _changes = ChangeNotifier();

  @override
  Listenable get changes => _changes;

  // ignore: invalid_use_of_protected_member, invalid_use_of_visible_for_testing_member
  void announceChange() => _changes.notifyListeners();

  @override
  Future<MessageSearchPage> search(SearchQuery query, {Object? cursor}) {
    requests.add((query: query, cursor: cursor));
    final completer = Completer<MessageSearchPage>();
    _pending.add(completer);
    return completer.future;
  }

  void answer(int request, List<MessageSearchHit> hits, {Object? next}) =>
      _pending[request].complete(
        MessageSearchPage(hits: hits, nextCursor: next),
      );

  void fail(int request) => _pending[request].completeError(Exception('down'));
}

const debounce = Duration(milliseconds: 250);

void main() {
  late FakeSource local;
  late FakeSource server;
  late MessageSearchController controller;
  late int notifications;

  setUp(() {
    local = FakeSource();
    server = FakeSource();
    controller = MessageSearchController([local, server], debounce: debounce);
    notifications = 0;
    controller.addListener(() => notifications++);
  });

  List<String> ids() => controller.hits.map((h) => h.eventId).toList();

  test('waits for a pause in typing and searches only the final text', () {
    fakeAsync((async) {
      controller.setInput('na');
      async.elapse(const Duration(milliseconds: 100));
      controller.setInput('nav');
      async.elapse(const Duration(milliseconds: 249));
      expect(local.requests, isEmpty);
      expect(controller.isLoading, isTrue);

      async.elapse(const Duration(milliseconds: 1));
      expect(local.requests.single.query.text, 'nav');
      expect(server.requests.single.query.text, 'nav');
    });
  });

  test('shows the first answer without waiting for the other source', () {
    fakeAsync((async) {
      controller.setInput('naveen');
      async.elapse(debounce);

      local.answer(0, [hit(r'$local', 100)]);
      async.flushMicrotasks();
      expect(ids(), [r'$local']);
      expect(controller.isLoading, isTrue);

      server.answer(0, [hit(r'$server', 200), hit(r'$local', 100)]);
      async.flushMicrotasks();
      expect(ids(), [r'$server', r'$local']);
      expect(controller.isLoading, isFalse);
    });
  });

  test('drops an answer that belongs to an earlier query', () {
    fakeAsync((async) {
      controller.setInput('naveen');
      async.elapse(debounce);
      controller.setInput('dinner');
      expect(controller.hits, isEmpty);

      local.answer(0, [hit(r'$stale', 100)]);
      async.flushMicrotasks();
      expect(controller.hits, isEmpty);

      async.elapse(debounce);
      local.answer(1, [hit(r'$fresh', 100)]);
      async.flushMicrotasks();
      expect(ids(), [r'$fresh']);
      expect(local.requests.map((r) => r.query.text), ['naveen', 'dinner']);
    });
  });

  test('clearing the field stops everything and empties the list', () {
    fakeAsync((async) {
      controller.setInput('naveen');
      async.elapse(debounce);
      local.answer(0, [hit(r'$a', 100)]);
      async.flushMicrotasks();

      controller.setInput('');
      expect(controller.query, isNull);
      expect(controller.hits, isEmpty);
      expect(controller.isLoading, isFalse);

      server.answer(0, [hit(r'$late', 100)]);
      async.flushMicrotasks();
      expect(controller.hits, isEmpty);
      async.elapse(debounce);
      expect(local.requests, hasLength(1));
    });
  });

  test('the same text again does not restart the search', () {
    fakeAsync((async) {
      controller.setInput('naveen');
      async.elapse(debounce);
      final before = notifications;
      controller.setInput('naveen ');
      async.elapse(debounce);
      expect(local.requests, hasLength(1));
      expect(notifications, before);
    });
  });

  test('loads further pages only from sources that have one', () {
    fakeAsync((async) {
      controller.setInput('naveen');
      async.elapse(debounce);
      local.answer(0, [hit(r'$l1', 400)]);
      server.answer(0, [hit(r'$s1', 300)], next: 'batch2');
      async.flushMicrotasks();
      expect(controller.hasMore, isTrue);

      controller.loadMore();
      // A second call while the page is on its way must not ask twice.
      controller.loadMore();
      expect(local.requests, hasLength(1));
      expect(server.requests, hasLength(2));
      expect(server.requests.last.cursor, 'batch2');

      server.answer(1, [hit(r'$s2', 200)]);
      async.flushMicrotasks();
      expect(ids(), [r'$l1', r'$s1', r'$s2']);
      expect(controller.hasMore, isFalse);
      expect(controller.loadedPages, 3);
    });
  });

  test('one failing source leaves the results of the other', () {
    fakeAsync((async) {
      controller.setInput('naveen');
      async.elapse(debounce);
      server.fail(0);
      async.flushMicrotasks();
      expect(controller.failed, isFalse);
      local.answer(0, [hit(r'$l1', 100)]);
      async.flushMicrotasks();
      expect(ids(), [r'$l1']);
      expect(controller.failed, isFalse);
      expect(controller.isLoading, isFalse);
    });
  });

  test('reports failure only when no source could answer', () {
    fakeAsync((async) {
      controller.setInput('naveen');
      async.elapse(debounce);
      server.fail(0);
      local.fail(0);
      async.flushMicrotasks();
      expect(controller.failed, isTrue);
      expect(controller.isLoading, isFalse);
    });
  });

  test('a source that gained content is searched again and merged in', () {
    fakeAsync((async) {
      controller.setInput('naveen');
      async.elapse(debounce);
      local.answer(0, [hit(r'$l1', 100)], next: 77);
      server.answer(0, []);
      async.flushMicrotasks();
      controller.loadMore();
      local.answer(1, [hit(r'$l0', 50)], next: 33);
      async.flushMicrotasks();

      local.announceChange();
      expect(local.requests, hasLength(3));
      expect(local.requests.last.cursor, isNull);
      local.answer(2, [hit(r'$l2', 200), hit(r'$l1', 100)], next: 88);
      async.flushMicrotasks();
      expect(ids(), [r'$l2', r'$l1', r'$l0']);

      // The repeated first page must not rewind the pagination.
      controller.loadMore();
      expect(local.requests.last.cursor, 33);
    });
  });

  test('ignores answers and changes after dispose', () {
    fakeAsync((async) {
      controller.setInput('naveen');
      async.elapse(debounce);
      controller.dispose();
      local.answer(0, [hit(r'$a', 100)]);
      local.announceChange();
      async.flushMicrotasks();
      expect(local.requests, hasLength(1));
    });
  });
}
