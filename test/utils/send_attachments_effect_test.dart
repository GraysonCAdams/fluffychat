// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/new_chat/new_group.dart';
import 'package:fluffychat/utils/room_features.dart';
import 'package:fluffychat/utils/send_attachments.dart';
import 'package:fluffychat/utils/share_items.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'message_search/search_test_client.dart';
import 'room_features_fixtures.dart';

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// A room that keeps what would be sent instead of sending it: each file
/// event's content as the SDK puts it together, and each other event.
class _RecordingRoom extends Room {
  _RecordingRoom(Client client)
    : super(id: '!effects:example.com', client: client);

  final files = <Map<String, Object?>>[];
  final replies = <String?>[];
  final messages = <Map<String, Object?>>[];

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
    bool displayPendingEvent = true,
  }) async {
    // As Room.sendFileEvent builds it.
    files.add({'body': file.name, 'filename': file.name, ...?extraContent});
    replies.add(inReplyTo?.eventId);
    return null;
  }

  @override
  Future<String?> sendEvent(
    Map<String, dynamic> content, {
    String type = EventTypes.Message,
    String? txid,
    Event? inReplyTo,
    String? editEventId,
    String? threadRootEventId,
    String? threadLastEventId,
    bool displayPendingEvent = true,
  }) async {
    messages.add(content);
    return null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late Directory folder;

  setUpAll(() async {
    client = await createSearchTestClient();
    folder = Directory.systemTemp.createTempSync('seam_attachments');
  });

  tearDownAll(() => folder.deleteSync(recursive: true));

  XFile photo(String name) {
    final file = File('${folder.path}/$name')..writeAsBytesSync(_png);
    return XFile(file.path, name: name, mimeType: 'image/png');
  }

  test('a photo and its caption go out as one event with the effect', () async {
    final room = _RecordingRoom(client);
    final reply = Event(
      content: {'msgtype': 'm.text', 'body': 'Where?'},
      type: EventTypes.Message,
      eventId: '\$question',
      senderId: '@alice:example.org',
      originServerTs: DateTime.now(),
      room: room,
    );
    await sendAttachments(
      room: room,
      files: [photo('roof.png')],
      caption: 'Sunset from the **roof**',
      inReplyTo: reply,
      effect: MessageEffect.slam,
    );
    expect(room.messages, isEmpty);
    expect(room.files, hasLength(1));
    final content = room.files.single;
    expect(content['body'], 'Sunset from the **roof**');
    expect(content['filename'], 'roof.png');
    expect(content['format'], 'org.matrix.custom.html');
    expect(content['formatted_body'], contains('<strong>roof</strong>'));
    expect(content.containsKey('msgtype'), isFalse);
    expect(content[messageEffectKey], MessageEffect.slam.id);
    expect(room.replies, ['\$question']);
  });

  test('a photo alone carries the effect', () async {
    final room = _RecordingRoom(client);
    await sendAttachments(
      room: room,
      files: [photo('a.png')],
      effect: MessageEffect.loud,
    );
    expect(room.messages, isEmpty);
    expect(room.files.single['body'], 'a.png');
    expect(room.files.single[messageEffectKey], MessageEffect.loud.id);
  });

  test(
    'of several files only the last carries the caption and the effect',
    () async {
      final room = _RecordingRoom(client);
      await sendAttachments(
        room: room,
        files: [photo('a.png'), photo('b.png'), photo('c.png')],
        caption: 'Three',
        effect: MessageEffect.slam,
      );
      expect(room.messages, isEmpty);
      expect(room.files.map((content) => content['body']), [
        'a.png',
        'b.png',
        'Three',
      ]);
      expect(
        room.files.where((content) => content.containsKey(messageEffectKey)),
        hasLength(1),
      );
      expect(room.files.last[messageEffectKey], MessageEffect.slam.id);
    },
  );

  test('without an effect the files carry none', () async {
    final room = _RecordingRoom(client);
    await sendAttachments(room: room, files: [photo('a.png')]);
    expect(room.files, hasLength(1));
    expect(room.files.single.containsKey(messageEffectKey), isFalse);
  });

  test('where captions are refused the caption follows on its own, '
      'the effect staying on the photo', () async {
    final room = _RecordingRoom(client);
    room.setState(
      Event(
        type: RoomFeatures.eventType,
        content: Map<String, Object?>.of(noCaptionFeatures),
        eventId: '\$features',
        senderId: '@bridge:example.org',
        originServerTs: DateTime.now(),
        stateKey: 'bridge',
        room: room,
      ),
    );
    await sendAttachments(
      room: room,
      files: [photo('a.png')],
      caption: 'Hi',
      effect: MessageEffect.gentle,
    );
    expect(room.files.single['body'], 'a.png');
    expect(room.files.single[messageEffectKey], MessageEffect.gentle.id);
    expect(room.messages, hasLength(1));
    expect(room.messages.single['body'], 'Hi');
    expect(room.messages.single.containsKey(messageEffectKey), isFalse);
  });

  testWidgets('a share of a photo with text sends the text as its caption', (
    tester,
  ) async {
    final room = _RecordingRoom(client);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: const Scaffold(body: SizedBox()),
      ),
    );
    await tester.pumpAndSettle();
    final context = tester.element(find.byType(SizedBox));
    final shared = photo('shared.png');
    await tester.runAsync(
      () => const NewChatDelivery().sendShare(
        context,
        room,
        SharePayload(files: [shared], text: 'Look'),
        effect: MessageEffect.confetti,
      ),
    );
    expect(room.messages, isEmpty);
    expect(room.files.single['body'], 'Look');
    expect(room.files.single['filename'], 'shared.png');
    expect(room.files.single[messageEffectKey], MessageEffect.confetti.id);
  });
}
