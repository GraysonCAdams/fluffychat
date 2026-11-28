// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/events/image_bubble.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;

  // The phone's layout, whatever the machine running the tests.
  setUpAll(() => ImageViewer.debugDesktopLayout = false);
  tearDownAll(() => ImageViewer.debugDesktopLayout = null);

  setUp(() async {
    client = await setUpFakeChatList('edited media chat');
    room = addFakeChat(client, '!fam:x', 'Family', partner: '@bridge:x');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
          (_) async =>
              const StandardMessageCodec().encodeMessage(<Object?>[null]),
        );
  });

  tearDown(() => tearDownFakeChatList(client));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> receive(WidgetTester tester, List<MatrixEvent> events) async {
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
    await settle(tester);
  }

  final start = DateTime.now().subtract(const Duration(minutes: 5));

  /// The text a Google Messages bridge sends while an attachment is still
  /// downloading, as Synapse stored it.
  MatrixEvent placeholder(String id, String name, int s) => MatrixEvent(
    type: EventTypes.Message,
    content: {
      'msgtype': MessageTypes.Notice,
      'body': 'Waiting for attachment $name',
      'com.beeper.disappearing_timer': <String, Object?>{},
      'm.mentions': <String, Object?>{},
    },
    senderId: '@bridge:x',
    eventId: id,
    originServerTs: start.add(Duration(seconds: s)),
  );

  /// The edit a Google Messages bridge sends once the attachment of
  /// [target] has downloaded, as Synapse stored it.
  MatrixEvent edit(
    String id,
    String target,
    String name,
    String mxc,
    int s, {
    String msgtype = MessageTypes.Image,
  }) {
    final media = {
      'body': name,
      'info': {'mimetype': 'image/jpeg', 'size': 94584},
      'm.mentions': <String, Object?>{},
      'msgtype': msgtype,
      'url': mxc,
    };
    return MatrixEvent(
      type: EventTypes.Message,
      content: {
        ...media,
        'com.beeper.dont_render_edited': true,
        'm.new_content': media,
        'm.relates_to': {'event_id': target, 'rel_type': 'm.replace'},
      },
      senderId: '@bridge:x',
      eventId: id,
      originServerTs: start.add(Duration(seconds: s)),
    );
  }

  testWidgets('pictures a bridge sent as edits page in the viewer once each', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1080, 2400);
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
    await receive(tester, [
      placeholder('\$p1', 'IMG_1.jpeg', 0),
      placeholder('\$p2', 'IMG_2.jpeg', 1),
    ]);
    await receive(tester, [
      edit('\$e1a', '\$p1', 'IMG_1.jpeg', 'mxc://x/one-preview', 10),
      edit('\$e2a', '\$p2', 'IMG_2.jpeg', 'mxc://x/two-preview', 11),
    ]);
    // Each placeholder is edited twice: a preview, then the full picture.
    await receive(tester, [
      edit('\$e1', '\$p1', 'IMG_1.jpeg', 'mxc://x/one', 20),
      edit('\$e2', '\$p2', 'IMG_2.jpeg', 'mxc://x/two', 21),
    ]);
    // A clip, later, arrives the same way.
    await receive(tester, [placeholder('\$p3', 'clip.mp4', 30)]);
    await receive(tester, [
      edit(
        '\$e3',
        '\$p3',
        'clip.mp4',
        'mxc://x/clip',
        40,
        msgtype: MessageTypes.Video,
      ),
    ]);
    expect(find.byType(ImageBubble), findsNWidgets(2));
    // The bridge flags its edits com.beeper.dont_render_edited: they fill
    // in a placeholder, so no message reads as edited.
    expect(find.text('(edited)'), findsNothing);

    // The newer picture is the lower one.
    final bubbles = find.byType(ImageBubble).evaluate().toList()
      ..sort(
        (a, b) => tester
            .getTopLeft(find.byWidget(a.widget))
            .dy
            .compareTo(tester.getTopLeft(find.byWidget(b.widget)).dy),
      );
    await tester.tap(find.byWidget(bubbles.last.widget));
    await settle(tester);

    final viewer = find.byType(ImageViewer);
    expect(viewer, findsOneWidget);
    final state = tester.state<ImageViewerController>(viewer);
    // Each message once, with its final media, in chat order.
    expect(state.allEvents.map((e) => e.content['url']), [
      'mxc://x/one',
      'mxc://x/two',
      'mxc://x/clip',
    ]);
    expect(
      state.allEvents[state.pageController.initialPage].content['url'],
      'mxc://x/two',
    );
    Navigator.of(tester.element(viewer)).pop();
    await settle(tester);
  });
}
