// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:archive/archive.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/utils/client_download_content_extension.dart';
import 'package:fluffychat/utils/matrix_sdk_extensions/matrix_file_extension.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/foundation.dart';
import 'package:lottie/lottie.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

class MxcImage extends StatefulWidget {
  final Uri? uri;
  final Event? event;
  final double? width;
  final double? height;
  final BoxFit? fit;
  final bool isThumbnail;
  final bool animated;
  final Duration retryDuration;
  final Duration animationDuration;
  final Curve animationCurve;
  final ThumbnailMethod thumbnailMethod;
  final Widget Function(BuildContext context)? placeholder;
  final String? cacheKey;
  final String? cacheName;
  final Client? client;
  final BorderRadius borderRadius;

  /// Paints the image at this opacity, which is cheaper than wrapping it in
  /// an [Opacity] widget because no offscreen layer is needed.
  final double? opacity;

  /// Caps the decoded width and height of an image drawn without a known
  /// box, like the full screen viewer, so a large photo is not decoded to a
  /// huge texture. The aspect ratio is kept and nothing is upscaled.
  final int? maxDecodeDimension;

  static void clearCache(String cacheName) =>
      _MxcImageState._imageDataCaches.remove(cacheName);

  const MxcImage({
    this.uri,
    this.event,
    this.width,
    this.height,
    this.fit,
    this.placeholder,
    this.isThumbnail = true,
    this.animated = false,
    this.animationDuration = FluffyThemes.animationDuration,
    this.retryDuration = const Duration(seconds: 2),
    this.animationCurve = FluffyThemes.animationCurve,
    this.thumbnailMethod = ThumbnailMethod.scale,
    this.cacheKey,
    this.client,
    this.borderRadius = BorderRadius.zero,
    this.cacheName,
    this.opacity,
    this.maxDecodeDimension,
    super.key,
  });

  @override
  State<MxcImage> createState() => _MxcImageState();
}

class _MxcImageState extends State<MxcImage> {
  static final Map<String?, Map<String, Uint8List>> _imageDataCaches = {};
  Map<String, Uint8List> get _imageDataCache =>
      _imageDataCaches[widget.cacheName ?? ''] ??= {};

  Uint8List? _imageDataNoCache;

  Uint8List? get _imageData => widget.cacheKey == null
      ? _imageDataNoCache
      : _imageDataCache[widget.cacheKey];

  set _imageData(Uint8List? data) {
    if (data == null) return;
    final cacheKey = widget.cacheKey;
    cacheKey == null
        ? _imageDataNoCache = data
        : _imageDataCache[cacheKey] = data;
  }

  Future<void> _load() async {
    if (!mounted) return;
    final client =
        widget.client ?? widget.event?.room.client ?? Matrix.of(context).client;
    if (!client.isLogged()) return;

    final uri = widget.uri;
    final event = widget.event;

    if (uri != null && uri.scheme == 'mxc') {
      final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
      final width = widget.width;
      final realWidth = width == null ? null : width * devicePixelRatio;
      final height = widget.height;
      final realHeight = height == null ? null : height * devicePixelRatio;

      final remoteData = await client.downloadMxcCached(
        uri,
        width: realWidth,
        height: realHeight,
        thumbnailMethod: widget.thumbnailMethod,
        isThumbnail: widget.isThumbnail,
        animated: widget.animated,
      );
      if (!mounted) return;
      setState(() {
        _imageData = remoteData;
      });
    }

    if (event != null) {
      final useThumbnail = widget.isThumbnail && event.hasThumbnail;
      if (!useThumbnail &&
          !{
            MessageTypes.Image,
            MessageTypes.Sticker,
          }.contains(event.messageType)) {
        Logs().e('Event of type ${event.messageType} has no thumbnail!');
      }
      final data = await event.downloadAndDecryptAttachment(
        getThumbnail: useThumbnail,
      );
      if (data.detectFileType is MatrixImageFile) {
        if (!mounted) return;
        setState(() {
          _imageData = data.bytes;
        });
        return;
      }
    }
  }

  Future<void> _tryLoad() async {
    if (_imageData != null) {
      return;
    }
    try {
      await _load();
    } on IOException catch (_) {
      if (!mounted) return;
      await Future.delayed(widget.retryDuration);
      _tryLoad();
    } on MatrixException catch (e) {
      Logs().d('Unable to load image', e);
    }
  }

  /// Whether the image is drawn without the cross fade from the
  /// placeholder. True only while the bytes were already cached when this
  /// widget was created, so there is nothing to fade in from.
  bool _skipFade = false;

  Uint8List? _lottieSource;
  Uint8List? _lottieData;

  /// Unzipping and re-encoding a Lottie file returns a new list each time,
  /// which would make [Lottie.memory] parse the animation again on every
  /// build, so the result is kept for as long as the bytes are the same.
  Uint8List? _ungzippedLottie(Uint8List data) {
    if (!identical(data, _lottieSource)) {
      _lottieSource = data;
      _lottieData = _ungzipLottie(data);
    }
    return _lottieData;
  }

  double? _opacityValue;
  Animation<double>? _opacityAnimation;

  /// [Image] repaints whenever it gets a different animation object, so one
  /// is kept per opacity value.
  Animation<double>? get _opacity {
    final opacity = widget.opacity;
    if (opacity != _opacityValue) {
      _opacityValue = opacity;
      _opacityAnimation = opacity == null
          ? null
          : AlwaysStoppedAnimation(opacity);
    }
    return _opacityAnimation;
  }

  @override
  void initState() {
    super.initState();
    final data = _imageData;
    _skipFade = data != null && data.isNotEmpty;
    WidgetsBinding.instance.addPostFrameCallback((_) => _tryLoad());
  }

  @override
  Widget build(BuildContext context) {
    final data = _imageData;
    final hasData = data != null && data.isNotEmpty;
    if (!hasData) _skipFade = false;
    final ungzippedLottieData = data == null ? null : _ungzippedLottie(data);

    Widget errorFallback(
      BuildContext context,
      Object error,
      StackTrace? stackTrace,
    ) {
      Logs().d('Unable to render mxc image', error, stackTrace);
      return SizedBox(
        width: widget.width,
        height: widget.height,
        child: Material(
          color: Theme.of(context).colorScheme.surfaceContainer,
          child: Icon(
            Icons.broken_image_outlined,
            size: min(widget.height ?? 64, 64),
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      );
    }

    final imageChild = data == null
        ? _MxcImagePlaceholder(
            width: widget.width,
            height: widget.height,
            placeholder: widget.placeholder,
          )
        : (ungzippedLottieData != null
              ? _withOpacity(
                  Lottie.memory(
                    ungzippedLottieData,
                    width: widget.width,
                    height: widget.height,
                    fit: widget.fit,
                    errorBuilder: errorFallback,
                  ),
                )
              : Image(
                  image: _imageProvider(context, data),
                  width: widget.width,
                  height: widget.height,
                  fit: widget.fit,
                  opacity: _opacity,
                  filterQuality: widget.isThumbnail
                      ? FilterQuality.low
                      : FilterQuality.medium,
                  errorBuilder: (context, error, stackTrace) =>
                      _withOpacity(errorFallback(context, error, stackTrace)),
                ));

    if (_skipFade) {
      // The same layout the cross fade gives a shown first child: a Stack
      // that loosens the constraints, without the hidden placeholder or the
      // animation controller.
      return Stack(
        clipBehavior: Clip.none,
        children: [
          ClipRRect(borderRadius: widget.borderRadius, child: imageChild),
        ],
      );
    }

    return AnimatedCrossFade(
      duration: FluffyThemes.animationDuration,
      firstChild: ClipRRect(
        borderRadius: widget.borderRadius,
        child: imageChild,
      ),
      secondChild: _MxcImagePlaceholder(
        width: widget.width,
        height: widget.height,
        placeholder: widget.placeholder,
      ),
      crossFadeState: hasData
          ? CrossFadeState.showFirst
          : CrossFadeState.showSecond,
    );
  }

  /// Applies [MxcImage.opacity] to content that cannot paint with an
  /// opacity of its own.
  Widget _withOpacity(Widget child) {
    final opacity = widget.opacity;
    return opacity == null ? child : Opacity(opacity: opacity, child: child);
  }

  /// Decodes [data] no larger than the box it is drawn into, when that box
  /// is known. A chat full of photos otherwise keeps every one decoded at
  /// full resolution, which costs memory, upload time to the GPU and
  /// garbage collection pauses. Images shown without a size, like the full
  /// screen viewer, keep their resolution for zooming, capped only by
  /// [MxcImage.maxDecodeDimension] when it is set.
  ImageProvider _imageProvider(BuildContext context, Uint8List data) {
    final width = widget.width;
    final height = widget.height;
    final fit = widget.fit;
    if (width == null ||
        height == null ||
        !width.isFinite ||
        !height.isFinite ||
        width <= 0 ||
        height <= 0 ||
        fit == BoxFit.fill ||
        fit == BoxFit.none) {
      final maxDecodeDimension = widget.maxDecodeDimension;
      if (maxDecodeDimension != null) {
        return ResizeImage(
          MemoryImage(data),
          width: maxDecodeDimension,
          height: maxDecodeDimension,
          policy: ResizeImagePolicy.fit,
        );
      }
      return MemoryImage(data);
    }
    final devicePixelRatio = MediaQuery.devicePixelRatioOf(context);
    return _BoxSizedMemoryImage(
      data,
      boxWidth: width * devicePixelRatio,
      boxHeight: height * devicePixelRatio,
      fit: fit,
    );
  }
}

/// A [MemoryImage] decoded at the smallest size that still fills a
/// [boxWidth] by [boxHeight] physical pixel box under [fit], and never
/// larger than the encoded image.
///
/// Unlike [ResizeImage], the decoded size follows the image's own aspect
/// ratio, so [BoxFit.cover] never ends up upscaling a downsized image.
@immutable
class _BoxSizedMemoryImage extends ImageProvider<_BoxSizedMemoryImage> {
  final Uint8List bytes;
  final double boxWidth;
  final double boxHeight;

  /// Null behaves like [BoxFit.scaleDown], the default of [paintImage].
  final BoxFit? fit;

  const _BoxSizedMemoryImage(
    this.bytes, {
    required this.boxWidth,
    required this.boxHeight,
    required this.fit,
  });

  @override
  Future<_BoxSizedMemoryImage> obtainKey(ImageConfiguration configuration) =>
      SynchronousFuture<_BoxSizedMemoryImage>(this);

  @override
  ImageStreamCompleter loadImage(
    _BoxSizedMemoryImage key,
    ImageDecoderCallback decode,
  ) => MultiFrameImageStreamCompleter(
    codec: key._loadAsync(decode),
    scale: 1.0,
    debugLabel: 'MxcImage(${describeIdentity(key.bytes)})',
  );

  Future<ui.Codec> _loadAsync(ImageDecoderCallback decode) async {
    final buffer = await ui.ImmutableBuffer.fromUint8List(bytes);
    return decode(buffer, getTargetSize: _targetSize);
  }

  ui.TargetImageSize _targetSize(int intrinsicWidth, int intrinsicHeight) {
    if (intrinsicWidth <= 0 || intrinsicHeight <= 0) {
      return const ui.TargetImageSize();
    }
    final widthScale = boxWidth / intrinsicWidth;
    final heightScale = boxHeight / intrinsicHeight;
    final scale = switch (fit) {
      BoxFit.cover => max(widthScale, heightScale),
      BoxFit.fitWidth => widthScale,
      BoxFit.fitHeight => heightScale,
      _ => min(widthScale, heightScale),
    };
    if (scale >= 1) return const ui.TargetImageSize();
    // Giving only the width keeps the aspect ratio; rounding up keeps the
    // decoded image at least as large as the box needs.
    return ui.TargetImageSize(width: (intrinsicWidth * scale).ceil());
  }

  @override
  bool operator ==(Object other) =>
      other is _BoxSizedMemoryImage &&
      identical(other.bytes, bytes) &&
      other.boxWidth == boxWidth &&
      other.boxHeight == boxHeight &&
      other.fit == fit;

  @override
  int get hashCode =>
      Object.hash(identityHashCode(bytes), boxWidth, boxHeight, fit);
}

class _MxcImagePlaceholder extends StatelessWidget {
  final double? width;
  final double? height;
  final Widget Function(BuildContext context)? placeholder;

  const _MxcImagePlaceholder({
    required this.width,
    required this.height,
    required this.placeholder,
  });

  @override
  Widget build(BuildContext context) {
    return placeholder?.call(context) ??
        Container(
          width: width,
          height: height,
          alignment: Alignment.center,
          child: const CircularProgressIndicator.adaptive(strokeWidth: 2),
        );
  }
}

Uint8List? _ungzipLottie(Uint8List data) {
  // early return if the data is not gzipped
  if (data.length < 2 || data.first != 0x1f || data[1] != 0x8b) {
    return null;
  }

  // try decoding json
  try {
    final decompressed = GZipDecoder().decodeBytes(data);
    final jsonStr = utf8.decode(decompressed);
    final json = jsonDecode(jsonStr);
    if (json is Map && json.containsKey('v')) {
      return Uint8List.fromList(utf8.encode(jsonStr));
    }
  } catch (_) {
    return null;
  }

  return null;
}
