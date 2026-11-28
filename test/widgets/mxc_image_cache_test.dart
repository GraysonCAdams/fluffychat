// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';

import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  // A one-pixel PNG.
  final bytes = base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR4nGNgYPj/HwADAgH/'
    'pCtHEwAAAABJRU5ErkJggg==',
  );

  Widget image() => MaterialApp(
    home: MxcImage(
      cacheName: '!room:x',
      cacheKey: 'txn-1',
      width: 40,
      height: 30,
      placeholder: (_) => const Text('placeholder'),
    ),
  );

  tearDown(() => MxcImage.clearCache('!room:x'));

  testWidgets('a primed image shows from its first frame', (tester) async {
    MxcImage.prime(cacheName: '!room:x', cacheKey: 'txn-1', bytes: bytes);
    await tester.pumpWidget(image());
    expect(find.text('placeholder'), findsNothing);
    expect(find.byType(Image), findsOneWidget);
  });

  testWidgets(
    'a shown image keeps its picture when its chat clears the cache',
    (tester) async {
      MxcImage.prime(cacheName: '!room:x', cacheKey: 'txn-1', bytes: bytes);
      await tester.pumpWidget(image());
      // Another page for the chat is disposed, as on a rotation, and this
      // image builds again afterwards.
      MxcImage.clearCache('!room:x');
      await tester.pumpWidget(image());
      await tester.pump(const Duration(seconds: 1));
      expect(find.text('placeholder'), findsNothing);
      expect(find.byType(Image), findsOneWidget);
    },
  );
}
