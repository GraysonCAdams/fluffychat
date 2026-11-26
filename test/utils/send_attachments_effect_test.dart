// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/send_attachments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'message_search/search_test_client.dart';

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// A room that keeps what would be sent instead of sending it.
class _RecordingRoom extends Room {
  _RecordingRoom(Client client)
    : super(id: '!effects:example.com', client: client);

  final sent = <Map<String, Object?>>[];

  @override
  Future<String?> sendFileEvent(
    MatrixFile file, {
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    int? shrinkImageMaxDimension,
    MatrixImageFile? thumbnail,
    Map<String, dynamic>? extraContent,
    String? threadRootEventId,
    String? threadLastEventId,
    StreamController<FileSendingStatus>? statusStream,
    bool displayPendingEvent = true,
  }) async {
    sent.add({...?extraContent});
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;

  setUpAll(() async {
    client = await createSearchTestClient();
  });

  XFile photo(String name) => XFile.fromData(
    Uint8List.fromList(_png),
    name: name,
    mimeType: 'image/png',
  );

  test('every file goes out with the effect picked', () async {
    final room = _RecordingRoom(client);
    await sendAttachments(
      room: room,
      files: [photo('a.png'), photo('b.png')],
      effect: MessageEffect.slam,
    );
    expect(room.sent, hasLength(2));
    for (final content in room.sent) {
      expect(content[messageEffectKey], MessageEffect.slam.id);
    }
  });

  test('without an effect the files carry none', () async {
    final room = _RecordingRoom(client);
    await sendAttachments(room: room, files: [photo('a.png')]);
    expect(room.sent, hasLength(1));
    expect(room.sent.single.containsKey(messageEffectKey), isFalse);
  });
}
