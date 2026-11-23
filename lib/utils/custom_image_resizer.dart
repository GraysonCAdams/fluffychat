// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:isolate';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:matrix/matrix.dart';
import 'package:native_imaging/native_imaging.dart' as native;

(int, int) _scaleToBox(int width, int height, {required int boxSize}) {
  final fit = applyBoxFit(
    BoxFit.scaleDown,
    Size(width.toDouble(), height.toDouble()),
    Size(boxSize.toDouble(), boxSize.toDouble()),
  ).destination;
  return (fit.width.round(), fit.height.round());
}

/// Result of [_processRgba]: the JPEG bytes (null for animated images, which
/// are sent unchanged), the output dimensions and the optional blurhash.
typedef _NativeResult = ({
  Uint8List? jpeg,
  int width,
  int height,
  String? blurhash,
});

/// Blurhashes, downscales and JPEG-encodes decoded RGBA pixels with
/// native_imaging. A 12 MP photo takes hundreds of milliseconds here, so on
/// native platforms this runs in a background isolate (see
/// [customImageResizer]). native_imaging binds its library through lazily
/// initialised top-level FFI lookups, so each isolate that calls into it
/// opens the shared library on first use.
Future<_NativeResult> _processRgba({
  required Uint8List rgba,
  required int width,
  required int height,
  required bool animated,
  required bool calcBlurhash,
  required int maxDimension,
}) async {
  await native.init();

  String? blurhash;
  Uint8List? jpeg;

  var nativeImg = native.Image.fromRGBA(width, height, rgba);

  if (calcBlurhash) {
    // scale down image for blurhashing to speed it up
    final (blurW, blurH) = _scaleToBox(width, height, boxSize: 100);
    final blurhashImg = nativeImg.resample(
      blurW,
      blurH,
      // nearest is unsupported...
      native.Transform.bilinear,
    );

    blurhash = blurhashImg.toBlurhash(3, 3);

    blurhashImg.free();
  }

  if (animated) {
    // Don't scale down animated images, since those would lose frames.
    nativeImg.free();
  } else {
    if (width > maxDimension || height > maxDimension) {
      (width, height) = _scaleToBox(width, height, boxSize: maxDimension);

      final scaledImg = nativeImg.resample(
        width,
        height,
        native.Transform.lanczos,
      );
      nativeImg.free();
      nativeImg = scaledImg;
    }

    jpeg = await nativeImg.toJpeg(75);
    nativeImg.free();
  }

  return (jpeg: jpeg, width: width, height: height, blurhash: blurhash);
}

Future<MatrixImageFileResizedResponse?> customImageResizer(
  MatrixImageFileResizeArguments arguments,
) async {
  var imageBytes = arguments.bytes;
  String? blurhash;

  var originalWidth = 0;
  var originalHeight = 0;
  var width = 0;
  var height = 0;
  String? mimeType;

  try {
    // Decoding stays on this isolate: dart:ui image codecs are unavailable
    // in background isolates, and the engine already decodes and reads the
    // pixels back on its own threads while this isolate awaits.
    final dartCodec = await instantiateImageCodec(arguments.bytes);
    final frameCount = dartCodec.frameCount;
    final dartFrame = await dartCodec.getNextFrame();
    final rgbaData = await dartFrame.image.toByteData();
    if (rgbaData == null) {
      return null;
    }
    final rgba = Uint8List.view(
      rgbaData.buffer,
      rgbaData.offsetInBytes,
      rgbaData.lengthInBytes,
    );

    width = originalWidth = dartFrame.image.width;
    height = originalHeight = dartFrame.image.height;

    dartFrame.image.dispose();
    dartCodec.dispose();

    final animated = frameCount > 1;
    final calcBlurhash = arguments.calcBlurhash;
    final maxDimension = arguments.maxDimension;

    final _NativeResult result;
    if (kIsWeb) {
      // Web has no isolates; native_imaging runs as WebAssembly in place.
      result = await _processRgba(
        rgba: rgba,
        width: width,
        height: height,
        animated: animated,
        calcBlurhash: calcBlurhash,
        maxDimension: maxDimension,
      );
    } else {
      // The closure below is copied into the new isolate, so it must capture
      // only these locals and not `arguments`, which holds the encoded file.
      // TransferableTypedData is materialized there without a second copy,
      // and Isolate.run hands the result back without copying.
      final transferable = TransferableTypedData.fromList([rgba]);
      final w = width;
      final h = height;
      result = await Isolate.run(
        () => _processRgba(
          rgba: transferable.materialize().asUint8List(),
          width: w,
          height: h,
          animated: animated,
          calcBlurhash: calcBlurhash,
          maxDimension: maxDimension,
        ),
        debugName: 'customImageResizer',
      );
    }

    blurhash = result.blurhash;
    width = result.width;
    height = result.height;
    final jpeg = result.jpeg;
    if (jpeg != null) {
      imageBytes = jpeg;
      mimeType = 'image/jpeg';
    }
  } catch (e, s) {
    Logs().e('Could not generate preview', e, s);
    mimeType = null;
  }

  return MatrixImageFileResizedResponse(
    bytes: imageBytes,
    width: width,
    height: height,
    originalWidth: originalWidth,
    originalHeight: originalHeight,
    blurhash: blurhash,
    mimeType: mimeType,
  );
}
