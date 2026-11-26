// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/utils/fallback_avatar_image.dart';
import 'package:fluffychat/utils/group_collage_image.dart';
import 'package:flutter_test/flutter_test.dart';

/// Decoded RGBA pixels of a PNG.
Future<({int size, ByteData rgba})> _decode(Uint8List png) async {
  final codec = await ui.instantiateImageCodec(png);
  final image = (await codec.getNextFrame()).image;
  final rgba = (await image.toByteData())!;
  final size = image.width;
  image.dispose();
  codec.dispose();
  return (size: size, rgba: rgba);
}

bool _opaque(({int size, ByteData rgba}) image, double x, double y) {
  final px = (x * image.size).round().clamp(0, image.size - 1);
  final py = (y * image.size).round().clamp(0, image.size - 1);
  return image.rgba.getUint8((py * image.size + px) * 4 + 3) > 200;
}

void main() {
  testWidgets('the person placeholder of a bare number fills the circle', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final png = await renderFallbackAvatar('+12292223978', size: 128);
      final image = await _decode(png!);
      final background = image.rgba.getUint32(0);
      var minX = image.size, maxX = 0, minY = image.size, maxY = 0;
      for (var y = 0; y < image.size; y++) {
        for (var x = 0; x < image.size; x++) {
          if (image.rgba.getUint32((y * image.size + x) * 4) == background) {
            continue;
          }
          if (x < minX) minX = x;
          if (x > maxX) maxX = x;
          if (y < minY) minY = y;
          if (y > maxY) maxY = y;
        }
      }
      // Google Messages' silhouette spans over half of the circle.
      expect((maxX - minX) / image.size, greaterThan(0.5));
      expect((maxY - minY) / image.size, greaterThan(0.5));
    });
  });

  group('renderGroupCollage', () {
    CollageMember member(String name) => (name: name, image: null);

    testWidgets('is nothing for fewer than two members', (tester) async {
      await tester.runAsync(() async {
        expect(await renderGroupCollage([member('Ann')]), isNull);
      });
    });

    testWidgets('puts two members on a diagonal', (tester) async {
      await tester.runAsync(() async {
        final image = await _decode(
          (await renderGroupCollage([member('Ann'), member('Bob')]))!,
        );
        expect(_opaque(image, 0.25, 0.25), isTrue);
        expect(_opaque(image, 0.75, 0.75), isTrue);
        expect(_opaque(image, 0.95, 0.05), isFalse);
        expect(_opaque(image, 0.05, 0.95), isFalse);
      });
    });

    testWidgets('puts four members in a grid and ignores a fifth', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final image = await _decode(
          (await renderGroupCollage([
            for (final n in ['Ann', 'Bob', 'Cy', 'Di', 'Ed']) member(n),
          ]))!,
        );
        for (final (x, y) in [
          (0.25, 0.25),
          (0.75, 0.25),
          (0.25, 0.75),
          (0.75, 0.75),
        ]) {
          expect(_opaque(image, x, y), isTrue, reason: '$x,$y');
        }
        // The gap between the faces and the corners stay transparent.
        expect(_opaque(image, 0.02, 0.02), isFalse);
        expect(_opaque(image, 0.5, 0.5), isFalse);
      });
    });
  });
}
