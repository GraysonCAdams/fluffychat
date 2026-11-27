// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/utils/merged_contacts/store.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'fake_rooms.dart';

void main() {
  late Client client;
  late List<String> started;
  late Map<String, Completer<void>> pending;
  late ClientMergedContactsBackend backend;
  late int changes;
  late StreamSubscription<void> sub;

  setUp(() async {
    client = await fakeMergedClient();
    started = [];
    pending = {};
    backend = ClientMergedContactsBackend(
      client,
      loadMembers: (room) {
        started.add(room.id);
        return (pending[room.id] = Completer<void>()).future;
      },
    );
    changes = 0;
    sub = backend.onRoomsChanged.listen((_) => changes++);
  });

  tearDown(() async {
    await sub.cancel();
    backend.dispose();
  });

  Room room(String id) => Room(id: id, client: client);

  Future<void> finish(String id) async {
    pending[id]!.complete();
    await pumpEventQueue();
  }

  test('loads the groups one at a time and looks again once', () async {
    for (final id in ['!a', '!b', '!c']) {
      backend.requestMembers(room(id));
    }
    await pumpEventQueue();
    expect(started, ['!a']);

    await finish('!a');
    expect(started, ['!a', '!b']);
    expect(changes, 0);

    await finish('!b');
    await finish('!c');
    expect(started, ['!a', '!b', '!c']);
    expect(changes, 1);
  });

  test('asks for each group once a session', () async {
    backend.requestMembers(room('!a'));
    backend.requestMembers(room('!a'));
    await finish('!a');
    backend.requestMembers(room('!a'));
    await pumpEventQueue();
    expect(started, ['!a']);
    expect(changes, 1);
  });

  test('a group asked for while loading joins the same pass', () async {
    backend.requestMembers(room('!a'));
    await pumpEventQueue();
    backend.requestMembers(room('!b'));
    await finish('!a');
    expect(changes, 0);
    await finish('!b');
    expect(started, ['!a', '!b']);
    expect(changes, 1);
  });
}
