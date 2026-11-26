// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/android_direct_share.dart';
import 'package:fluffychat/utils/share_items.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

/// A chat a Direct Share picked opens with the share staged in its
/// composer, and sends nothing until the user does.
void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;
  final returns = <Object?>[];
  const shareChannel = MethodChannel('chat.fluffy.fluffychat/share');

  setUp(() async {
    client = await setUpFakeChatList('chat share staging');
    room = addFakeChat(client, '!gray:x', 'Gray Adams', partner: '@gray:x');
    returns.clear();
    AndroidDirectShare.debugIsAndroid = true;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(shareChannel, (call) async {
      if (call.method == 'returnToSourceApp') returns.add(call.arguments);
      return null;
    });
    // The chat page keeps the screen on while it is open.
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  tearDown(() {
    AndroidDirectShare.debugIsAndroid = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(shareChannel, null);
    tearDownFakeChatList(client);
  });

  Future<GoRouter> pump(WidgetTester tester, SharedDraft share) async {
    tester.view.physicalSize = const Size(1200, 2400);
    tester.view.devicePixelRatio = 3;
    addTearDown(tester.view.reset);
    final prefs = await SharedPreferences.getInstance();
    final router = GoRouter(
      routes: [
        GoRoute(
          path: '/',
          builder: (_, _) => const Scaffold(body: Text('chat list')),
          routes: [
            GoRoute(
              path: 'chat',
              builder: (_, _) => ChatPage(roomId: room.id, share: share),
            ),
          ],
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
    await tester.pumpAndSettle();
    router.push('/chat');
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
    return router;
  }

  testWidgets('files are staged as attachments and text goes in the field; '
      'back sends nothing and returns to the sharing app', (tester) async {
    final photo = XFile('/tmp/photo.jpg');
    await pump(
      tester,
      SharedDraft([
        FileShareItem(photo),
        TextShareItem('https://example.org'),
      ], fromShareIntent: true),
    );
    final chat = tester.state<ChatController>(find.byType(ChatPageWithRoom));
    expect(chat.pendingAttachments, [photo]);
    expect(chat.sendController.text, 'https://example.org');
    expect(returns, isEmpty);

    await tester.tap(find.byType(BackButton));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 200));
    }
    expect(find.text('chat list'), findsOneWidget);
    expect(returns, [
      {'toast': null},
    ]);
  });
}
