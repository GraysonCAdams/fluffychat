// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/image_bubble.dart';
import 'package:fluffychat/utils/local_media_preview.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

/// Serves every media download with a one-pixel PNG and records which
/// media were asked for; anything else goes to the SDK's fake server.
class _MediaServer extends http.BaseClient {
  final _api = FakeMatrixApi();
  final downloads = <String>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    final path = request.url.path;
    if (path.contains('/download/')) {
      downloads.add(path.split('/').last);
      return Future.value(
        http.StreamedResponse(
          Stream.value(_png),
          200,
          headers: {'content-type': 'image/png'},
        ),
      );
    }
    return _api.send(request);
  }
}

final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwADAgH/'
  'pCtHEwAAAABJRU5ErkJggg==',
);

class _FakeMatrix extends MatrixState {
  final Client fakeClient;
  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

/// An image Seam sent, which a bridge then edits twice to swap the file
/// (the iMessage bridge converts a PNG to JPEG and later points back at
/// the original). The bubble shows each new file, not its placeholder.
void main() {
  late Client client;
  late _MediaServer server;
  late Room room;

  setUp(() async {
    sqfliteFfiInit();
    server = _MediaServer();
    client = Client(
      'edited image bubble',
      httpClient: server,
      database: await MatrixSdkDatabase.init(
        'edited image bubble',
        database: await databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    await client.init(
      newHomeserver: Uri.parse('https://fakeserver.notexisting'),
      newDeviceID: 'ABCD1234',
      newDeviceName: 'edited image bubble',
      newToken: '1234',
      newUserID: '@test:fakeServer.notExisting',
    );
    client.backgroundSync = false;
    room = client.getRoomById('!726s6s6q:example.com')!;
  });

  tearDown(() => MxcImage.clearCache(room.id));

  const sent = r'$ugdajjal8AAcO5i2KxTKSvn85zk8e4FLpeeT9gV3Biw';
  const txid = 'Seam windows-1-1795845670000';
  const png = 'mxc://d.graysons.network/UIWDudGNnzSmjdCCkEmtVqqv';
  const jpeg = 'mxc://d.graysons.network/dUuJyfDcJrkfPXUKjzDdcQCX';

  Map<String, Object?> image(String url, String mime, int size) => {
    'msgtype': MessageTypes.Image,
    'body': 'IMG.png',
    'filename': 'IMG.png',
    'url': url,
    'info': {'mimetype': mime, 'w': 768, 'h': 768, 'size': size},
  };

  /// The message as the timeline shows it after the edit [editId], as
  /// Event.getDisplayEvent builds it: the edit's event with its
  /// m.new_content as content.
  Event shown(String editId, Map<String, Object?> content) => Event(
    content: content,
    type: EventTypes.Message,
    eventId: editId,
    senderId: '@test:fakeServer.notExisting',
    originServerTs: DateTime(2026, 11, 28, 6, 1, 10),
    room: room,
  );

  Future<void> show(
    WidgetTester tester,
    Event event, {
    void Function()? onFirstFrame,
  }) async {
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrix(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(child: ImageBubble(event, width: 256, height: 256)),
          ),
        ),
      ),
    );
    onFirstFrame?.call();
    for (var i = 0; i < 10; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  /// Whether the bubble shows a picture rather than its placeholder.
  bool showsPicture(WidgetTester tester) {
    final fade = find.descendant(
      of: find.byType(MxcImage),
      matching: find.byType(AnimatedCrossFade),
    );
    // A picture that was there from the first frame has no cross fade.
    if (fade.evaluate().isEmpty) return true;
    return tester.widget<AnimatedCrossFade>(fade).crossFadeState ==
        CrossFadeState.showFirst;
  }

  testWidgets('a bridge edit that swaps the file shows the new file', (
    tester,
  ) async {
    // Sent from this device: the picture is primed under the transaction.
    primeLocalMediaPreview(
      room: room,
      txid: txid,
      file: MatrixImageFile(bytes: _png, name: 'IMG.png'),
    );
    await show(
      tester,
      Event(
        content: image(png, 'image/png', 316774),
        type: EventTypes.Message,
        eventId: sent,
        senderId: '@test:fakeServer.notExisting',
        originServerTs: DateTime(2026, 11, 28, 6, 1, 10),
        unsigned: {'transaction_id': txid},
        room: room,
      ),
    );
    expect(showsPicture(tester), isTrue);

    // The bridge's first edit: the PNG converted to JPEG.
    await show(
      tester,
      shown(r'$edit1', image(jpeg, 'image/jpeg', 81082)),
      // While the new file loads, the old picture stays.
      onFirstFrame: () => expect(showsPicture(tester), isTrue),
    );
    expect(showsPicture(tester), isTrue);
    expect(server.downloads, contains('dUuJyfDcJrkfPXUKjzDdcQCX'));

    // Its second: back to the original PNG.
    await show(tester, shown(r'$edit2', image(png, 'image/png', 316774)));
    expect(server.downloads, contains('UIWDudGNnzSmjdCCkEmtVqqv'));
    expect(showsPicture(tester), isTrue);
  });
}
