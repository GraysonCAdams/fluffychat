// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:cross_file/cross_file.dart';
import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/size_string.dart';
import 'package:flutter/foundation.dart';
import 'package:material_ui/material_ui.dart';
import 'package:mime/mime.dart';

/// Side of the square thumbnail tile for one staged attachment.
const double _tileSize = 72;

/// Space between neighbouring tiles.
const double _gap = 8;

/// Room left above each tile so the remove badge can stick out past the
/// tile's top edge without being clipped by the list.
const double _topInset = 8;

/// How far the remove badge reaches past the tile's top and right edges.
const double _badgeOverhang = 6;

const double _badgeSize = 24;

/// Width of the ring in the composer's own colour that separates the badge
/// from the thumbnail underneath it.
const double _badgeRing = 2;

/// Minimum touch target for the remove badge.
const double _hitTarget = 48;

/// Attachments the user has picked but not sent yet, shown as a row of
/// removable thumbnails inside the message composer, above the text field.
///
/// Each file becomes a rounded square tile: a picture for images, a video
/// placeholder for videos, and an icon with the file name for anything else.
/// Tapping a picture opens it full screen.
/// A small round badge on the tile's top-right corner removes it through
/// [onRemove]. The strip collapses to nothing when [files] is empty and
/// animates its height as the first file arrives or the last one leaves.
class ComposerAttachmentStrip extends StatelessWidget {
  final List<XFile> files;
  final void Function(XFile file) onRemove;

  const ComposerAttachmentStrip({
    required this.files,
    required this.onRemove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    return AnimatedSize(
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      alignment: Alignment.bottomCenter,
      child: files.isEmpty
          ? const SizedBox.shrink()
          : SizedBox(
              height: _topInset + _tileSize,
              child: ListView.builder(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.only(left: 12, right: 4),
                itemCount: files.length,
                itemBuilder: (context, i) {
                  final file = files[i];
                  return _AttachmentChip(
                    key: ObjectKey(file),
                    file: file,
                    onRemove: () => onRemove(file),
                  );
                },
              ),
            ),
    );
  }
}

/// One tile plus its remove badge.
///
/// The item is wider and taller than the tile so that the whole 48dp badge
/// target sits inside the item's bounds: a [Stack] only receives taps within
/// its own size, so a target hanging outside it would lose part of its area.
class _AttachmentChip extends StatelessWidget {
  final XFile file;
  final VoidCallback onRemove;

  const _AttachmentChip({
    required this.file,
    required this.onRemove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final mimeType = file.mimeType ?? lookupMimeType(file.name) ?? '';
    final Widget preview;
    if (mimeType.startsWith('image/')) {
      // Tapping a picture opens it full screen, as a sent one would.
      preview = GestureDetector(
        onTap: () => Navigator.of(context, rootNavigator: true).push(
          MaterialPageRoute<void>(
            fullscreenDialog: true,
            builder: (_) => _FullScreenImage(file: file),
          ),
        ),
        child: _ImagePreview(file: file),
      );
    } else if (mimeType.startsWith('video/')) {
      preview = const _VideoPreview();
    } else {
      preview = _FilePreview(file: file, mimeType: mimeType);
    }

    return SizedBox(
      width: _tileSize + _gap,
      height: _topInset + _tileSize,
      child: Stack(
        children: [
          Positioned(
            left: 0,
            top: _topInset,
            width: _tileSize,
            height: _tileSize,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: preview,
            ),
          ),
          Positioned(
            // Puts the badge's outer edge _badgeOverhang past the tile's
            // top-right corner, with the target filling the space around it.
            right: _gap - _badgeOverhang - _badgeRing,
            top: _topInset - _badgeOverhang - _badgeRing,
            child: _RemoveBadge(onRemove: onRemove),
          ),
        ],
      ),
    );
  }
}

class _RemoveBadge extends StatelessWidget {
  final VoidCallback onRemove;

  const _RemoveBadge({required this.onRemove});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    // The ring takes the colour of the surface the strip sits on, so the
    // badge reads as cut out of the thumbnail in either theme.
    final ringColor =
        Material.maybeOf(context)?.color ?? colorScheme.surfaceContainer;
    const ringSize = _badgeSize + 2 * _badgeRing;

    return Semantics(
      button: true,
      label: L10n.of(context).removeAttachment,
      excludeSemantics: true,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onRemove,
        child: Padding(
          // The target extends left and down from the badge; the item's
          // top and right edges bound it on the other two sides.
          padding: const EdgeInsets.only(
            left: _hitTarget - ringSize,
            bottom: _hitTarget - ringSize,
          ),
          child: Container(
            width: ringSize,
            height: ringSize,
            alignment: Alignment.center,
            decoration: BoxDecoration(color: ringColor, shape: BoxShape.circle),
            child: Container(
              width: _badgeSize,
              height: _badgeSize,
              decoration: BoxDecoration(
                color: colorScheme.inverseSurface,
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.close,
                size: 16,
                color: colorScheme.onInverseSurface,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Whether [file] can be read from its path. A file held only in memory can
/// still carry a path: a keyboard-inserted GIF sets its file name there so
/// the name survives, and nothing exists on disk at that path.
bool _isOnDisk(XFile file) =>
    !kIsWeb && file.path.isNotEmpty && File(file.path).existsSync();

/// Image thumbnail, decoded at tile size to keep memory low.
///
/// Native platforms read straight from the picked file's path. On the web,
/// and for files that only exist in memory (an edited image, or a GIF from
/// the keyboard, for example), the bytes are read once and kept for the life
/// of the tile.
class _ImagePreview extends StatefulWidget {
  final XFile file;

  const _ImagePreview({required this.file});

  @override
  State<_ImagePreview> createState() => _ImagePreviewState();
}

class _ImagePreviewState extends State<_ImagePreview> {
  Future<Uint8List>? _bytes;

  late final bool _hasNativePath = _isOnDisk(widget.file);

  @override
  void initState() {
    super.initState();
    if (!_hasNativePath) _bytes = widget.file.readAsBytes();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final cacheWidth = (_tileSize * MediaQuery.devicePixelRatioOf(context))
        .round();
    Widget errorBuilder(BuildContext context, Object error, StackTrace? _) =>
        _IconTile(icon: Icons.broken_image_outlined, colorScheme: colorScheme);

    if (_hasNativePath) {
      return Image.file(
        File(widget.file.path),
        fit: BoxFit.cover,
        cacheWidth: cacheWidth,
        errorBuilder: errorBuilder,
      );
    }
    return FutureBuilder<Uint8List>(
      future: _bytes,
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return snapshot.hasError
              ? _IconTile(
                  icon: Icons.broken_image_outlined,
                  colorScheme: colorScheme,
                )
              : ColoredBox(color: colorScheme.surfaceContainerHighest);
        }
        return Image.memory(
          data,
          fit: BoxFit.cover,
          cacheWidth: cacheWidth,
          gaplessPlayback: true,
          errorBuilder: errorBuilder,
        );
      },
    );
  }
}

/// A staged picture on its own page, at full size with pinch to zoom.
class _FullScreenImage extends StatelessWidget {
  final XFile file;

  const _FullScreenImage({required this.file});

  @override
  Widget build(BuildContext context) {
    Widget errorBuilder(BuildContext context, Object error, StackTrace? _) =>
        const Icon(Icons.broken_image_outlined, color: Colors.white, size: 48);
    final hasNativePath = _isOnDisk(file);
    return Scaffold(
      backgroundColor: Colors.black,
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.white,
        elevation: 0,
        leading: const CloseButton(),
      ),
      body: InteractiveViewer(
        minScale: 1,
        maxScale: 10,
        child: Center(
          child: hasNativePath
              ? Image.file(
                  File(file.path),
                  fit: BoxFit.contain,
                  errorBuilder: errorBuilder,
                )
              : FutureBuilder<Uint8List>(
                  future: file.readAsBytes(),
                  builder: (context, snapshot) {
                    final data = snapshot.data;
                    if (data == null) return const SizedBox.shrink();
                    return Image.memory(
                      data,
                      fit: BoxFit.contain,
                      errorBuilder: errorBuilder,
                    );
                  },
                ),
        ),
      ),
    );
  }
}

/// Placeholder for a video: decoding a real frame needs a platform video
/// decoder per tile, which is too slow for a preview that appears the moment
/// a file is picked.
class _VideoPreview extends StatelessWidget {
  const _VideoPreview();

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Stack(
      fit: StackFit.expand,
      children: [
        _IconTile(icon: Icons.videocam, colorScheme: colorScheme),
        Positioned(
          left: 6,
          bottom: 6,
          child: Container(
            width: 20,
            height: 20,
            decoration: BoxDecoration(
              color: colorScheme.inverseSurface,
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.play_arrow,
              size: 14,
              color: colorScheme.onInverseSurface,
            ),
          ),
        ),
      ],
    );
  }
}

/// Tile for files that have no visual preview: a type icon, the file name
/// and, once known, its size.
class _FilePreview extends StatefulWidget {
  final XFile file;
  final String mimeType;

  const _FilePreview({required this.file, required this.mimeType});

  @override
  State<_FilePreview> createState() => _FilePreviewState();
}

class _FilePreviewState extends State<_FilePreview> {
  late final Future<int> _length = widget.file.length();

  IconData get _icon {
    final mimeType = widget.mimeType;
    if (mimeType.startsWith('audio/')) return Icons.audio_file_outlined;
    if (mimeType == 'application/pdf') return Icons.picture_as_pdf_outlined;
    if (mimeType.startsWith('text/')) return Icons.description_outlined;
    if (mimeType.contains('zip') ||
        mimeType.contains('compressed') ||
        mimeType.contains('tar')) {
      return Icons.folder_zip_outlined;
    }
    return Icons.insert_drive_file_outlined;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textStyle = theme.textTheme.labelSmall?.copyWith(
      color: colorScheme.onSurfaceVariant,
    );
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.all(6),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(_icon, size: 20, color: colorScheme.onSurfaceVariant),
            const Spacer(),
            Text(
              widget.file.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: textStyle,
            ),
            FutureBuilder<int>(
              future: _length,
              builder: (context, snapshot) {
                final length = snapshot.data;
                if (length == null) return const SizedBox.shrink();
                return Text(
                  length.sizeString,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: textStyle,
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}

/// Tonal tile with a centred icon, used for videos and unreadable images.
class _IconTile extends StatelessWidget {
  final IconData icon;
  final ColorScheme colorScheme;

  const _IconTile({required this.icon, required this.colorScheme});

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: colorScheme.surfaceContainerHighest,
      child: Center(
        child: Icon(icon, size: 28, color: colorScheme.onSurfaceVariant),
      ),
    );
  }
}
