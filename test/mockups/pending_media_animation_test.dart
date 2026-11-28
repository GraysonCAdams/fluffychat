// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

// Renders a Google Messages chat as the bridge delivers attachments, frame
// by frame at 30 fps, to PNG files under build/pending_media_animation/
// <theme>/, with the app's own theme, font, bubbles and motion:
//
//   flutter test test/mockups/pending_media_animation_test.dart
//   ffmpeg -framerate 30 -i build/pending_media_animation/dark/%04d.png \
//     -c:v libx264 -pix_fmt yuv420p anim_dark.mp4
//
// The photos are the CC0 ones in test/fixtures/pending_media, and each
// placeholder's preview is that same photo shrunk to about 60 pixels, as
// Google Messages makes it.

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/image_bubble.dart';
import 'package:fluffychat/pages/chat/events/pending_media_tile.dart';
import 'package:fluffychat/pages/chat/events/video_player.dart';
import 'package:fluffychat/utils/pending_media.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';
import '../utils/pending_media_fixtures.dart';

const _fixtures = 'test/fixtures/pending_media';
const _ghost = '@gmessages_15551234567:x';
const _frame = Duration(microseconds: 33333);

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

/// A photo from the fixtures, its size, and its preview as Google Messages
/// sends one: the same picture shrunk to about 60 pixels on its long side.
class _Photo {
  final Uint8List bytes;
  final int width;
  final int height;
  final Uint8List preview;

  _Photo._(this.bytes, this.width, this.height, this.preview);

  factory _Photo.load(String name) {
    final bytes = File('$_fixtures/$name').readAsBytesSync();
    final image = img.decodeJpg(bytes)!;
    final small = image.width >= image.height
        ? img.copyResize(image, width: 63)
        : img.copyResize(image, height: 63);
    return _Photo._(
      bytes,
      image.width,
      image.height,
      img.encodeJpg(small, quality: 70),
    );
  }
}

void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;
  var rooms = 0;

  setUpAll(() async {
    final loader = FontLoader('GoogleSansFlex');
    for (final weight in ['Regular', 'Medium']) {
      final file = File(
        'assets/fonts/google_sans_flex/GoogleSansFlex-$weight.ttf',
      );
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
    await loader.load();
    final icons = File(
      '${File(Platform.resolvedExecutable).parent.parent.parent.path}'
      '/material_fonts/MaterialIcons-Regular.otf',
    );
    if (icons.existsSync()) {
      final iconLoader = FontLoader('MaterialIcons')
        ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
      await iconLoader.load();
    }
  });

  setUp(() async {
    client = await setUpFakeChatList('pending media animation');
    room = addFakeChat(client, '!sms${++rooms}:x', 'Parla', partner: _ghost);
    // A Google Messages portal, so its bubbles take that network's colour.
    room.setState(
      StrippedStateEvent(
        type: 'm.bridge',
        content: {
          'bridgebot': '@gmessagesbot:x',
          'protocol': {'id': 'gmessages', 'displayname': 'Google Messages'},
        },
        senderId: '@gmessagesbot:x',
        stateKey: 'net/${room.id}',
      ),
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() {
    MxcImage.clearCache(room.id);
    tearDownFakeChatList(client);
  });

  for (final brightness in Brightness.values) {
    testWidgets('pending media animation, ${brightness.name}', (tester) async {
      final out = Directory('build/pending_media_animation/${brightness.name}')
        ..createSync(recursive: true);
      for (final file in out.listSync()) {
        file.deleteSync();
      }
      tester.view.physicalSize = const Size(412 * 2, 915 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);

      final onigiri = _Photo.load('onigiri.jpg');
      final dog = _Photo.load('dog_on_deck.jpg');
      final bulldog = _Photo.load('bulldog_life_jacket.jpg');

      var frameCount = 0;
      Future<void> capture() async {
        final boundary = tester.renderObject<RenderRepaintBoundary>(
          find.byKey(const ValueKey('shot')),
        );
        await tester.runAsync(() async {
          final image = await boundary.toImage(pixelRatio: 2);
          final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
          File(
            '${out.path}/${(frameCount++).toString().padLeft(4, '0')}.png',
          ).writeAsBytesSync(bytes!.buffer.asUint8List());
          image.dispose();
        });
      }

      /// Plays [duration] at 30 frames a second, capturing each frame.
      Future<void> play(Duration duration) async {
        final frames = (duration.inMicroseconds / _frame.inMicroseconds)
            .round();
        for (var i = 0; i < frames; i++) {
          await tester.pump(_frame);
          await capture();
        }
      }

      /// Lets the database and timeline take [events] in, without moving the
      /// clock, until [arrived] holds.
      Future<void> deliver(
        List<MatrixEvent> events,
        bool Function() arrived,
      ) async {
        await tester.runAsync(
          () => client.handleSync(
            SyncUpdate(
              nextBatch: 'b${events.first.eventId}',
              rooms: RoomsUpdate(
                join: {
                  room.id: JoinedRoomUpdate(
                    timeline: TimelineUpdate(events: events),
                  ),
                },
              ),
            ),
          ),
        );
        for (var i = 0; i < 200 && !arrived(); i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(arrived(), isTrue, reason: 'events ${events.first.eventId}');
      }

      var clock = DateTime.now().subtract(const Duration(minutes: 3));
      DateTime next() => clock = clock.add(const Duration(seconds: 20));

      MatrixEvent text(String id, String sender, String body) => MatrixEvent(
        type: EventTypes.Message,
        content: {'msgtype': MessageTypes.Text, 'body': body},
        senderId: sender,
        eventId: id,
        originServerTs: next(),
      );

      MatrixEvent placeholder(
        String id,
        String name, {
        _Photo? photo,
        String mimeType = 'image/jpeg',
      }) => MatrixEvent(
        type: EventTypes.Message,
        content: {
          'msgtype': MessageTypes.Notice,
          'body': 'Waiting for attachment $name',
          PendingMedia.pendingKey: true,
          if (photo != null)
            PendingMedia.rawDebugDataKey: rawDebugData([
              mediaContent(
                name: name,
                mimeType: mimeType,
                width: photo.width,
                height: photo.height,
                preview: photo.preview,
              ),
            ]),
        },
        senderId: _ghost,
        eventId: id,
        originServerTs: next(),
      );

      MatrixEvent edit(String id, String target, Map<String, Object?> media) {
        return MatrixEvent(
          type: EventTypes.Message,
          content: {
            ...media,
            'com.beeper.dont_render_edited': true,
            'm.new_content': media,
            'm.relates_to': {'event_id': target, 'rel_type': 'm.replace'},
          },
          senderId: _ghost,
          eventId: id,
          originServerTs: next(),
        );
      }

      int count(Type type) => find.byType(type).evaluate().length;

      room.setState(
        StrippedStateEvent(
          type: EventTypes.RoomMember,
          content: {'membership': 'join'},
          senderId: '@me:x',
          stateKey: '@me:x',
        ),
      );
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
        RepaintBoundary(
          key: const ValueKey('shot'),
          child: Provider<MatrixState>.value(
            value: _Matrix(client, prefs),
            child: MaterialApp.router(
              debugShowCheckedModeBanner: false,
              localizationsDelegates: L10n.localizationsDelegates,
              supportedLocales: L10n.supportedLocales,
              routerConfig: router,
              builder: (context, child) => Theme(
                data: FluffyThemes.buildTheme(context, brightness),
                child: child!,
              ),
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 50)),
        );
        await tester.pump(const Duration(milliseconds: 100));
      }

      // 1. A conversation already under way.
      await deliver(
        [
          text(r'$t1', _ghost, 'Lunch was so good today'),
          text(r'$t2', '@me:x', 'What did you get?'),
          text(r'$t3', _ghost, 'Spam onigiri. Sending a pic'),
        ],
        () => find
            .textContaining('Spam onigiri', findRichText: true)
            .evaluate()
            .isNotEmpty,
      );
      await tester.pump(const Duration(seconds: 1));
      await play(const Duration(milliseconds: 1000));

      // 2. The photo's placeholder: its blurred preview and the ring.
      final tiles = count(PendingMediaTile);
      await deliver([
        placeholder(r'$p1', 'PXL_20261127_121530.jpg', photo: onigiri),
      ], () => count(PendingMediaTile) > tiles);
      await play(const Duration(milliseconds: 2000));

      // 3. The bridge's edit brings the photo.
      MxcImage.prime(
        cacheName: room.id,
        cacheKey: r'$e1',
        bytes: onigiri.bytes,
      );
      final images = count(ImageBubble);
      await deliver([
        edit(r'$e1', r'$p1', {
          'msgtype': MessageTypes.Image,
          'body': 'PXL_20261127_121530.jpg',
          'info': {
            'mimetype': 'image/jpeg',
            'w': onigiri.width,
            'h': onigiri.height,
          },
          'url': 'mxc://x/onigiri',
        }),
      ], () => count(ImageBubble) > images);
      await play(const Duration(milliseconds: 1500));

      // 4. A video: its placeholder with the poster frame, then the video.
      await deliver([text(r'$t4', '@me:x', 'Ha, and the dog?')], () {
        return find
            .textContaining('and the dog', findRichText: true)
            .evaluate()
            .isNotEmpty;
      });
      await play(const Duration(milliseconds: 600));
      final videoTiles = count(PendingMediaTile);
      await deliver([
        placeholder(
          r'$p2',
          'PXL_20261127_121602.mp4',
          photo: dog,
          mimeType: 'video/mp4',
        ),
      ], () => count(PendingMediaTile) > videoTiles);
      await play(const Duration(milliseconds: 2000));
      MxcImage.prime(cacheName: room.id, cacheKey: r'$e2', bytes: dog.bytes);
      final videos = count(EventVideoPlayer);
      await deliver([
        edit(r'$e2', r'$p2', {
          'msgtype': MessageTypes.Video,
          'body': 'PXL_20261127_121602.mp4',
          'info': {
            'mimetype': 'video/mp4',
            'w': dog.width,
            'h': dog.height,
            'duration': 9000,
            'thumbnail_url': 'mxc://x/dog-poster',
            'thumbnail_info': {
              'mimetype': 'image/jpeg',
              'w': dog.width,
              'h': dog.height,
            },
          },
          'url': 'mxc://x/dog',
        }),
      ], () => count(EventVideoPlayer) > videos);
      await play(const Duration(milliseconds: 1500));

      // 5. A photo whose debug data the bridge left out: the plain tile.
      final plainTiles = count(PendingMediaTile);
      await deliver([
        placeholder(r'$p3', 'PXL_20261127_121644.jpg'),
      ], () => count(PendingMediaTile) > plainTiles);
      await play(const Duration(milliseconds: 2000));
      MxcImage.prime(
        cacheName: room.id,
        cacheKey: r'$e3',
        bytes: bulldog.bytes,
      );
      final bulldogs = count(ImageBubble);
      await deliver([
        edit(r'$e3', r'$p3', {
          'msgtype': MessageTypes.Image,
          'body': 'PXL_20261127_121644.jpg',
          'info': {
            'mimetype': 'image/jpeg',
            'w': bulldog.width,
            'h': bulldog.height,
          },
          'url': 'mxc://x/bulldog',
        }),
      ], () => count(ImageBubble) > bulldogs);
      await play(const Duration(milliseconds: 1500));

      // 6. One that never arrives.
      final failedTiles = count(PendingMediaTile);
      await deliver([
        MatrixEvent(
          type: EventTypes.Message,
          content: {
            'msgtype': MessageTypes.Notice,
            'body': 'Failed to transfer attachment PXL_20261127_121710.jpg',
          },
          senderId: _ghost,
          eventId: r'$p4',
          originServerTs: next(),
        ),
      ], () => count(PendingMediaTile) > failedTiles);
      await play(const Duration(milliseconds: 2000));

      expect(find.text('(edited)'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }
}
