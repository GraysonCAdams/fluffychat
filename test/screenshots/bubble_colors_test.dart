// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../pages/chat_list/chat_list_fakes.dart';

/// Writes the chat peek of an iMessage chat and of a plain Matrix group,
/// light and dark, to `build/bubble_colors/`, for checking the user's own
/// bubbles by eye.
final _out = Directory('build/bubble_colors');

void main() {
  late FakeChatListClient client;

  setUpAll(() async {
    _out.createSync(recursive: true);
    final loader = FontLoader('GoogleSansFlex');
    for (final weight in ['Regular', 'Medium', 'SemiBold', 'Bold']) {
      final file = File(
        'assets/fonts/google_sans_flex/GoogleSansFlex-$weight.ttf',
      );
      loader.addFont(
        Future.value(ByteData.sublistView(file.readAsBytesSync())),
      );
    }
    await loader.load();
  });

  setUp(() async {
    client = await setUpFakeChatList('bubble colour screenshots');
    addFakeChat(
      client,
      '!imsg:x',
      'Harrison Young',
      partner: '@imessage_harrison:x',
      lastMessageTime: DateTime(2026, 1, 5),
    ).setMessages(
      [
        'Are we still on for Friday?',
        'Yes! 7 at the usual place',
        'Perfect',
        'I will bring the board games',
      ],
      partner: '@imessage_harrison:x',
      end: DateTime(2026, 1, 5, 18),
    );
    addFakeChat(
      client,
      '!grp:x',
      'Book club',
      lastMessageTime: DateTime(2026, 1, 2),
    ).setMessages([
      'Who has finished the book?',
      'Just did, the ending got me',
      'No spoilers please',
      'My lips are sealed until Sunday',
    ]);
  });

  tearDown(() => tearDownFakeChatList(client));

  for (final brightness in Brightness.values) {
    for (final (name, file) in [
      ('Harrison Young', 'imessage'),
      ('Book club', 'plain_matrix'),
    ]) {
      testWidgets('peek $file ${brightness.name}', (tester) async {
        tester.view.physicalSize = const Size(1080, 2400);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.reset);
        await pumpFakeChatList(tester, client, brightness: brightness);
        await tester.longPress(find.text(name));
        await tester.pumpAndSettle();
        var boundary = tester.renderObject(find.byType(Navigator).first);
        while (!boundary.isRepaintBoundary) {
          boundary = boundary.parent!;
        }
        final layer = boundary.debugLayer! as OffsetLayer;
        final bytes = await tester.runAsync(() async {
          final image = await layer.toImage(
            boundary.paintBounds,
            pixelRatio: tester.view.devicePixelRatio,
          );
          return image.toByteData(format: ui.ImageByteFormat.png);
        });
        File(
          '${_out.path}/peek_${file}_${brightness.name}.png',
        ).writeAsBytesSync(bytes!.buffer.asUint8List());
        await finishFakeChatList(tester, client);
      });
    }
  }
}
