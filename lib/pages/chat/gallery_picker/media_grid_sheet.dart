// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/gallery_picker/picked_media.dart';
import 'package:fluffychat/pages/chat/gallery_picker/thumbnail_cache.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:photo_manager/photo_manager.dart';

/// Draggable bottom sheet with a three-column grid of the newest photos and
/// videos on the device. Tapping a tile toggles it in [selection].
///
/// Assets are fetched [_pageSize] at a time as the user scrolls, newest
/// first, so a library of thousands of items opens instantly. Limited
/// ("selected photos only") access is treated like full access: the grid
/// simply shows what the system lets the app see.
class MediaGridSheet extends StatefulWidget {
  final MediaSelection selection;
  final ThumbnailCache thumbnails;

  /// The pending gallery permission request, shared with the page so the
  /// camera can wait for it: Android shows one permission dialog at a time.
  final Future<PermissionState> permission;

  /// Collapsed height as a fraction of the area the sheet is laid out in.
  /// Fully expanded, the sheet stops just below the status bar.
  final double minChildSize;

  const MediaGridSheet({
    required this.selection,
    required this.thumbnails,
    required this.permission,
    required this.minChildSize,
    super.key,
  });

  @override
  State<MediaGridSheet> createState() => _MediaGridSheetState();
}

class _MediaGridSheetState extends State<MediaGridSheet>
    with WidgetsBindingObserver {
  static const int _pageSize = 60;

  /// Start the next page once fewer than this many pixels remain below the
  /// viewport, so new rows are ready before the user reaches them.
  static const double _prefetchExtent = 1200;

  final FilterOptionGroup _filter = FilterOptionGroup(
    orders: const [OrderOption(type: OrderOptionType.createDate)],
  );

  PermissionState? _permission;
  final List<AssetEntity> _assets = [];
  int _nextPage = 0;
  bool _loading = false;
  bool _hasMore = true;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _init();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The user may come back from the system settings having granted
    // access, so re-check whenever the app resumes without it.
    if (state != AppLifecycleState.resumed) return;
    final permission = _permission;
    if (permission == null || permission.hasAccess) return;
    PhotoManager.getPermissionState(
      requestOption: const PermissionRequestOption(),
    ).then(_onPermission);
  }

  Future<void> _init() async {
    PermissionState permission;
    try {
      permission = await widget.permission;
    } catch (e, s) {
      Logs().w('Gallery permission request failed', e, s);
      permission = PermissionState.denied;
    }
    _onPermission(permission);
  }

  void _onPermission(PermissionState permission) {
    if (!mounted) return;
    setState(() => _permission = permission);
    if (permission.hasAccess && _assets.isEmpty) _loadMore();
  }

  Future<void> _loadMore() async {
    if (_loading || !_hasMore) return;
    setState(() => _loading = true);
    List<AssetEntity> page;
    try {
      page = await PhotoManager.getAssetListPaged(
        page: _nextPage,
        pageCount: _pageSize,
        filterOption: _filter,
      );
    } catch (e, s) {
      Logs().w('Unable to load gallery assets', e, s);
      page = const [];
    }
    if (!mounted) return;
    setState(() {
      _assets.addAll(page);
      _nextPage++;
      _hasMore = page.length == _pageSize;
      _loading = false;
    });
  }

  bool _onScroll(ScrollNotification notification) {
    if (notification.metrics.extentAfter < _prefetchExtent) _loadMore();
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final permission = _permission;
    final padding = MediaQuery.paddingOf(context);

    return LayoutBuilder(
      builder: (context, constraints) => DraggableScrollableSheet(
        initialChildSize: widget.minChildSize,
        minChildSize: widget.minChildSize,
        maxChildSize: constraints.maxHeight <= padding.top
            ? 1
            : ((constraints.maxHeight - padding.top) / constraints.maxHeight)
                  .clamp(widget.minChildSize, 1.0),
        snap: true,
        builder: (context, scrollController) => Material(
          color: theme.colorScheme.surfaceContainer,
          clipBehavior: Clip.antiAlias,
          shape: const RoundedRectangleBorder(
            borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
          ),
          child: NotificationListener<ScrollNotification>(
            onNotification: _onScroll,
            child: CustomScrollView(
              controller: scrollController,
              slivers: [
                SliverPersistentHeader(
                  pinned: true,
                  delegate: _DragHandleDelegate(
                    background: theme.colorScheme.surfaceContainer,
                    handle: theme.colorScheme.onSurfaceVariant.withValues(
                      alpha: 0.4,
                    ),
                  ),
                ),
                if (permission == null ||
                    (permission.hasAccess && _assets.isEmpty && _loading))
                  const SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(child: CircularProgressIndicator.adaptive()),
                  )
                else if (!permission.hasAccess)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _GalleryMessage(
                      icon: Icons.photo_library_outlined,
                      message: l10n.allowGalleryAccess,
                      actionLabel: l10n.openSettings,
                      onAction: PhotoManager.openSetting,
                    ),
                  )
                else if (_assets.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: _GalleryMessage(
                      icon: Icons.photo_outlined,
                      message: l10n.noRecentMedia,
                    ),
                  )
                else
                  SliverGrid(
                    gridDelegate:
                        const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 3,
                          mainAxisSpacing: 2,
                          crossAxisSpacing: 2,
                        ),
                    delegate: SliverChildBuilderDelegate(
                      (context, index) => _GridTile(
                        key: ValueKey(_assets[index].id),
                        media: GalleryMedia(_assets[index]),
                        selection: widget.selection,
                        thumbnails: widget.thumbnails,
                      ),
                      childCount: _assets.length,
                    ),
                  ),
                SliverToBoxAdapter(child: SizedBox(height: padding.bottom)),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Pinned strip with the drag handle, so the handle stays reachable while
/// the expanded grid scrolls underneath it.
class _DragHandleDelegate extends SliverPersistentHeaderDelegate {
  static const double _extent = 28;

  final Color background;
  final Color handle;

  const _DragHandleDelegate({required this.background, required this.handle});

  @override
  double get minExtent => _extent;

  @override
  double get maxExtent => _extent;

  @override
  Widget build(
    BuildContext context,
    double shrinkOffset,
    bool overlapsContent,
  ) => ColoredBox(
    color: background,
    child: Center(
      child: Container(
        width: 32,
        height: 4,
        decoration: BoxDecoration(
          color: handle,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    ),
  );

  @override
  bool shouldRebuild(_DragHandleDelegate oldDelegate) =>
      oldDelegate.background != background || oldDelegate.handle != handle;
}

/// Centered icon, text and optional button for the empty and no-permission
/// states of the grid.
class _GalleryMessage extends StatelessWidget {
  final IconData icon;
  final String message;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _GalleryMessage({
    required this.icon,
    required this.message,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final actionLabel = this.actionLabel;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 40, color: theme.colorScheme.onSurfaceVariant),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          if (actionLabel != null) ...[
            const SizedBox(height: 16),
            FilledButton.tonal(onPressed: onAction, child: Text(actionLabel)),
          ],
        ],
      ),
    );
  }
}

/// One grid cell. Only this tile rebuilds when its own selection flag
/// changes; the thumbnail is passed through as a prebuilt child so the
/// selection animation never re-creates the image.
class _GridTile extends StatelessWidget {
  final GalleryMedia media;
  final MediaSelection selection;
  final ThumbnailCache thumbnails;

  const _GridTile({
    required this.media,
    required this.selection,
    required this.thumbnails,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return GestureDetector(
      onTap: () => selection.toggle(media),
      child: ValueListenableBuilder<bool>(
        valueListenable: selection.isSelected(media.id),
        child: _AssetThumbnail(entity: media.entity, thumbnails: thumbnails),
        builder: (context, selected, thumbnail) => Semantics(
          button: true,
          selected: selected,
          child: TweenAnimationBuilder<double>(
            tween: Tween(end: selected ? 1 : 0),
            duration: const Duration(milliseconds: 180),
            curve: Curves.easeOutCubic,
            child: thumbnail,
            builder: (context, t, thumbnail) => Stack(
              fit: StackFit.expand,
              children: [
                Transform.scale(
                  scale: 1 - 0.12 * t,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(16 * t),
                    // An unselected tile has square corners, so clipping
                    // would only add a clip layer per tile while scrolling.
                    // Switching clipBehavior rather than dropping the widget
                    // keeps the thumbnail's element in place.
                    clipBehavior: t == 0 ? Clip.none : Clip.antiAlias,
                    child: thumbnail,
                  ),
                ),
                if (t > 0)
                  Positioned(
                    top: 6,
                    left: 6,
                    child: Opacity(
                      opacity: t,
                      child: Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: theme.colorScheme.primary,
                          border: Border.all(
                            color: theme.colorScheme.surfaceContainer,
                            width: 1.5,
                          ),
                        ),
                        child: Icon(
                          Icons.check,
                          size: 16,
                          color: theme.colorScheme.onPrimary,
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Square thumbnail of a gallery asset, with a duration label and play
/// badge for videos.
class _AssetThumbnail extends StatelessWidget {
  final AssetEntity entity;
  final ThumbnailCache thumbnails;

  const _AssetThumbnail({required this.entity, required this.thumbnails});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Stack(
      fit: StackFit.expand,
      children: [
        FutureBuilder<Uint8List?>(
          future: thumbnails.load(entity),
          initialData: thumbnails.peek(entity),
          builder: (context, snapshot) {
            final bytes = snapshot.data;
            if (bytes == null) {
              return ColoredBox(
                color: theme.colorScheme.surfaceContainerHighest,
              );
            }
            return Image.memory(
              bytes,
              fit: BoxFit.cover,
              gaplessPlayback: true,
            );
          },
        ),
        if (entity.type == AssetType.video)
          Positioned(
            right: 6,
            bottom: 6,
            child: Row(
              spacing: 4,
              children: [
                Text(
                  formatVideoDuration(entity.videoDuration),
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: theme.colorScheme.onSurface,
                    shadows: [
                      Shadow(color: theme.colorScheme.scrim, blurRadius: 4),
                    ],
                  ),
                ),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: theme.colorScheme.onSurface,
                  ),
                  child: Icon(
                    Icons.play_arrow,
                    size: 16,
                    color: theme.colorScheme.surface,
                  ),
                ),
              ],
            ),
          ),
      ],
    );
  }
}

/// Formats a video length as mm:ss, the way gallery apps label videos.
String formatVideoDuration(Duration duration) {
  final minutes = duration.inMinutes.toString().padLeft(2, '0');
  final seconds = (duration.inSeconds % 60).toString().padLeft(2, '0');
  return '$minutes:$seconds';
}
