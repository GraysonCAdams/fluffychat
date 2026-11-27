// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: implementation_imports, depend_on_referenced_packages

import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/events/link_preview_card.dart';
import 'package:fluffychat/pages/chat/events/message_content.dart';
import 'package:fluffychat/utils/link_preview.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:matrix/src/models/timeline_chunk.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../utils/message_search/search_test_client.dart';

class _FakeMatrix extends MatrixState {
  final Client fakeClient;

  _FakeMatrix(this.fakeClient);

  @override
  Client get client => fakeClient;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Client client;
  late Room room;

  setUpAll(() async {
    SharedPreferences.setMockInitialValues({});
    await AppSettings.init(loadWebConfigFile: false);
    client = await createSearchTestClient();
    room = client.rooms.firstWhere((room) => !room.isSpace);
  });

  setUp(clearServerLinkPreviewCache);

  Event textEvent(Map<String, Object?> extra) => Event(
    content: {
      'msgtype': 'm.text',
      'body': 'read this https://example.com/story',
      ...extra,
    },
    type: EventTypes.Message,
    eventId: '\$link',
    senderId: '@alice:example.org',
    originServerTs: DateTime(2026, 11, 27),
    room: room,
  );

  Future<void> pumpContent(WidgetTester tester, Event event) async {
    await tester.pumpWidget(
      Provider<MatrixState>.value(
        value: _FakeMatrix(client),
        child: MaterialApp(
          localizationsDelegates: L10n.localizationsDelegates,
          supportedLocales: L10n.supportedLocales,
          home: Scaffold(
            body: Center(
              child: MessageContent(
                event,
                timeline: Timeline(
                  room: room,
                  chunk: TimelineChunk(events: [event]),
                ),
                textColor: Colors.black,
                linkColor: Colors.blue,
                borderRadius: BorderRadius.zero,
                selected: false,
                bigEmojis: const {},
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('a bridged message shows the preview it carries', (tester) async {
    await pumpContent(
      tester,
      textEvent({
        beeperLinkPreviewsKey: [
          {
            'matched_url': 'https://example.com/story',
            'og:title': 'The story',
            'og:description': 'What happened next',
            'og:site_name': 'Example News',
          },
        ],
      }),
    );
    expect(find.byType(LinkPreviewCard), findsOneWidget);
    expect(find.text('The story'), findsOneWidget);
    expect(find.text('What happened next'), findsOneWidget);
    expect(find.text('Example News'), findsOneWidget);
  });

  testWidgets('an empty bridge list shows no card', (tester) async {
    await pumpContent(tester, textEvent({beeperLinkPreviewsKey: []}));
    expect(find.byType(LinkPreviewCard), findsNothing);
  });

  testWidgets('a link the server cannot preview shows no card', (tester) async {
    // The fake homeserver has no preview for this URL and answers 404.
    await pumpContent(tester, textEvent({}));
    expect(find.byType(LinkPreviewCard), findsNothing);
    expect(find.textContaining('example.com/story'), findsOneWidget);
  });
}
