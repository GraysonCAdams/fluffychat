// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/utils/send_attachments.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:matrix/matrix.dart';

import 'message_search/search_test_client.dart';

/// A 1x1 PNG, standing in for a video's first frame.
final _frame = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

/// A room that keeps each file it is asked to send, with its thumbnail
/// and transaction ID, instead of sending it.
class _RecordingRoom extends Room {
  _RecordingRoom(Client client)
    : super(id: '!video:example.com', client: client);

  final sent =
      <({MatrixFile file, MatrixImageFile? thumbnail, String? txid})>[];

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
    sent.add((file: file, thumbnail: thumbnail, txid: txid));
    return null;
  }
}

/// On the desktop a video goes out with its first frame as the thumbnail,
/// the frame the composer already made for its preview. Without one, the
/// bubble has nothing but a blur hash to show for it, once sent and in
/// every other client.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late Directory folder;

  setUpAll(() async {
    client = await createSearchTestClient();
    folder = Directory.systemTemp.createTempSync('seam_video_send');
  });

  tearDownAll(() => folder.deleteSync(recursive: true));

  XFile file(String name, String mimeType) {
    final file = File('${folder.path}/$name')..writeAsBytesSync(_frame);
    return XFile(file.path, name: name, mimeType: mimeType);
  }

  testWidgets('two photos and a movie: the movie has its poster', (
    tester,
  ) async {
    final room = _RecordingRoom(client);
    final asked = <String>[];
    await tester.runAsync(
      () => sendAttachments(
        room: room,
        files: [
          file('a.jpg', 'image/jpeg'),
          file('b.jpg', 'image/jpeg'),
          file('movie.mp4', 'video/mp4'),
        ],
        videoPoster: (path) async {
          asked.add(path);
          return _frame;
        },
      ),
    );

    expect(room.sent, hasLength(3));
    final movie = room.sent.last;
    expect(movie.file, isA<MatrixVideoFile>());
    expect(asked, [endsWith('movie.mp4')]);
    expect(movie.thumbnail, isNotNull);
    expect(movie.thumbnail!.width, 1);
    // The poster shows from the first frame of the local message.
    expect(MxcImage.isCached(room.id, movie.txid!), isTrue);
    // A photo is its own picture and needs no poster.
    expect(room.sent.first.thumbnail, isNull);
  });

  testWidgets('a movie whose frame cannot be had still goes', (tester) async {
    final room = _RecordingRoom(client);
    await tester.runAsync(
      () => sendAttachments(
        room: room,
        files: [file('movie2.mp4', 'video/mp4')],
        videoPoster: (_) async => null,
      ),
    );
    expect(room.sent.single.file, isA<MatrixVideoFile>());
    expect(room.sent.single.thumbnail, isNull);
  });
}
