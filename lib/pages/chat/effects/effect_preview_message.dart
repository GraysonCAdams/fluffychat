// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/pages/chat/effects/message_effect_bubble.dart';
import 'package:fluffychat/utils/message_effects.dart';
import 'package:fluffychat/utils/resize_video.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mime/mime.dart';

/// The message the effect sheet plays its effect on, as it will arrive:
/// the staged [media] above the [text] bubble, as iMessage shows a photo
/// sent with a caption. Several items lie in a stack, the first on top.
///
/// A bubble effect moves the media and the text as one. Invisible ink
/// covers each of them on its own, so a touch on the photo leaves the text
/// hidden. A screen effect plays around the whole message.
class EffectPreviewMessage extends StatelessWidget {
  final MessageEffect effect;
  final String text;
  final List<XFile> media;
  final Color bubbleColor;
  final Color onBubbleColor;
  final BorderRadius borderRadius;

  const EffectPreviewMessage({
    required this.effect,
    required this.text,
    required this.bubbleColor,
    required this.onBubbleColor,
    required this.borderRadius,
    this.media = const [],
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final hasText = text.trim().isNotEmpty;
    final textBubble = Container(
      constraints: const BoxConstraints(maxWidth: 260),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(color: bubbleColor, borderRadius: borderRadius),
      child: Text(
        text,
        maxLines: media.isEmpty ? 4 : 2,
        overflow: TextOverflow.ellipsis,
        style: theme.textTheme.bodyLarge?.copyWith(color: onBubbleColor),
      ),
    );
    final mediaStack = media.isEmpty
        ? null
        : _MediaStack(media: media, borderRadius: borderRadius);

    EffectBubble bubble(
      Widget child, {
      Key? key,
      Color? color,
      Color? onColor,
    }) => EffectBubble(
      key: key,
      effect: effect,
      ownMessage: true,
      autoPlay: true,
      bubbleColor: color ?? bubbleColor,
      onBubbleColor: onColor ?? onBubbleColor,
      borderRadius: borderRadius,
      text: text,
      child: child,
    );

    final Widget message;
    if (effect == MessageEffect.invisibleInk) {
      message = Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        spacing: 4,
        children: [
          if (mediaStack != null)
            bubble(
              mediaStack,
              key: const ValueKey('effect_preview_media_ink'),
              color: theme.colorScheme.surfaceContainerHighest,
              onColor: theme.colorScheme.onSurface,
            ),
          if (hasText) bubble(textBubble),
        ],
      );
    } else {
      message = bubble(
        Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.end,
          spacing: 4,
          children: [?mediaStack, if (hasText) textBubble],
        ),
      );
    }
    // A tall photo and a long caption shrink together to fit the stage.
    return FittedBox(
      fit: BoxFit.scaleDown,
      alignment: Alignment.bottomRight,
      child: message,
    );
  }
}

/// The staged media: one tile, or up to three lying in a stack with the
/// ones under the first turned a little to either side.
class _MediaStack extends StatelessWidget {
  final List<XFile> media;
  final BorderRadius borderRadius;

  const _MediaStack({required this.media, required this.borderRadius});

  static const width = 180.0;
  static const height = 200.0;

  /// How far each tile under the top one is turned, in radians.
  static const _angles = [0.0, -0.07, 0.06];

  @override
  Widget build(BuildContext context) {
    final shown = media.take(_angles.length).toList();
    Widget tile(XFile file) => ClipRRect(
      borderRadius: borderRadius,
      child: SizedBox(
        width: width,
        height: height,
        child: _MediaTile(file: file),
      ),
    );
    if (shown.length == 1) {
      return KeyedSubtree(
        key: const ValueKey('effect_preview_media'),
        child: tile(shown.single),
      );
    }
    return SizedBox(
      key: const ValueKey('effect_preview_media'),
      width: width + 24,
      height: height + 16,
      child: Stack(
        alignment: Alignment.center,
        children: [
          for (var i = shown.length - 1; i >= 0; i--)
            Transform.rotate(angle: _angles[i], child: tile(shown[i])),
        ],
      ),
    );
  }
}

/// One staged item filling its tile: a photo, a video's first frame with a
/// play badge, or a file's icon and name.
class _MediaTile extends StatefulWidget {
  final XFile file;

  const _MediaTile({required this.file});

  @override
  State<_MediaTile> createState() => _MediaTileState();
}

class _MediaTileState extends State<_MediaTile> {
  /// Each file's picture, read once for as long as the file is staged:
  /// every replay builds the preview anew, and a photo read again would
  /// flash empty for a frame or two.
  static final _reads = Expando<Future<Uint8List?>>();
  static final _read = Expando<Uint8List>();

  late final String _mimeType =
      widget.file.mimeType ?? lookupMimeType(widget.file.name) ?? '';

  /// The picture's bytes for a photo that is not a file on disk, or the
  /// first frame of a video where the platform can make one.
  Future<Uint8List?>? _bytes;

  bool get _onDisk =>
      !kIsWeb &&
      widget.file.path.isNotEmpty &&
      File(widget.file.path).existsSync();

  @override
  void initState() {
    super.initState();
    final file = widget.file;
    Future<Uint8List?> remember(Future<Uint8List?> bytes) => bytes.then((data) {
      if (data != null) _read[file] = data;
      return data;
    });
    if (_mimeType.startsWith('image/')) {
      if (!_onDisk) _bytes = _reads[file] ??= remember(file.readAsBytes());
    } else if (_mimeType.startsWith('video/')) {
      _bytes = _reads[file] ??= remember(
        file.getVideoThumbnail().then((frame) => frame?.bytes),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(color: colorScheme.surfaceContainerHighest);
    final cacheWidth =
        (_MediaStack.width * MediaQuery.devicePixelRatioOf(context)).round();
    Widget picture() {
      if (_bytes == null) {
        return Image.file(
          File(widget.file.path),
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          errorBuilder: (_, _, _) => placeholder,
        );
      }
      return FutureBuilder<Uint8List?>(
        future: _bytes,
        initialData: _read[widget.file],
        builder: (context, snapshot) {
          final data = snapshot.data;
          if (data == null) return placeholder;
          return Image.memory(
            data,
            fit: BoxFit.cover,
            cacheWidth: cacheWidth,
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => placeholder,
          );
        },
      );
    }

    if (_mimeType.startsWith('image/')) return picture();
    if (_mimeType.startsWith('video/')) {
      return Stack(
        fit: StackFit.expand,
        children: [
          picture(),
          Center(
            child: Container(
              key: const ValueKey('effect_preview_play'),
              width: 44,
              height: 44,
              decoration: const BoxDecoration(
                color: Colors.black54,
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.play_arrow,
                size: 28,
                color: Colors.white,
              ),
            ),
          ),
        ],
      );
    }
    return ColoredBox(
      color: colorScheme.surfaceContainerHigh,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.insert_drive_file_outlined,
              size: 40,
              color: colorScheme.onSurfaceVariant,
            ),
            const SizedBox(height: 8),
            Text(
              widget.file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: Theme.of(
                context,
              ).textTheme.bodySmall?.copyWith(color: colorScheme.onSurface),
            ),
          ],
        ),
      ),
    );
  }
}
