// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';

import 'package:fluffychat/utils/merged_contacts/model.dart';
import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:flutter_test/flutter_test.dart';

/// Account data and rooms held in memory. [serverContent] is what the
/// server has; a write lands there and is echoed through [onRemoteChange]
/// as a sync would.
class _FakeBackend extends MergedContactsBackend {
  Map<String, Object?>? serverContent;
  Set<String> usableRooms;
  int clock = 1000;
  final writes = <Map<String, Object?>>[];
  bool failWrites = false;
  bool echoWrites = true;

  // Asynchronous like a real sync, so a write made while handling a
  // remote change does not re-enter the stream.
  final _remote = StreamController<void>.broadcast();
  final _rooms = StreamController<void>.broadcast(sync: true);

  _FakeBackend({this.serverContent, Set<String>? usableRooms})
    : usableRooms = usableRooms ?? {'!a', '!b', '!c', '!d'};

  @override
  Map<String, Object?>? read() => serverContent;

  @override
  Future<void> write(Map<String, Object?> content) async {
    if (failWrites) throw Exception('offline');
    // A round trip through JSON, as the server stores it.
    final stored = jsonDecode(jsonEncode(content)) as Map<String, Object?>;
    writes.add(stored);
    serverContent = stored;
    if (echoWrites) _remote.add(null);
  }

  /// Another device wrote [content].
  void remoteWrite(Map<String, Object?> content) {
    serverContent = content;
    _remote.add(null);
  }

  void roomsChanged() => _rooms.add(null);

  @override
  Stream<void> get onRemoteChange => _remote.stream;

  @override
  Stream<void> get onRoomsChanged => _rooms.stream;

  @override
  bool isUsableRoom(String roomId) => usableRooms.contains(roomId);

  @override
  Future<void> get ready async {}

  @override
  int now() => clock;
}

Map<String, Object?> _event(Map<String, Object?> contacts, {List? dismissed}) =>
    {'version': 1, 'contacts': contacts, 'dismissed_suggestions': ?dismissed};

void main() {
  group('MergedContactsData.fromJson', () {
    test('reads a contact with every field', () {
      final data = MergedContactsData.fromJson(
        _event(
          {
            'c_1': {
              'name': 'Harrison Young',
              'rooms': ['!a', '!b'],
              'send_via': '!b',
              'send_mode': 'last_received',
              'updated': 5,
              'identifier': {'type': 'phone', 'value': '+14045551234'},
              'fallback': true,
            },
          },
          dismissed: [
            ['!c', '!d'],
          ],
        ),
      );
      final contact = data.contacts['c_1']!;
      expect(contact.name, 'Harrison Young');
      expect(contact.rooms, ['!a', '!b']);
      expect(contact.sendVia, '!b');
      expect(contact.sendMode, SendMode.lastReceived);
      expect(contact.updated, 5);
      expect(contact.identifier, {'type': 'phone', 'value': '+14045551234'});
      expect(contact.fallback, isTrue);
      expect(data.dismissedSuggestions, [
        ['!c', '!d'],
      ]);
    });

    test('survives malformed content', () {
      expect(MergedContactsData.fromJson(null).contacts, isEmpty);
      expect(MergedContactsData.fromJson('nope').contacts, isEmpty);
      final data = MergedContactsData.fromJson({
        'contacts': {
          'c_1': 'not a map',
          'c_2': {
            'rooms': ['!a', 3, '!a', '', '!b'],
            'send_mode': 'bogus',
            'updated': 'yesterday',
          },
        },
        'dismissed_suggestions': [
          ['!a'],
          'x',
          ['!a', '!b'],
        ],
      });
      expect(data.contacts.keys, ['c_2']);
      expect(data.contacts['c_2']!.rooms, ['!a', '!b']);
      expect(data.contacts['c_2']!.sendMode, SendMode.preferred);
      expect(data.contacts['c_2']!.updated, 0);
      expect(data.dismissedSuggestions, [
        ['!a', '!b'],
      ]);
    });

    test('round trips through toJson', () {
      final json = _event({
        'c_1': {
          'rooms': ['!a', '!b'],
          'send_via': '!a',
          'send_mode': 'preferred',
          'updated': 7,
        },
      }, dismissed: []);
      expect(
        jsonEncode(MergedContactsData.fromJson(json).toJson()),
        jsonEncode(json),
      );
    });
  });

  group('normalized', () {
    test('drops stale rooms and dissolves contacts left with one room', () {
      final data = MergedContactsData.fromJson(
        _event({
          'c_1': {
            'rooms': ['!a', '!b', '!gone'],
            'send_via': '!gone',
            'updated': 1,
          },
          'c_2': {
            'rooms': ['!c', '!left'],
            'updated': 1,
          },
        }),
      );
      final shown = data.normalized({'!a', '!b', '!c'}.contains);
      expect(shown.map((c) => c.id), ['c_1']);
      expect(shown.single.rooms, ['!a', '!b']);
      // The send_via room is gone, so the first usable room takes over.
      expect(shown.single.sendVia, '!a');
      // The stored copy still remembers the stale room.
      expect(data.contacts['c_1']!.rooms, contains('!gone'));
    });

    test('puts each room in one contact, the newest merge winning', () {
      final data = MergedContactsData.fromJson(
        _event({
          'c_old': {
            'rooms': ['!a', '!b', '!c'],
            'updated': 1,
          },
          'c_new': {
            'rooms': ['!c', '!d'],
            'updated': 2,
          },
        }),
      );
      final shown = data.normalized((_) => true);
      final byId = {for (final c in shown) c.id: c};
      expect(byId['c_new']!.rooms, ['!c', '!d']);
      expect(byId['c_old']!.rooms, ['!a', '!b']);
    });

    test('leaves tombstones out', () {
      final data = MergedContactsData.fromJson(
        _event({
          'c_1': {'removed': true, 'rooms': [], 'updated': 3},
        }),
      );
      expect(data.normalized((_) => true), isEmpty);
    });
  });

  group('reconcile', () {
    test('keeps the newer copy of each contact', () {
      final a = MergedContactsData.fromJson(
        _event({
          'c_1': {
            'name': 'A1',
            'rooms': ['!a', '!b'],
            'updated': 5,
          },
          'c_2': {
            'name': 'A2',
            'rooms': ['!c', '!d'],
            'updated': 1,
          },
        }),
      );
      final b = MergedContactsData.fromJson(
        _event({
          'c_1': {
            'name': 'B1',
            'rooms': ['!a', '!b'],
            'updated': 4,
          },
          'c_2': {
            'name': 'B2',
            'rooms': ['!c', '!d'],
            'updated': 2,
          },
        }),
      );
      final merged = MergedContactsData.reconcile(a, b);
      expect(merged.contacts['c_1']!.name, 'A1');
      expect(merged.contacts['c_2']!.name, 'B2');
    });

    test('a newer tombstone beats an older contact and the reverse', () {
      final alive = MergedContactsData.fromJson(
        _event({
          'c_1': {
            'rooms': ['!a', '!b'],
            'updated': 1,
          },
        }),
      );
      final removed = MergedContactsData.fromJson(
        _event({
          'c_1': {'removed': true, 'rooms': [], 'updated': 2},
        }),
      );
      expect(
        MergedContactsData.reconcile(alive, removed).contacts['c_1']!.removed,
        isTrue,
      );
      expect(
        MergedContactsData.reconcile(removed, alive).contacts['c_1']!.removed,
        isTrue,
      );
    });

    test('unites dismissed pairs regardless of order', () {
      final a = MergedContactsData.fromJson(
        _event(
          {},
          dismissed: [
            ['!a', '!b'],
          ],
        ),
      );
      final b = MergedContactsData.fromJson(
        _event(
          {},
          dismissed: [
            ['!b', '!a'],
            ['!c', '!d'],
          ],
        ),
      );
      expect(MergedContactsData.reconcile(a, b).dismissedSuggestions, [
        ['!a', '!b'],
        ['!c', '!d'],
      ]);
    });

    test('old tombstones are pruned', () {
      final data = MergedContactsData.fromJson(
        _event({
          'c_1': {'removed': true, 'rooms': [], 'updated': 0},
          'c_2': {'removed': true, 'rooms': [], 'updated': 100},
        }),
      );
      final pruned = data.withoutOldTombstones(
        MergedContactsData.tombstoneLifetime.inMilliseconds + 50,
      );
      expect(pruned.contacts.keys, ['c_2']);
    });
  });

  group('MergedContactsStore', () {
    test('indexes rooms to contacts', () {
      final store = MergedContactsStore(
        _FakeBackend(
          serverContent: _event({
            'c_1': {
              'rooms': ['!a', '!b'],
              'updated': 1,
            },
          }),
        ),
      );
      expect(store.contactForRoom('!a')?.id, 'c_1');
      expect(store.contactForRoom('!b')?.id, 'c_1');
      expect(store.contactForRoom('!c'), isNull);
      expect(store.contactById('c_1')?.rooms, ['!a', '!b']);
      store.dispose();
    });

    test('merge, rename, send via, unmerge', () async {
      final backend = _FakeBackend();
      final store = MergedContactsStore(backend);
      final revisions = <int>[];
      store.revision.addListener(() => revisions.add(store.revision.value));

      final id = await store.merge(['!a', '!b']);
      expect(store.contactForRoom('!a')?.id, id);
      expect(store.contactById(id)!.sendVia, '!a');

      backend.clock = 2000;
      await store.rename(id, '  Harrison  ');
      expect(store.contactById(id)!.name, 'Harrison');
      expect(store.contactById(id)!.updated, 2000);

      await store.setSendVia(id, '!b');
      expect(store.contactById(id)!.sendVia, '!b');

      await store.unmerge(id);
      expect(store.contactForRoom('!a'), isNull);
      // The unmerge is stored as a tombstone, not a deletion.
      expect(store.stored.contacts[id]!.removed, isTrue);
      expect(revisions, isNotEmpty);
      store.dispose();
    });

    test('merging a room moves it out of its old contact', () async {
      final backend = _FakeBackend(
        serverContent: _event({
          'c_1': {
            'rooms': ['!a', '!b', '!c'],
            'updated': 1,
          },
        }),
      );
      final store = MergedContactsStore(backend);
      final id = await store.merge(['!c', '!d']);
      expect(store.contactForRoom('!c')?.id, id);
      expect(store.contactById('c_1')!.rooms, ['!a', '!b']);

      // Taking one more room leaves c_1 with a single room: it dissolves.
      await store.merge(['!b'], intoContactId: id);
      expect(store.contactById('c_1'), isNull);
      expect(store.stored.contacts['c_1']!.removed, isTrue);
      store.dispose();
    });

    test('removing a room dissolves a two-room contact', () async {
      final store = MergedContactsStore(
        _FakeBackend(
          serverContent: _event({
            'c_1': {
              'rooms': ['!a', '!b'],
              'updated': 1,
            },
          }),
        ),
      );
      await store.removeRoom('!b');
      expect(store.contactForRoom('!a'), isNull);
      store.dispose();
    });

    test('a failed write restores the previous contacts', () async {
      final backend = _FakeBackend()..failWrites = true;
      final store = MergedContactsStore(backend);
      await expectLater(store.merge(['!a', '!b']), throwsException);
      expect(store.contactForRoom('!a'), isNull);
      store.dispose();
    });

    test('rooms becoming unusable are dropped from the index', () {
      final backend = _FakeBackend(
        serverContent: _event({
          'c_1': {
            'rooms': ['!a', '!b', '!c'],
            'updated': 1,
          },
        }),
      );
      final store = MergedContactsStore(backend);
      backend.usableRooms = {'!a', '!b'};
      backend.roomsChanged();
      expect(store.contactById('c_1')!.rooms, ['!a', '!b']);
      backend.usableRooms = {'!a'};
      backend.roomsChanged();
      expect(store.contactForRoom('!a'), isNull);
      store.dispose();
    });

    test(
      'repairs a remote write that lost this device\'s newer edit',
      () async {
        final backend = _FakeBackend(
          serverContent: _event({
            'c_1': {
              'rooms': ['!a', '!b'],
              'updated': 1,
            },
            'c_2': {
              'rooms': ['!c', '!d'],
              'updated': 1,
            },
          }),
        );
        final store = MergedContactsStore(backend);
        backend.clock = 10;
        await store.rename('c_1', 'Mine');
        // Another device renames c_2 from a copy made before our rename, and
        // its write lands after ours, overwriting it.
        backend.remoteWrite(
          _event({
            'c_1': {
              'rooms': ['!a', '!b'],
              'updated': 1,
            },
            'c_2': {
              'name': 'Theirs',
              'rooms': ['!c', '!d'],
              'updated': 11,
            },
          }),
        );
        await Future<void>.delayed(Duration.zero);
        final server = MergedContactsData.fromJson(backend.serverContent);
        expect(server.contacts['c_1']!.name, 'Mine');
        expect(server.contacts['c_2']!.name, 'Theirs');
        expect(store.contactById('c_1')!.name, 'Mine');
        expect(store.contactById('c_2')!.name, 'Theirs');
        // Converged: our own repaired write echoing back writes nothing more.
        final writes = backend.writes.length;
        backend.remoteWrite(backend.serverContent!);
        await Future<void>.delayed(Duration.zero);
        expect(backend.writes.length, writes);
        store.dispose();
      },
    );

    test('an overwrite long after the edit is not repaired', () async {
      final backend = _FakeBackend(
        serverContent: _event({
          'c_1': {
            'rooms': ['!a', '!b'],
            'updated': 1,
          },
        }),
      );
      final store = MergedContactsStore(backend);
      backend.clock = 10;
      await store.rename('c_1', 'Mine');
      backend.clock = 10 + MergedContactsStore.repairWindow.inMilliseconds + 1;
      // Another device pruned an old tombstone set and wrote without c_1:
      // this device must not bring c_1 back from its old write.
      final writes = backend.writes.length;
      backend.remoteWrite(_event({}));
      await Future<void>.delayed(Duration.zero);
      expect(backend.writes.length, writes);
      expect(store.contactById('c_1'), isNull);
      store.dispose();
    });

    test('the same contact edited on two devices: last write wins', () async {
      final backend = _FakeBackend(
        serverContent: _event({
          'c_1': {
            'rooms': ['!a', '!b'],
            'updated': 1,
          },
        }),
      );
      final store = MergedContactsStore(backend);
      backend.clock = 10;
      await store.rename('c_1', 'Mine');
      backend.remoteWrite(
        _event({
          'c_1': {
            'name': 'Theirs',
            'rooms': ['!a', '!b'],
            'updated': 20,
          },
        }),
      );
      await Future<void>.delayed(Duration.zero);
      expect(store.contactById('c_1')!.name, 'Theirs');
      expect(
        MergedContactsData.fromJson(
          backend.serverContent,
        ).contacts['c_1']!.name,
        'Theirs',
      );
      store.dispose();
    });

    test('dismissed pairs are stored once', () async {
      final backend = _FakeBackend();
      final store = MergedContactsStore(backend);
      await store.dismissSuggestion('!b', '!a');
      await store.dismissSuggestion('!a', '!b');
      expect(store.stored.dismissedSuggestions, [
        ['!a', '!b'],
      ]);
      store.dispose();
    });
  });
}
