// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat_list/chat_list_item.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'chat_list_fakes.dart';

/// Where a preview's icon sits in its plain text. The user's own message
/// also starts with one, for its status icon before "You:".
const _icon = '￼';
const _me = '@me:x';
const _url = 'https://scrolly.312.dev/join/e424660b?p=QmFz';

void main() {
  late FakeChatListClient client;
  var rooms = 0;

  setUp(() async {
    client = await setUpFakeChatList('media preview test');
  });

  tearDown(() => tearDownFakeChatList(client));

  void member(Room room, String id, String name) => room.setState(
    StrippedStateEvent(
      type: EventTypes.RoomMember,
      content: {'membership': 'join', 'displayname': name},
      senderId: id,
      stateKey: id,
    ),
  );

  /// A chat whose newest event is [content] from [sender]: a direct chat
  /// with Khai, or a group with Harrison in it when [group] is set.
  Room chat(
    String sender,
    Map<String, Object?> content, {
    bool group = false,
    String type = EventTypes.Message,
    int unread = 0,
    bool redacted = false,
  }) {
    final id = '!r${rooms++}:x';
    final room = group
        ? addFakeChat(client, id, 'Squad', notificationCount: unread)
        : addFakeChat(
            client,
            id,
            'Khai Atwi',
            partner: '@khai:x',
            notificationCount: unread,
          );
    member(room, _me, 'Grayson Adams');
    member(room, '@harrison:x', 'Harrison Young');
    room.lastEvent = Event(
      content: content,
      type: type,
      eventId: '\$$id-last',
      senderId: sender,
      originServerTs: DateTime(2026),
      room: room,
      unsigned: redacted
          ? {
              'redacted_because': {
                'type': EventTypes.Redaction,
                'sender': sender,
                'event_id': '\$redaction',
                'origin_server_ts': 0,
                'content': {},
              },
            }
          : null,
    );
    return room;
  }

  Future<void> show(WidgetTester tester, Room room) async {
    final prefs = await SharedPreferences.getInstance();
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: ListView(children: [ChatListItem(room, onTap: () {})]),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The texts the row shows, an icon in a text as [_icon].
  List<String> texts(WidgetTester tester) => tester
      .widgetList<Text>(find.byType(Text))
      .map((text) => text.data ?? text.textSpan!.toPlainText())
      .toList();

  /// The text widget of the preview, the one that starts with [start].
  Text previewText(WidgetTester tester, String start) => tester
      .widgetList<Text>(find.byType(Text))
      .singleWhere(
        (text) => (text.data ?? text.textSpan!.toPlainText()).startsWith(start),
      );

  group('links', () {
    testWidgets('a lone link shows the link icon and no 🔗', (tester) async {
      await show(
        tester,
        chat(_me, {
          'msgtype': MessageTypes.Text,
          'body': _url,
          'format': 'org.matrix.custom.html',
          'formatted_body': '<a href="$_url">$_url</a>',
        }),
      );
      expect(
        texts(tester),
        contains('${_icon}You: ${_icon}scrolly.312.dev/join/e424660b?p=QmFz'),
      );
      expect(find.byIcon(Icons.link), findsOneWidget);
      expect(texts(tester).where((t) => t.contains('🔗')), isEmpty);
    });

    testWidgets('a lone link without HTML shows the same', (tester) async {
      await show(
        tester,
        chat(_me, {'msgtype': MessageTypes.Text, 'body': _url}),
      );
      expect(
        texts(tester),
        contains('${_icon}You: ${_icon}scrolly.312.dev/join/e424660b?p=QmFz'),
      );
      expect(find.byIcon(Icons.link), findsOneWidget);
    });

    testWidgets('a link inside a sentence stays text, without 🔗', (
      tester,
    ) async {
      await show(
        tester,
        chat(_me, {
          'msgtype': MessageTypes.Text,
          'body': 'see https://x.org now',
          'format': 'org.matrix.custom.html',
          'formatted_body': 'see <a href="https://x.org">https://x.org</a> now',
        }),
      );
      expect(texts(tester), contains('${_icon}You: see https://x.org now'));
      expect(find.byIcon(Icons.link), findsNothing);
    });

    testWidgets('a 🔗 the sender typed stays', (tester) async {
      await show(
        tester,
        chat(_me, {
          'msgtype': MessageTypes.Text,
          'body': '🔗 links below',
          'format': 'org.matrix.custom.html',
          'formatted_body': '🔗 links <b>below</b>',
        }),
      );
      expect(texts(tester), contains('${_icon}You: 🔗 links below'));
    });
  });

  group('media', () {
    testWidgets('a photo from the partner reads Photo, with no emoji', (
      tester,
    ) async {
      await show(
        tester,
        chat('@khai:x', {
          'msgtype': MessageTypes.Image,
          'body': 'PXL_1.jpg',
          'filename': 'PXL_1.jpg',
        }),
      );
      expect(texts(tester), contains('${_icon}Photo'));
      expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
      expect(texts(tester).where((t) => t.contains('🖼')), isEmpty);
    });

    testWidgets('my own photo does not repeat my name', (tester) async {
      await show(
        tester,
        chat(_me, {
          'msgtype': MessageTypes.Image,
          'body': 'PXL_1.jpg',
          'filename': 'PXL_1.jpg',
        }),
      );
      expect(texts(tester), contains('${_icon}You: ${_icon}Photo'));
      expect(texts(tester).where((t) => t.contains('Grayson')), isEmpty);
    });

    testWidgets('a caption replaces Photo, after the sender in a group', (
      tester,
    ) async {
      await show(
        tester,
        chat('@harrison:x', {
          'msgtype': MessageTypes.Image,
          'body': 'Sunset from the roof',
          'filename': 'IMG_4410.jpg',
        }, group: true),
      );
      expect(
        texts(tester),
        contains('Harrison Young: ${_icon}Sunset from the roof'),
      );
      expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
    });

    testWidgets('a GIF reads GIF', (tester) async {
      await show(
        tester,
        chat('@khai:x', {
          'msgtype': MessageTypes.Image,
          'body': 'giphy.gif',
          'filename': 'giphy.gif',
          'info': {'mimetype': 'image/gif'},
        }),
      );
      expect(texts(tester), contains('${_icon}GIF'));
      expect(find.byIcon(Icons.gif_box_outlined), findsOneWidget);
    });

    testWidgets('a video shows its length', (tester) async {
      await show(
        tester,
        chat('@khai:x', {
          'msgtype': MessageTypes.Video,
          'body': 'VID.mp4',
          'filename': 'VID.mp4',
          'info': {'duration': 48000},
        }),
      );
      expect(texts(tester), contains('${_icon}Video 0:48'));
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    });

    testWidgets('a voice message shows its length', (tester) async {
      await show(
        tester,
        chat('@khai:x', {
          'msgtype': MessageTypes.Audio,
          'body': 'Voice message.ogg',
          'filename': 'Voice message.ogg',
          'org.matrix.msc3245.voice': {},
          'info': {'duration': 12000},
        }),
      );
      expect(texts(tester), contains('${_icon}Voice message 0:12'));
      expect(find.byIcon(Icons.mic_none_outlined), findsOneWidget);
    });

    testWidgets('an audio file shows its name', (tester) async {
      await show(
        tester,
        chat('@khai:x', {
          'msgtype': MessageTypes.Audio,
          'body': 'song.mp3',
          'filename': 'song.mp3',
        }),
      );
      expect(texts(tester), contains('${_icon}song.mp3'));
      expect(find.byIcon(Icons.headphones_outlined), findsOneWidget);
    });

    testWidgets('a file shows its name', (tester) async {
      await show(
        tester,
        chat('@khai:x', {
          'msgtype': MessageTypes.File,
          'body': 'Lease.pdf',
          'filename': 'Lease.pdf',
        }),
      );
      expect(texts(tester), contains('${_icon}Lease.pdf'));
      expect(find.byIcon(Icons.attach_file), findsOneWidget);
    });

    testWidgets('a sticker reads Sticker', (tester) async {
      await show(
        tester,
        chat(
          '@harrison:x',
          {'body': 'thumbs up', 'url': 'mxc://x/y'},
          type: EventTypes.Sticker,
          group: true,
        ),
      );
      expect(texts(tester), contains('Harrison Young: ${_icon}Sticker'));
      expect(find.byIcon(Icons.sticky_note_2_outlined), findsOneWidget);
    });

    testWidgets('a location reads Location', (tester) async {
      await show(
        tester,
        chat('@khai:x', {
          'msgtype': MessageTypes.Location,
          'body': 'Location',
          'geo_uri': 'geo:41.88,-87.62',
        }),
      );
      expect(texts(tester), contains('${_icon}Location'));
      expect(find.byIcon(Icons.location_on_outlined), findsOneWidget);
    });

    testWidgets('a bridge placeholder reads as the photo it stands for', (
      tester,
    ) async {
      await show(
        tester,
        chat('@gmessages_15551234567:x', {
          'msgtype': MessageTypes.Notice,
          'body': 'Waiting for attachment PXL_1.jpg',
          'fi.mau.gmessages.media_pending': true,
        }),
      );
      // The ghost is not the chat's partner here, so its name leads.
      expect(texts(tester), contains('Gmessages 15551234567: ${_icon}Photo'));
      expect(find.byIcon(Icons.photo_outlined), findsOneWidget);
      expect(texts(tester).where((t) => t.contains('Waiting')), isEmpty);
    });

    testWidgets('a bridge placeholder for a video reads Video', (tester) async {
      await show(
        tester,
        chat('@gmessages_15551234567:x', {
          'msgtype': MessageTypes.Notice,
          'body': 'Waiting for attachment PXL_2.mp4',
          'fi.mau.gmessages.media_pending': true,
        }),
      );
      expect(texts(tester), contains('Gmessages 15551234567: ${_icon}Video'));
      expect(find.byIcon(Icons.videocam_outlined), findsOneWidget);
    });

    testWidgets('an attachment the bridge failed to fetch says so', (
      tester,
    ) async {
      await show(
        tester,
        chat('@gmessages_15551234567:x', {
          'msgtype': MessageTypes.Notice,
          'body': 'Failed to transfer attachment PXL_3.jpg',
        }),
      );
      expect(
        texts(tester),
        contains("Gmessages 15551234567: ${_icon}Photo didn't arrive"),
      );
      expect(find.byIcon(Icons.broken_image_outlined), findsOneWidget);
    });

    testWidgets('the same notice from another sender stays text', (
      tester,
    ) async {
      await show(
        tester,
        chat('@whatsappbot:x', {
          'msgtype': MessageTypes.Notice,
          'body': 'Waiting for attachment PXL_1.jpg',
        }),
      );
      expect(
        texts(tester),
        contains('Whatsappbot: Waiting for attachment PXL_1.jpg'),
      );
      expect(find.byIcon(Icons.photo_outlined), findsNothing);
    });

    testWidgets('a removed photo shows no media icon', (tester) async {
      await show(
        tester,
        chat('@khai:x', {
          'msgtype': MessageTypes.Image,
          'body': 'PXL_1.jpg',
        }, redacted: true),
      );
      expect(find.byIcon(Icons.photo_outlined), findsNothing);
    });
  });

  testWidgets('an unread preview keeps two lines and its icon the text color', (
    tester,
  ) async {
    await show(
      tester,
      chat(
        '@harrison:x',
        {
          'msgtype': MessageTypes.Image,
          'body': 'Sunset from the roof',
          'filename': 'IMG_4410.jpg',
        },
        group: true,
        unread: 2,
      ),
    );
    final text = previewText(tester, 'Harrison Young: ');
    expect(text.maxLines, 2);
    final icon = tester.widget<Icon>(find.byIcon(Icons.photo_outlined));
    expect(icon.color, text.style!.color);
    expect(icon.size, 18);
  });

  testWidgets('a text message reads as before', (tester) async {
    await show(
      tester,
      chat(_me, {'msgtype': MessageTypes.Text, 'body': 'Test'}),
    );
    expect(texts(tester), contains('${_icon}You: Test'));
    expect(previewText(tester, '${_icon}You: ').maxLines, 1);
  });
}
