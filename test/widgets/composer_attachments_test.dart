// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:typed_data';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/composer_attachments.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// A 1x1 PNG, standing in for a video's first frame.
final _frame = Uint8List.fromList(const [
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D, //
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01, //
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00, //
  0x0D, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0xF8, 0xCF, 0xC0, 0xF0, //
  0x1F, 0x00, 0x05, 0x00, 0x01, 0xFF, 0x89, 0x99, 0x3D, 0x1D, 0x00, 0x00, //
  0x00, 0x00, 0x49, 0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82, //
]);

void main() {
  Future<void> pump(
    WidgetTester tester,
    XFile file, {
    Future<Uint8List?> Function(XFile file)? poster,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Material(
            child: ComposerAttachmentStrip(
              files: [file],
              onRemove: (_) {},
              videoPoster: poster,
            ),
          ),
        ),
      ),
    );
    // The localizations load before the first frame with content.
    await tester.pumpAndSettle();
  }

  final placeholder = find.byKey(const ValueKey('video-placeholder'));
  final poster = find.byKey(const ValueKey('video-poster'));

  testWidgets('a staged video shows its first frame once it is read', (
    tester,
  ) async {
    final frame = Completer<Uint8List?>();
    await pump(tester, XFile('clip.mp4'), poster: (_) => frame.future);
    expect(placeholder, findsOneWidget);
    expect(poster, findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);

    frame.complete(_frame);
    await tester.pumpAndSettle();
    expect(poster, findsOneWidget);
    expect(placeholder, findsNothing);
    expect(find.byIcon(Icons.play_arrow), findsOneWidget);
  });

  testWidgets('a video with no frame keeps its placeholder', (tester) async {
    await pump(tester, XFile('clip.mp4'), poster: (_) async => null);
    await tester.pumpAndSettle();
    expect(placeholder, findsOneWidget);
  });
}
