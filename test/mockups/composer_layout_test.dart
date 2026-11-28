// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

// Screenshots the real composer of an open chat, attach button leading and
// emoji button trailing, at a Windows width (1000, with the system emoji
// picker) and a phone width (412, without one), dark and light, empty,
// typing and with three lines, to build/composer_layout/<theme>_<width>_
// <state>.png:
//
//   flutter test test/mockups/composer_layout_test.dart

import 'dart:io';
import 'dart:ui' as ui;

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/chat.dart';
import 'package:fluffychat/pages/chat/chat_input_row.dart';
import 'package:fluffychat/utils/native_emoji_picker.dart';
import 'package:fluffychat/widgets/matrix.dart';
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

const _ghost = '@imessage_drew:x';
const _seed = Color(0xFF1A5AD7);

class _Matrix extends FakeMatrix {
  _Matrix(super.fakeClient, super.prefs);

  @override
  bool get isMultiAccount => false;
}

void main() {
  late FakeChatListClient client;
  late FakeChatListRoom room;

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
    expect(icons.existsSync(), isTrue, reason: icons.path);
    final iconLoader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(icons.readAsBytesSync())));
    await iconLoader.load();
  });

  setUp(() async {
    client = await setUpFakeChatList('composer layout');
    room = addFakeChat(client, '!imsg:x', 'Drew', partner: _ghost);
    room.setState(
      StrippedStateEvent(
        type: 'm.bridge',
        content: {
          'bridgebot': '@imessagebot:x',
          'protocol': {'id': 'imessage', 'displayname': 'iMessage'},
        },
        senderId: '@imessagebot:x',
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
    NativeEmojiPicker.debugSupported = null;
    tearDownFakeChatList(client);
  });

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  for (final brightness in Brightness.values) {
    for (final width in [1000.0, 412.0]) {
      testWidgets('composer layout, ${brightness.name}, ${width.toInt()}', (
        tester,
      ) async {
        final out = Directory('build/composer_layout')
          ..createSync(recursive: true);
        final phone = width < 600;
        NativeEmojiPicker.debugSupported = !phone;
        tester.view.physicalSize = Size(width * 2, (phone ? 915 : 700) * 2);
        tester.view.devicePixelRatio = 2;
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
                  builder: (_, _) => ChatPage(roomId: room.id),
                ),
              ],
            ),
          ],
        );
        await tester.pumpWidget(
          RepaintBoundary(
            key: const ValueKey('shot'),
            child: Provider<MatrixState>.value(
              value: _Matrix(client, prefs),
              child: MaterialApp.router(
                localizationsDelegates: L10n.localizationsDelegates,
                supportedLocales: L10n.supportedLocales,
                routerConfig: router,
                builder: (context, child) => Theme(
                  data: FluffyThemes.buildTheme(context, brightness, _seed),
                  child: child!,
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
        router.push('/chat');
        await settle(tester);
        final chat = tester.state<ChatController>(
          find.byType(ChatPageWithRoom),
        );

        Future<void> capture(String state) async {
          final composer = tester.getRect(find.byType(ChatComposer));
          final boundary = tester.renderObject<RenderRepaintBoundary>(
            find.byKey(const ValueKey('shot')),
          );
          await tester.runAsync(() async {
            final image = await boundary.toImage(pixelRatio: 2);
            final bytes = await image.toByteData(
              format: ui.ImageByteFormat.png,
            );
            image.dispose();
            final full = img.decodePng(bytes!.buffer.asUint8List())!;
            final top = ((composer.top - 24) * 2).round().clamp(0, full.height);
            final bottom = ((composer.bottom + 24) * 2).round().clamp(
              0,
              full.height,
            );
            final crop = img.copyCrop(
              full,
              x: 0,
              y: top,
              width: full.width,
              height: bottom - top,
            );
            File(
              '${out.path}/${brightness.name}_${width.toInt()}_$state.png',
            ).writeAsBytesSync(img.encodePng(crop));
          });
        }

        expect(
          find.byKey(const ValueKey('composer-emoji')),
          phone ? findsNothing : findsOneWidget,
        );
        await capture('empty');
        chat.sendController.text = 'Waffle House at 9?';
        chat.inputTextIsEmpty.value = false;
        await settle(tester);
        await capture('typing');
        chat.sendController.text =
            'Waffle House at 9?\nBring cash, the card reader is down\n'
            'And tell Sam';
        await settle(tester);
        expect(
          tester.getSize(find.byType(ChatInputRow)).height,
          greaterThan(ChatInputRow.height),
        );
        await capture('multiline');
      });
    }
  }
}
