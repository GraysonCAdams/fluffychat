// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/image_bubble.dart';
import 'package:fluffychat/pages/chat/events/media_sending_indicator.dart';
import 'package:fluffychat/pages/chat/events/video_player.dart';
import 'package:fluffychat/utils/send_attachments.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:sqflite_common_ffi/sqflite_ffi.dart';

import '../pages/chat_list/chat_list_fakes.dart';

/// A homeserver for sending: uploads get an mxc URI, events get an ID made
/// from their transaction, downloads serve what was uploaded. Anything
/// else goes to the SDK's fake server.
class _Server extends http.BaseClient {
  final _api = FakeMatrixApi();
  final media = <String, List<int>>{};
  final sent = <String, Map<String, Object?>>{};
  var _next = 0;

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final path = request.url.path;
    http.StreamedResponse json(Object body) => http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
    );
    if (path.contains('/upload')) {
      final bytes = await request.finalize().toBytes();
      final id = 'm${_next++}';
      media[id] = bytes;
      return json({'content_uri': 'mxc://fakeServer.notExisting/$id'});
    }
    if (path.contains('/download/')) {
      final bytes = media[path.split('/').last] ?? const <int>[];
      return http.StreamedResponse(Stream.value(bytes), 200);
    }
    if (path.endsWith('/messages')) {
      return json({'chunk': <Object>[], 'start': 'old'});
    }
    if (request.method == 'PUT' && path.contains('/send/m.room.message/')) {
      final txid = Uri.decodeComponent(path.split('/').last);
      final body = await request.finalize().bytesToString();
      sent[txid] = jsonDecode(body) as Map<String, Object?>;
      return json({'event_id': '\$sent-$txid'});
    }
    return _api.send(request);
  }
}

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

Uint8List _jpeg(int w, int h) => img.encodeJpg(img.Image(width: w, height: h));

Uint8List _gif(int w, int h) {
  final a = img.Image(width: w, height: h)..clear(img.ColorRgb8(200, 30, 30));
  final b = img.Image(width: w, height: h)..clear(img.ColorRgb8(30, 30, 200));
  a.addFrame(b);
  return img.encodeGif(a);
}

void main() {
  late Client client;
  late _Server server;
  late Room room;
  late Directory folder;

  setUp(() async {
    // The app's settings, as the chat list tests set them.
    final fake = await setUpFakeChatList('multi media settings');
    tearDownFakeChatList(fake);
    sqfliteFfiInit();
    server = _Server();
    client = Client(
      'multi media send',
      httpClient: server,
      database: await MatrixSdkDatabase.init(
        'multi media send',
        database: await databaseFactoryFfi.openDatabase(inMemoryDatabasePath),
        sqfliteFactory: databaseFactoryFfi,
      ),
    );
    await client.init(
      newHomeserver: Uri.parse('https://fakeserver.notexisting'),
      newDeviceID: 'ABCD1234',
      newDeviceName: 'multi media send',
      newToken: '1234',
      newUserID: '@test:fakeServer.notExisting',
    );
    client.backgroundSync = false;
    // A plain, unencrypted room with the user in it, as a bridge portal is.
    const roomId = '!imessage:fakeServer.notExisting';
    await client.handleSync(
      SyncUpdate(
        nextBatch: 'room',
        rooms: RoomsUpdate(
          join: {
            roomId: JoinedRoomUpdate(
              state: [
                MatrixEvent(
                  type: EventTypes.RoomCreate,
                  content: {},
                  senderId: client.userID!,
                  stateKey: '',
                  eventId: r'$create',
                  originServerTs: DateTime(2026),
                ),
                MatrixEvent(
                  type: EventTypes.RoomMember,
                  content: {'membership': 'join'},
                  senderId: client.userID!,
                  stateKey: client.userID,
                  eventId: r'$me',
                  originServerTs: DateTime(2026),
                ),
                MatrixEvent(
                  type: EventTypes.RoomMember,
                  content: {'membership': 'join', 'displayname': 'Ana'},
                  senderId: '@imessage_ana:fakeServer.notExisting',
                  stateKey: '@imessage_ana:fakeServer.notExisting',
                  eventId: r'$ana',
                  originServerTs: DateTime(2026),
                ),
              ],
              timeline: TimelineUpdate(
                events: [
                  MatrixEvent(
                    type: EventTypes.Message,
                    content: {'msgtype': 'm.text', 'body': 'Send them over'},
                    senderId: '@imessage_ana:fakeServer.notExisting',
                    eventId: r'$hello',
                    originServerTs: DateTime(2026),
                  ),
                ],
                prevBatch: 'old',
              ),
            ),
          },
        ),
      ),
    );
    room = client.getRoomById(roomId)!;
    folder = Directory.systemTemp.createTempSync('seam_multi_media');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() {
    MxcImage.clearCache(room.id);
    folder.deleteSync(recursive: true);
  });

  XFile file(String name, Uint8List bytes, String mime) {
    final f = File('${folder.path}/$name')..writeAsBytesSync(bytes);
    return XFile(f.path, name: name, mimeType: mime);
  }

  Future<void> settle(WidgetTester tester, [int rounds = 8]) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 200));
    }
  }

  /// Rings that show over a picture, and those that show on their own.
  List<String> problems(WidgetTester tester) {
    final out = <String>[];
    for (final e in find.byType(MediaSendingIndicator).evaluate()) {
      final ind = e.widget as MediaSendingIndicator;
      AnimatedScale? scale;
      void visit(Element child) {
        if (child.widget is AnimatedScale) {
          scale = child.widget as AnimatedScale;
          return;
        }
        child.visitChildren(visit);
      }

      e.visitChildren(visit);
      if ((scale?.scale ?? 0) > 0 && ind.event.status != EventStatus.sending) {
        out.add('ring on ${ind.event.eventId} (${ind.event.status})');
      }
    }
    // A progress indicator that is neither a sending ring nor the status
    // line's small mark stands in for a picture on its own.
    for (final e in find.byType(CircularProgressIndicator).evaluate()) {
      var inRing = false;
      e.visitAncestorElements((a) {
        if (a.widget is MediaProgressDisc) inRing = true;
        return !inRing;
      });
      final size = (e.renderObject as RenderBox).size;
      if (!inRing && size.width > 14) out.add('bare spinner $size');
    }
    return out;
  }

  testWidgets('two photos, one a GIF, and a movie, then the bridge edits', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(412 * 2.625, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      initialLocation: '/chat',
      routes: [
        GoRoute(
          path: '/chat',
          builder: (_, _) => ChatPage(roomId: room.id),
        ),
      ],
    );
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _Matrix(client, prefs),
        child: MaterialApp.router(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          routerConfig: router,
        ),
      ),
    );
    await settle(tester);

    final seen = <String>{};
    // Started in the real zone, so it runs on whenever the test waits for
    // real time, while the frames are pumped in between.
    var done = false;
    await tester.runAsync(() async {
      sendAttachments(
        room: room,
        files: [
          file('photo.jpg', _jpeg(40, 30), 'image/jpeg'),
          file('funny.gif', _gif(40, 40), 'image/gif'),
          file(
            'movie.mp4',
            Uint8List.fromList(List.filled(64, 1)),
            'video/mp4',
          ),
        ],
        videoPoster: (_) async => _jpeg(16, 9),
      ).whenComplete(() => done = true);
    });
    for (var i = 0; i < 60 && !done; i++) {
      await settle(tester, 1);
      seen.addAll(problems(tester).where((p) => p.startsWith('bare')));
    }
    expect(done, isTrue, reason: 'the send finished');
    await settle(tester);
    expect(server.sent, hasLength(3), reason: 'all three sent');
    expect(problems(tester), isEmpty, reason: 'once sent');

    // The server's copies, as the next sync brings them.
    var n = 0;
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'echo',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                timeline: TimelineUpdate(
                  events: [
                    for (final MapEntry(key: txid, value: content)
                        in server.sent.entries)
                      MatrixEvent(
                        type: EventTypes.Message,
                        content: content,
                        senderId: client.userID!,
                        eventId: '\$sent-$txid',
                        originServerTs: DateTime.now().add(
                          Duration(seconds: n++),
                        ),
                        unsigned: {'transaction_id': txid},
                      ),
                  ],
                ),
              ),
            },
          ),
        ),
      ),
    );
    await settle(tester);
    expect(problems(tester), isEmpty, reason: 'once synced');

    // The bridge swaps each file (and the movie's thumbnail) by an edit.
    final edits = <MatrixEvent>[];
    for (final MapEntry(key: txid, value: content) in server.sent.entries) {
      final id = 'x${n++}';
      server.media[id] = server.media.values.first;
      final info = Map<String, Object?>.from(content['info'] as Map);
      if (info.containsKey('thumbnail_url')) {
        info['thumbnail_url'] = 'mxc://fakeServer.notExisting/$id';
      }
      final newContent = {
        ...content,
        'url': 'mxc://fakeServer.notExisting/$id',
        'info': info,
      };
      edits.add(
        MatrixEvent(
          type: EventTypes.Message,
          content: {
            ...newContent,
            'm.new_content': newContent,
            'm.relates_to': {
              'rel_type': 'm.replace',
              'event_id': '\$sent-$txid',
            },
          },
          senderId: client.userID!,
          eventId: '\$edit-$id',
          originServerTs: DateTime.now().add(Duration(seconds: n)),
        ),
      );
    }
    await tester.runAsync(
      () => client.handleSync(
        SyncUpdate(
          nextBatch: 'edits',
          rooms: RoomsUpdate(
            join: {
              room.id: JoinedRoomUpdate(
                timeline: TimelineUpdate(events: edits),
              ),
            },
          ),
        ),
      ),
    );
    await settle(tester);
    expect(problems(tester), isEmpty, reason: 'after the edits');
    expect(seen, isEmpty, reason: 'while sending');
    expect(find.byType(ImageBubble), findsNWidgets(2));
    expect(find.byType(EventVideoPlayer), findsOneWidget);
  });
}
