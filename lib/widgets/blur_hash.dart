// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:blurhash_dart/blurhash_dart.dart' as b;
import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as image;
import 'package:material_ui/material_ui.dart';

class BlurHash extends StatefulWidget {
  final double width;
  final double height;
  final String blurhash;
  final BoxFit fit;

  const BlurHash({
    super.key,
    String? blurhash,
    required this.width,
    required this.height,
    this.fit = BoxFit.cover,
  }) : blurhash = blurhash ?? 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';

  @override
  State<BlurHash> createState() => _BlurHashState();
}

class _BlurHashState extends State<BlurHash> {
  /// Decoded placeholders by hash and pixel size, most recently used last.
  /// The same few hashes come back every time a chat is opened or scrolled,
  /// and reusing the same bytes also lets [Image.memory] hit the image cache
  /// instead of decoding the PNG again.
  static final Map<String, Uint8List> _decoded = {};
  static const int _maxDecoded = 256;

  Uint8List? _data;
  late final Future<Uint8List?> _future;

  @override
  void initState() {
    super.initState();
    // Computed once, like the bytes it caches: a later change of hash or
    // size keeps showing the first placeholder.
    _future = _computeBlurhashData();
  }

  static Future<Uint8List> getBlurhashData(BlurhashData blurhashData) async {
    final blurhash = b.BlurHash.decode(blurhashData.hsh);
    final img = blurhash.toImage(blurhashData.w, blurhashData.h);
    return Uint8List.fromList(image.encodePng(img));
  }

  Future<Uint8List?> _computeBlurhashData() async {
    if (_data != null) return _data!;
    final ratio = widget.width / widget.height;
    var width = 32;
    var height = 32;
    if (ratio > 1.0) {
      height = (width / ratio).round();
    } else {
      width = (height * ratio).round();
    }

    final cacheKey = '${widget.blurhash}|$width|$height';
    final cached = _decoded.remove(cacheKey);
    if (cached != null) {
      _decoded[cacheKey] = cached;
      return _data = cached;
    }

    final data = await compute(
      getBlurhashData,
      BlurhashData(hsh: widget.blurhash, w: width, h: height),
    );
    _decoded[cacheKey] = data;
    if (_decoded.length > _maxDecoded) _decoded.remove(_decoded.keys.first);
    return _data ??= data;
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List?>(
      future: _future,
      initialData: _data,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return Container(
            width: widget.width,
            height: widget.height,
            color: Theme.of(context).colorScheme.onInverseSurface,
          );
        }
        return Image.memory(
          data,
          fit: widget.fit,
          width: widget.width,
          height: widget.height,
        );
      },
    );
  }
}

class BlurhashData {
  final String hsh;
  final int w;
  final int h;

  const BlurhashData({required this.hsh, required this.w, required this.h});

  factory BlurhashData.fromJson(Map<String, dynamic> json) =>
      BlurhashData(hsh: json['hsh'], w: json['w'], h: json['h']);

  Map<String, dynamic> toJson() => {'hsh': hsh, 'w': w, 'h': h};
}
