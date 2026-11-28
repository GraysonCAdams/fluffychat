// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:convert';
import 'dart:io';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/utils/windows_clipboard.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:material_ui/material_ui.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../pages/chat_list/chat_list_fakes.dart';

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

const _gifUrl = 'https://media.tenor.com/abc/dance.gif';
final _gifBytes = Uint8List.fromList([...ascii.encode('GIF89a'), 1, 0, 1, 0]);
final _pngBytes = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0, //
]);

/// The system clipboard as the pasteboard plugin and the Windows clipboard
/// see it.
class _Clipboard {
  int sequence = 1;
  bool fromEmojiPanel = false;
  String? html;
  Uint8List? image;

  /// What the emoji panel (Win+.) writes when a GIF is picked: an HTML
  /// `<img>` linking the GIF and a bitmap of its first frame, tagged as the
  /// panel's.
  void writeFromEmojiPanel() {
    sequence++;
    fromEmojiPanel = true;
    html = '<img src="$_gifUrl">';
    image = _pngBytes;
  }

  /// A screenshot copied by any other app: a bitmap, no HTML.
  void writeImage() {
    sequence++;
    fromEmojiPanel = false;
    html = null;
    image = _pngBytes;
  }

  /// A GIF copied from a browser: the same HTML, not tagged as the panel's.
  void writeBrowserGif() {
    sequence++;
    fromEmojiPanel = false;
    html = '<img src="$_gifUrl">';
    image = _pngBytes;
  }
}

/// A GIF picked in the Windows emoji panel is staged once, whether the
/// panel's clipboard write is seen by the clipboard watcher, by a paste, or
/// both; an ordinary paste stages what it pastes once.
void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;
  late _Clipboard clipboard;
  var downloads = 0;

  setUp(() async {
    client = await setUpFakeChatList('emoji panel gif');
    room = addFakeChat(client, '!grp:x', 'Squad Goals');
    clipboard = _Clipboard();
    downloads = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(const MethodChannel('pasteboard'), (
      call,
    ) async {
      switch (call.method) {
        case 'html':
          return clipboard.html;
        case 'image':
          // On Windows the plugin hands the bitmap over as a temporary
          // file, which it deletes once read.
          final image = clipboard.image;
          if (image == null) return null;
          final file = File(
            '${Directory.systemTemp.createTempSync('paste').path}/image.png',
          )..writeAsBytesSync(image);
          return file.path;
        case 'files':
          return <String>[];
      }
      return null;
    });
    messenger.setMockMessageHandler(
      'dev.flutter.pigeon.wakelock_plus_platform_interface.WakelockPlusApi.toggle',
      (_) async => const StandardMessageCodec().encodeMessage(<Object?>[null]),
    );
  });

  tearDown(() {
    WindowsClipboard.debugSequenceNumber = null;
    WindowsClipboard.debugHoldsEmojiPanelContent = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('pasteboard'), null);
    tearDownFakeChatList(client);
  });

  /// Lets the clipboard watcher tick and the GIF download finish.
  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      WindowsClipboard.debugSequenceNumber = clipboard.sequence;
      WindowsClipboard.debugHoldsEmojiPanelContent = clipboard.fromEmojiPanel;
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<ChatController> open(WidgetTester tester) async {
    WindowsClipboard.debugSequenceNumber = clipboard.sequence;
    WindowsClipboard.debugHoldsEmojiPanelContent = false;
    tester.view.physicalSize = const Size(1000, 800);
    tester.view.devicePixelRatio = 1;
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
    final chat = tester.state<ChatController>(find.byType(ChatPageWithRoom));
    // The watcher runs while the composer has focus.
    chat.inputFocus.unfocus();
    await tester.pump();
    chat.inputFocus.requestFocus();
    await settle(tester);
    expect(chat.inputFocus.hasFocus, isTrue);
    return chat;
  }

  Future<void> paste(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(LogicalKeyboardKey.keyV);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
  }

  /// Runs [body] with GIF downloads answered locally.
  Future<void> withGifs(Future<void> Function() body) => http.runWithClient(
    body,
    () => MockClient((request) async {
      downloads++;
      if (request.url.toString() != _gifUrl) return http.Response('', 404);
      return http.Response.bytes(
        _gifBytes,
        200,
        headers: {'content-type': 'image/gif'},
      );
    }),
  );

  int gifs(ChatController chat) => chat.pendingAttachments
      .where((file) => file.mimeType == 'image/gif')
      .length;

  testWidgets('the emoji panel copies a GIF and pastes it: staged once', (
    tester,
  ) async {
    await withGifs(() async {
      final chat = await open(tester);
      clipboard.writeFromEmojiPanel();
      WindowsClipboard.debugSequenceNumber = clipboard.sequence;
      WindowsClipboard.debugHoldsEmojiPanelContent = true;
      await paste(tester);
      await settle(tester);
      expect(gifs(chat), 1);
      expect(chat.pendingAttachments, hasLength(1));
    });
  });

  testWidgets('the emoji panel writes the clipboard twice: staged once', (
    tester,
  ) async {
    await withGifs(() async {
      final chat = await open(tester);
      clipboard.writeFromEmojiPanel();
      await settle(tester);
      clipboard.writeFromEmojiPanel();
      await settle(tester);
      expect(gifs(chat), 1);
      expect(chat.pendingAttachments, hasLength(1));
    });
  });

  testWidgets('the same GIF picked again later is staged again', (
    tester,
  ) async {
    await withGifs(() async {
      final chat = await open(tester);
      clipboard.writeFromEmojiPanel();
      await settle(tester);
      expect(gifs(chat), 1);
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(seconds: 3)),
      );
      clipboard.writeFromEmojiPanel();
      await settle(tester);
      expect(gifs(chat), 2);
    });
  });

  testWidgets('Ctrl+V of an image stages it once', (tester) async {
    await withGifs(() async {
      final chat = await open(tester);
      clipboard.writeImage();
      await settle(tester);
      await paste(tester);
      await settle(tester);
      expect(chat.pendingAttachments, hasLength(1));
      expect(downloads, 0);
    });
  });

  testWidgets('Ctrl+V of a browser GIF stages it, and again when repeated', (
    tester,
  ) async {
    await withGifs(() async {
      final chat = await open(tester);
      clipboard.writeBrowserGif();
      await settle(tester);
      await paste(tester);
      await settle(tester);
      expect(gifs(chat), 1);
      await paste(tester);
      await settle(tester);
      expect(gifs(chat), 2);
    });
  });
}
