// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer.dart';
import 'package:fluffychat/pages/image_viewer/image_viewer_view.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;

  setUp(() async {
    client = await setUpFakeChatList('media viewer');
    room = addFakeChat(client, '!mia:x', 'Mia', partner: '@mia:x');
  });

  tearDown(() => tearDownFakeChatList(client));

  /// Lets the database and media requests catch up.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 4; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 30)),
      );
      await tester.pump(const Duration(milliseconds: 150));
    }
  }

  Event picture(int i) => Event(
    content: {
      'msgtype': MessageTypes.Image,
      'body': 'IMG_$i.jpg',
      'url': 'mxc://x/picture$i',
      'info': {'w': 400, 'h': 300, 'mimetype': 'image/jpeg'},
    },
    type: EventTypes.Message,
    eventId: '\$picture$i',
    senderId: '@mia:x',
    originServerTs: DateTime(2026, 11, 27, 9, i),
    room: room,
  );

  final replied = <String>[];
  final shownInChat = <String>[];

  /// Opens the viewer on the middle of three pictures, in a chat that can
  /// answer and scroll to them.
  Future<ImageViewerController> open(WidgetTester tester) async {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 2.625;
    addTearDown(tester.view.reset);
    replied.clear();
    shownInChat.clear();
    final prefs = await SharedPreferences.getInstance();
    // Newest first, as a timeline holds them.
    final events = [picture(3), picture(2), picture(1)];
    final timeline = Timeline(
      room: room,
      chunk: TimelineChunk(events: events),
    );
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: FakeMatrix(client, prefs),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Builder(
            builder: (context) => Scaffold(
              body: Center(
                child: TextButton(
                  onPressed: () => Navigator.of(context).push(
                    PageRouteBuilder<void>(
                      opaque: false,
                      pageBuilder: (_, _, _) => ImageViewer(
                        events[1],
                        timeline: timeline,
                        outerContext: context,
                        onReply: (e) => replied.add(e.eventId),
                        onShowInChat: (e) => shownInChat.add(e.eventId),
                      ),
                    ),
                  ),
                  child: const Text('open'),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('open'));
    await settle(tester);
    return tester.state<ImageViewerController>(find.byType(ImageViewer));
  }

  /// Lets a single tap through once it can no longer be a double tap.
  Future<void> tapOnce(WidgetTester tester, Offset at) async {
    await tester.tapAt(at);
    await tester.pump(const Duration(milliseconds: 400));
    await settle(tester);
  }

  Offset middle(WidgetTester tester) =>
      tester.getCenter(find.byType(ImageViewer));

  testWidgets('pages through the chat media oldest first, from the tapped '
      'one', (tester) async {
    final viewer = await open(tester);
    expect(viewer.allEvents.map((e) => e.eventId), [
      '\$picture1',
      '\$picture2',
      '\$picture3',
    ]);
    expect(viewer.currentIndex, 1);

    await tester.fling(
      find.byType(PageView),
      const Offset(-600, 0),
      2000,
    );
    await settle(tester);
    expect(viewer.currentIndex, 2);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await settle(tester);
    expect(viewer.currentIndex, 1);
  });

  testWidgets('the thumbnail strip shows every picture and jumps to one', (
    tester,
  ) async {
    final viewer = await open(tester);
    final strip = find.byType(MediaThumbnailStrip);
    expect(strip, findsOneWidget);
    final thumbs = find.descendant(
      of: strip,
      matching: find.byType(GestureDetector),
    );
    expect(thumbs, findsNWidgets(3));
    await tester.tap(thumbs.first);
    await settle(tester);
    expect(viewer.currentIndex, 0);
  });

  testWidgets('a tap hides the bars and another brings them back', (
    tester,
  ) async {
    await open(tester);
    final close = find.byTooltip('Close');
    expect(close.hitTestable(), findsOneWidget);

    await tapOnce(tester, middle(tester));
    expect(close.hitTestable(), findsNothing);

    await tapOnce(tester, middle(tester));
    expect(close.hitTestable(), findsOneWidget);
  });

  testWidgets('a long drag down closes the viewer, a short one does not', (
    tester,
  ) async {
    await open(tester);
    await tester.timedDragFrom(
      middle(tester),
      const Offset(0, 60),
      const Duration(milliseconds: 600),
    );
    await settle(tester);
    expect(find.byType(ImageViewer), findsOneWidget);

    await tester.timedDragFrom(
      middle(tester),
      const Offset(0, 320),
      const Duration(milliseconds: 600),
    );
    await settle(tester);
    expect(find.byType(ImageViewer), findsNothing);
  });

  testWidgets('Escape closes the viewer', (tester) async {
    await open(tester);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(ImageViewer), findsNothing);
  });

  testWidgets('the actions are there and act on the picture shown', (
    tester,
  ) async {
    await open(tester);
    for (final label in ['Download', 'Reply', 'Forward', 'More']) {
      expect(
        find.byWidgetPredicate(
          (w) => w is Tooltip && (w.message ?? '').startsWith(label),
        ),
        findsWidgets,
        reason: label,
      );
    }

    await tester.tap(find.byTooltip('More'));
    await settle(tester);
    await tester.tap(find.text('Show in chat'));
    await settle(tester);
    expect(shownInChat, ['\$picture2']);
    expect(find.byType(ImageViewer), findsNothing);
  });

  testWidgets('reply answers the picture shown', (tester) async {
    await open(tester);
    await tester.tap(find.byTooltip('Reply'));
    await settle(tester);
    expect(replied, ['\$picture2']);
    expect(find.byType(ImageViewer), findsNothing);
  });
}
