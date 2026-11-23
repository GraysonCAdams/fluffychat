// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';
import 'dart:typed_data';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/gallery_picker/picked_media.dart';
import 'package:fluffychat/pages/chat/gallery_picker/thumbnail_cache.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:photo_manager/photo_manager.dart';
import 'package:video_player/video_player.dart';

/// Upper half of the gallery picker once something is selected: a top bar
/// naming the recipient, a swipeable carousel of the picked media and the
/// caption field with the send button.
///
/// The widget listens to [selection] itself, so adding or removing media
/// rebuilds only this view and never the grid below it.
class SendPreview extends StatefulWidget {
  final MediaSelection selection;
  final ThumbnailCache thumbnails;
  final String recipientName;
  final TextEditingController caption;
  final bool hd;
  final bool sending;
  final VoidCallback onToggleHd;
  final VoidCallback onClose;
  final VoidCallback onOpenCamera;
  final VoidCallback onSend;

  const SendPreview({
    required this.selection,
    required this.thumbnails,
    required this.recipientName,
    required this.caption,
    required this.hd,
    required this.sending,
    required this.onToggleHd,
    required this.onClose,
    required this.onOpenCamera,
    required this.onSend,
    super.key,
  });

  @override
  State<SendPreview> createState() => _SendPreviewState();
}

class _SendPreviewState extends State<SendPreview> {
  /// Below 1 so the neighbouring cards peek in from the sides, hinting that
  /// the carousel can be swiped.
  static const double _viewportFraction = 0.82;

  late final PageController _pages;
  late int _lastLength;

  /// Full-size files and large video thumbnails, resolved once per item so
  /// swiping back and forth does not ask the platform again.
  final Map<String, Future<File?>> _files = {};
  final Map<String, Future<Uint8List?>> _videoThumbnails = {};

  @override
  void initState() {
    super.initState();
    _lastLength = widget.selection.length;
    _pages = PageController(
      viewportFraction: _viewportFraction,
      initialPage: _lastLength > 0 ? _lastLength - 1 : 0,
    );
    widget.selection.addListener(_onSelectionChanged);
  }

  @override
  void didUpdateWidget(SendPreview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selection != widget.selection) {
      oldWidget.selection.removeListener(_onSelectionChanged);
      widget.selection.addListener(_onSelectionChanged);
    }
  }

  @override
  void dispose() {
    widget.selection.removeListener(_onSelectionChanged);
    _pages.dispose();
    super.dispose();
  }

  void _onSelectionChanged() {
    final length = widget.selection.length;
    final grew = length > _lastLength;
    _lastLength = length;
    setState(() {});
    if (!grew) return;
    // Show the item just added, which is always the last one.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_pages.hasClients) return;
      _pages.animateToPage(
        length - 1,
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeOutCubic,
      );
    });
  }

  Future<File?> _fileFor(GalleryMedia media) =>
      _files.putIfAbsent(media.id, () => media.entity.file);

  Future<Uint8List?> _videoThumbnailFor(GalleryMedia media) =>
      _videoThumbnails.putIfAbsent(media.id, () {
        // Ask for roughly a screen's worth of pixels on the long edge while
        // keeping the video's own proportions.
        const longEdge = 1080;
        final ratio = media.aspectRatio;
        final size = ratio >= 1
            ? ThumbnailSize(longEdge, (longEdge / ratio).round())
            : ThumbnailSize((longEdge * ratio).round(), longEdge);
        return media.entity.thumbnailDataWithSize(size, quality: 90);
      });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final items = widget.selection.items;

    return SafeArea(
      bottom: false,
      child: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                IconButton(
                  tooltip: l10n.close,
                  icon: const Icon(Icons.close),
                  onPressed: widget.onClose,
                ),
                const SizedBox(width: 4),
                Expanded(
                  child: Text(
                    l10n.toRecipient(widget.recipientName),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge,
                  ),
                ),
                IconButton(
                  tooltip: l10n.sendInHd,
                  isSelected: widget.hd,
                  onPressed: widget.onToggleHd,
                  icon: _HdBadge(enabled: widget.hd),
                ),
                IconButton(
                  tooltip: l10n.openCamera,
                  icon: const Icon(Icons.add_a_photo_outlined),
                  onPressed: widget.onOpenCamera,
                ),
              ],
            ),
          ),
          Expanded(
            child: Semantics(
              container: true,
              label: l10n.attachmentsSelected(items.length),
              child: PageView.builder(
                controller: _pages,
                itemCount: items.length,
                findChildIndexCallback: (key) {
                  final index = items.indexWhere(
                    (media) => ValueKey(media.id) == key,
                  );
                  return index == -1 ? null : index;
                },
                itemBuilder: (context, index) {
                  final media = items[index];
                  return _PreviewCard(
                    key: ValueKey(media.id),
                    media: media,
                    removeTooltip: l10n.removeAttachment,
                    onRemove: () => widget.selection.remove(media.id),
                    image: switch (media) {
                      GalleryMedia() when media.isVideo => _VideoThumbnail(
                        bytes: _videoThumbnailFor(media),
                        placeholder: widget.thumbnails.peek(media.entity),
                      ),
                      GalleryMedia() => _GalleryImage(
                        file: _fileFor(media),
                        placeholder: widget.thumbnails.peek(media.entity),
                      ),
                      CapturedMedia() when media.isVideo => _CapturedVideo(
                        path: media.file.path,
                      ),
                      CapturedMedia() => _FileImage(
                        file: File(media.file.path),
                      ),
                    },
                  );
                },
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 12, 12),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              spacing: 8,
              children: [
                Expanded(
                  child: TextField(
                    controller: widget.caption,
                    minLines: 1,
                    maxLines: 4,
                    keyboardType: TextInputType.multiline,
                    textCapitalization: TextCapitalization.sentences,
                    style: theme.textTheme.bodyLarge,
                    decoration: InputDecoration(
                      hintText: l10n.writeACaption,
                      filled: true,
                      fillColor: theme.colorScheme.surfaceContainerHighest
                          .withValues(alpha: 0.8),
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 20,
                        vertical: 16,
                      ),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(28),
                        borderSide: BorderSide.none,
                      ),
                    ),
                  ),
                ),
                IconButton(
                  tooltip: l10n.send,
                  onPressed: widget.sending ? null : widget.onSend,
                  style: IconButton.styleFrom(
                    fixedSize: const Size.square(56),
                    backgroundColor: theme.colorScheme.primaryContainer,
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    disabledBackgroundColor: theme.colorScheme.primaryContainer,
                  ),
                  icon: widget.sending
                      ? SizedBox.square(
                          dimension: 24,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: theme.colorScheme.onPrimaryContainer,
                          ),
                        )
                      : const Icon(Icons.send),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// Rounded "HD" text badge; filled when full-quality sending is on.
class _HdBadge extends StatelessWidget {
  final bool enabled;

  const _HdBadge({required this.enabled});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final color = theme.colorScheme.onSurface;
    return AnimatedContainer(
      duration: const Duration(milliseconds: 150),
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 1),
      decoration: BoxDecoration(
        color: enabled ? color : Colors.transparent,
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(5),
      ),
      child: Text(
        'HD',
        style: theme.textTheme.labelMedium?.copyWith(
          fontWeight: FontWeight.w900,
          color: enabled ? theme.colorScheme.surface : color,
        ),
      ),
    );
  }
}

/// One carousel page: the media in a rounded card sized to its own aspect
/// ratio, with a remove button overlapping the top-right corner.
class _PreviewCard extends StatelessWidget {
  final PickedMedia media;
  final Widget image;
  final String removeTooltip;
  final VoidCallback onRemove;

  const _PreviewCard({
    required this.media,
    required this.image,
    required this.removeTooltip,
    required this.onRemove,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      // Leaves room for the remove button, which hangs 10dp outside the card.
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 16),
      child: Center(
        child: AspectRatio(
          aspectRatio: media.aspectRatio,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              Positioned.fill(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(28),
                  child: ColoredBox(
                    color: theme.colorScheme.surfaceContainerHigh,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        image,
                        if (media.isVideo)
                          Center(
                            child: DecoratedBox(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                color: theme.colorScheme.scrim.withValues(
                                  alpha: 0.45,
                                ),
                              ),
                              child: const Padding(
                                padding: EdgeInsets.all(8),
                                child: Icon(
                                  Icons.play_arrow,
                                  size: 40,
                                  color: Colors.white,
                                ),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
              Positioned(
                top: -10,
                right: -10,
                child: Tooltip(
                  message: removeTooltip,
                  child: Material(
                    color: theme.colorScheme.scrim.withValues(alpha: 0.55),
                    shape: const CircleBorder(
                      side: BorderSide(color: Colors.white, width: 2),
                    ),
                    clipBehavior: Clip.antiAlias,
                    child: InkWell(
                      onTap: onRemove,
                      child: const SizedBox.square(
                        dimension: 32,
                        child: Icon(Icons.close, size: 20, color: Colors.white),
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Decodes at about the card's on-screen width rather than the photo's full
/// resolution, which keeps several 50 MP photos in the carousel affordable.
int _decodeWidth(BuildContext context) =>
    (MediaQuery.sizeOf(context).width * MediaQuery.devicePixelRatioOf(context))
        .round();

/// Full-size gallery photo. The grid thumbnail is shown while the file is
/// resolved so the card never flashes empty.
class _GalleryImage extends StatelessWidget {
  final Future<File?> file;
  final Uint8List? placeholder;

  const _GalleryImage({required this.file, required this.placeholder});

  @override
  Widget build(BuildContext context) => FutureBuilder<File?>(
    future: file,
    builder: (context, snapshot) {
      final resolved = snapshot.data;
      if (resolved != null) return _FileImage(file: resolved);
      final placeholder = this.placeholder;
      if (placeholder == null) return const SizedBox.shrink();
      return Image.memory(placeholder, fit: BoxFit.cover);
    },
  );
}

class _FileImage extends StatelessWidget {
  final File file;

  const _FileImage({required this.file});

  @override
  Widget build(BuildContext context) => Image.file(
    file,
    fit: BoxFit.cover,
    cacheWidth: _decodeWidth(context),
    gaplessPlayback: true,
  );
}

/// Large thumbnail of a gallery video, falling back to the grid thumbnail.
class _VideoThumbnail extends StatelessWidget {
  final Future<Uint8List?> bytes;
  final Uint8List? placeholder;

  const _VideoThumbnail({required this.bytes, required this.placeholder});

  @override
  Widget build(BuildContext context) => FutureBuilder<Uint8List?>(
    future: bytes,
    builder: (context, snapshot) {
      final data = snapshot.data ?? placeholder;
      if (data == null) return const SizedBox.shrink();
      return Image.memory(data, fit: BoxFit.cover, gaplessPlayback: true);
    },
  );
}

/// First frame of a video just recorded with the camera. Such a file has no
/// gallery thumbnail yet, so the frame is read through video_player.
class _CapturedVideo extends StatefulWidget {
  final String path;

  const _CapturedVideo({required this.path});

  @override
  State<_CapturedVideo> createState() => _CapturedVideoState();
}

class _CapturedVideoState extends State<_CapturedVideo> {
  late final VideoPlayerController _controller = VideoPlayerController.file(
    File(widget.path),
  );
  bool _ready = false;

  @override
  void initState() {
    super.initState();
    _controller.initialize().then(
      (_) {
        if (mounted) setState(() => _ready = true);
      },
      onError: (Object e, StackTrace s) =>
          Logs().w('Unable to read recorded video', e, s),
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) return const SizedBox.shrink();
    final size = _controller.value.size;
    return FittedBox(
      fit: BoxFit.cover,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: size.width,
        height: size.height,
        child: VideoPlayer(_controller),
      ),
    );
  }
}
