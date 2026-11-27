// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_picker.dart';
import 'package:fluffychat/pages/chat/gallery_picker/picked_media.dart';
import 'package:fluffychat/pages/chat/gallery_picker/send_preview.dart';
import 'package:fluffychat/pages/chat/gallery_picker/thumbnail_cache.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A 1x1 PNG.
final _png = base64Decode(
  'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8z8BQDwAEhQGAhKmMIQAAAABJRU5ErkJggg==',
);

void main() {
  const iMessageBlue = Color(0xFF1D8CF8);
  final send = find.byKey(const ValueKey('gallery_send'));

  /// The photo send screen with one picked photo and [caption] typed,
  /// its long press wired as the gallery picker wires it in an iMessage
  /// chat. [sent] gets each effect picked.
  Future<void> pumpPreview(
    WidgetTester tester, {
    required List<MessageEffect> sent,
    String caption = 'Sunset',
  }) async {
    tester.view.physicalSize = const Size(412, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final photo = XFile.fromData(
      Uint8List.fromList(_png),
      name: 'photo.png',
      path: '/picked/photo.png',
      mimeType: 'image/png',
    );
    final selection = MediaSelection()
      ..add(CapturedMedia(file: photo, isVideo: false, aspectRatio: 1));
    final captionController = TextEditingController(text: caption);
    addTearDown(captionController.dispose);
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        theme: ThemeData(brightness: Brightness.dark),
        home: Scaffold(
          body: Builder(
            builder: (context) => SendPreview(
              selection: selection,
              thumbnails: ThumbnailCache(),
              recipientName: 'Gray Adams',
              caption: captionController,
              sending: false,
              onClose: () {},
              onOpenCamera: () {},
              onSend: () {},
              sendColor: iMessageBlue,
              onSendColor: Colors.white,
              onSendLongPress: (color, onColor) => onSendLongPress(
                context,
                effectsAvailable: true,
                text: captionController.text,
                media: [photo],
                bubbleColor: color,
                onBubbleColor: onColor,
                send: sent.add,
                fallback: () {},
              ),
            ),
          ),
        ),
      ),
    );
    for (
      var i = 0;
      i < 50 && find.byType(SendPreview).evaluate().isEmpty;
      i++
    ) {
      await tester.pump(const Duration(milliseconds: 1));
    }
    await tester.pump();
  }

  testWidgets('the send button has the composer\'s colours', (tester) async {
    await pumpPreview(tester, sent: []);
    final button = tester.widget<IconButton>(send);
    final style = button.style!;
    expect(style.backgroundColor!.resolve({}), iMessageBlue);
    expect(style.foregroundColor!.resolve({}), Colors.white);
  });

  testWidgets('a long press opens the effect picker with the photo and its '
      'caption, and sends with the effect picked', (tester) async {
    final sent = <MessageEffect>[];
    await pumpPreview(tester, sent: sent);
    await tester.longPress(send);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    final picker = find.byType(MessageEffectPicker);
    expect(picker, findsOneWidget);
    // No tooltip answers the long press.
    expect(
      find.descendant(of: send, matching: find.byType(Tooltip)),
      findsNothing,
    );
    expect(find.text('Send'), findsNothing);
    expect(
      find.descendant(
        of: picker,
        matching: find.byKey(const ValueKey('effect_preview_media')),
      ),
      findsOneWidget,
    );
    expect(
      find.descendant(of: picker, matching: find.text('Sunset')),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 3));
    await tester.tap(find.byKey(const ValueKey('send_effect_slam')));
    await tester.pumpAndSettle();
    expect(sent, [MessageEffect.slam]);
  });

  testWidgets('a long press with only the photo opens the picker too', (
    tester,
  ) async {
    await pumpPreview(tester, sent: [], caption: '');
    await tester.longPress(send);
    await tester.pump();
    await tester.pump(const Duration(seconds: 1));
    expect(find.byType(MessageEffectPicker), findsOneWidget);
    await tester.pump(const Duration(seconds: 3));
  });
}
