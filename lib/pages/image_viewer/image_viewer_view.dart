// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/image_viewer/pointers_listener.dart';
import 'package:fluffychat/pages/image_viewer/video_player.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/hover_builder.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

import 'desktop_image_viewer_view.dart';
import 'image_viewer.dart';

/// The media viewer's layout on a phone, after the photo viewer of Apple's
/// Messages and Photos: the picture edge to edge on black, a top bar with
/// the sender and time, a strip of the chat's other media and a row of
/// actions at the bottom. Drawn in the app's dark theme. The desktop has a
/// layout of its own, [DesktopImageViewerView].
class ImageViewerView extends StatelessWidget {
  final ImageViewerController controller;

  const ImageViewerView(this.controller, {super.key});

  @override
  Widget build(BuildContext context) {
    if (controller.desktopLayout) return DesktopImageViewerView(controller);
    final theme = FluffyThemes.buildTheme(context, Brightness.dark);
    final progress = controller.dragProgress;
    final chrome = controller.chromeVisible && controller.dragOffset == 0;
    return Theme(
      data: theme,
      child: KeyboardListener(
        focusNode: controller.focusNode,
        autofocus: true,
        onKeyEvent: controller.onKeyEvent,
        child: Scaffold(
          backgroundColor: Colors.black.withValues(alpha: 1 - progress),
          body: HoverBuilder(
            builder: (context, hovered) => Stack(
              children: [
                Positioned.fill(
                  child: GestureDetector(
                    onVerticalDragUpdate: controller.zoomed
                        ? null
                        : controller.onDragUpdate,
                    onVerticalDragEnd: controller.zoomed
                        ? null
                        : controller.onDragEnd,
                    child: Transform.translate(
                      offset: Offset(0, controller.dragOffset),
                      child: Transform.scale(
                        scale: 1 - progress * 0.25,
                        child: _pages(context),
                      ),
                    ),
                  ),
                ),
                Positioned(
                  top: 0,
                  left: 0,
                  right: 0,
                  child: _Chrome(visible: chrome, child: _TopBar(controller)),
                ),
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: _Chrome(
                    visible: chrome,
                    child: _BottomBar(controller),
                  ),
                ),
                if (hovered && chrome) ...[
                  if (controller.canGoBack)
                    Align(
                      alignment: .centerLeft,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: IconButton.filledTonal(
                          tooltip: L10n.of(context).previous,
                          icon: const Icon(Icons.keyboard_arrow_left_outlined),
                          onPressed: controller.prevImage,
                        ),
                      ),
                    ),
                  if (controller.canGoNext)
                    Align(
                      alignment: .centerRight,
                      child: Padding(
                        padding: const EdgeInsets.all(12.0),
                        child: IconButton.filledTonal(
                          tooltip: L10n.of(context).next,
                          icon: const Icon(Icons.keyboard_arrow_right_outlined),
                          onPressed: controller.nextImage,
                        ),
                      ),
                    ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _pages(BuildContext context) => PointersListener(
    builder: (context, moreThanOnePointer) => PageView.builder(
      physics: moreThanOnePointer || controller.zoomed
          ? const NeverScrollableScrollPhysics()
          : const BouncingScrollPhysics(),
      scrollDirection: Axis.horizontal,
      controller: controller.pageController,
      onPageChanged: controller.onPageChanged,
      itemCount: controller.allEvents.length,
      itemBuilder: (context, i) {
        final event = controller.allEvents[i];
        switch (event.messageType) {
          case MessageTypes.Video:
            return GestureDetector(
              // Taps beside the video show or hide the bars; taps on it
              // belong to its controls.
              onTap: controller.toggleChrome,
              behavior: HitTestBehavior.opaque,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 72),
                child: Center(
                  child: GestureDetector(
                    onTap: () {},
                    child: EventVideoPlayer(
                      event,
                      startAt: event.eventId == controller.widget.event.eventId
                          ? controller.widget.videoStartPosition
                          : null,
                    ),
                  ),
                ),
              ),
            );
          case MessageTypes.Image:
          case MessageTypes.Sticker:
          default:
            return ZoomableMedia(
              key: ValueKey(event.eventId),
              onTap: controller.toggleChrome,
              onZoomChanged: controller.onZoomChanged,
              onInteractionEnd: controller.onInteractionEnds,
              child: Hero(
                tag: event.eventId,
                child: MxcImage(
                  key: ValueKey(event.eventId),
                  event: event,
                  fit: BoxFit.contain,
                  isThumbnail: false,
                  animated: true,
                  // Keeps a 12 MP photo from becoming a 48 MB texture;
                  // 4096 px still leaves headroom for pinch zoom.
                  maxDecodeDimension: 4096,
                ),
              ),
            );
        }
      },
    ),
  );
}

/// Fades the viewer's bars in and out, and keeps hidden ones from taking
/// taps.
class _Chrome extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _Chrome({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: FluffyThemes.animationDuration,
      curve: FluffyThemes.animationCurve,
      child: child,
    ),
  );
}

/// The top bar: close on the left, then who sent the media shown and when,
/// centred as Apple does it, over a scrim that keeps it readable on a
/// bright picture.
class _TopBar extends StatelessWidget {
  final ImageViewerController controller;

  const _TopBar(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final event = controller.currentEvent;
    final sender = event.senderFromMemoryOrFallback;
    final name = sender.calcDisplayname();
    final sent = event.originServerTs;
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: SizedBox(
          height: 64,
          child: Row(
            children: [
              const SizedBox(width: 4),
              IconButton(
                icon: const Icon(Icons.close),
                tooltip: L10n.of(context).close,
                onPressed: controller.close,
              ),
              Expanded(
                child: Row(
                  mainAxisAlignment: .center,
                  children: [
                    Avatar(mxContent: sender.avatarUrl, name: name, size: 32),
                    const SizedBox(width: 12),
                    Flexible(
                      child: Column(
                        mainAxisSize: .min,
                        crossAxisAlignment: .start,
                        children: [
                          Text(
                            name,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.titleSmall,
                          ),
                          Text(
                            '${sent.localizedDate(context)} • '
                            '${sent.localizedTimeOfDay(context)}',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: theme.colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              // Balances the close button so the sender stays centred.
              const SizedBox(width: 52),
            ],
          ),
        ),
      ),
    );
  }
}

/// The bottom: the strip of the chat's media, then the actions.
class _BottomBar extends StatelessWidget {
  final ImageViewerController controller;

  const _BottomBar(this.controller);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return DecoratedBox(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black87, Colors.transparent],
        ),
      ),
      child: SafeArea(
        top: false,
        child: Column(
          mainAxisSize: .min,
          children: [
            if (controller.allEvents.length > 1)
              MediaThumbnailStrip(controller),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisAlignment: .spaceAround,
                children: [
                  if (PlatformInfos.isMobile)
                    // Use builder context to correctly position the share
                    // dialog on iPad.
                    Builder(
                      builder: (context) => IconButton(
                        tooltip: l10n.share,
                        icon: Icon(Icons.adaptive.share_outlined),
                        onPressed: () => controller.shareFileAction(context),
                      ),
                    ),
                  IconButton(
                    tooltip: l10n.downloadFile,
                    icon: const Icon(Icons.download_outlined),
                    onPressed: () => controller.saveFileAction(context),
                  ),
                  if (controller.widget.onReply != null)
                    IconButton(
                      tooltip: l10n.reply,
                      icon: const Icon(Icons.reply_outlined),
                      onPressed: controller.replyAction,
                    ),
                  IconButton(
                    tooltip: l10n.forward,
                    icon: const Icon(Icons.forward_outlined),
                    onPressed: controller.forwardAction,
                  ),
                  PopupMenuButton<void>(
                    tooltip: l10n.more,
                    icon: const Icon(Icons.more_horiz),
                    itemBuilder: (context) => [
                      if (controller.widget.onShowInChat != null)
                        PopupMenuItem(
                          onTap: controller.showInChatAction,
                          child: ListTile(
                            leading: const Icon(Icons.chat_outlined),
                            title: Text(l10n.showInChat),
                          ),
                        ),
                      PopupMenuItem(
                        onTap: () => controller.saveFileAction(context),
                        child: ListTile(
                          leading: const Icon(Icons.download_outlined),
                          title: Text(l10n.downloadFile),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// A strip of the chat's media, the one shown outlined and larger, as the
/// scrubber at the bottom of Apple's Photos. A tap shows that one.
class MediaThumbnailStrip extends StatefulWidget {
  final ImageViewerController controller;

  const MediaThumbnailStrip(this.controller, {super.key});

  static const itemSize = 40.0;
  static const currentSize = 52.0;
  static const gap = 4.0;

  @override
  State<MediaThumbnailStrip> createState() => _MediaThumbnailStripState();
}

class _MediaThumbnailStripState extends State<MediaThumbnailStrip> {
  final _scroll = ScrollController();
  int? _centred;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Keeps the current thumbnail in the middle of the strip.
  void _centre() {
    final index = widget.controller.currentIndex;
    if (_centred == index) return;
    _centred = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      const step = MediaThumbnailStrip.itemSize + MediaThumbnailStrip.gap;
      // The strip's padding centres the first thumbnail, so each step along
      // centres the next.
      final target = (index * step).clamp(
        0.0,
        _scroll.position.maxScrollExtent,
      );
      _scroll.animateTo(
        target,
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    final controller = widget.controller;
    final colorScheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: MediaThumbnailStrip.currentSize + 8,
      child: LayoutBuilder(
        builder: (context, constraints) {
          _centre();
          return ListView.separated(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: EdgeInsets.symmetric(
              horizontal: constraints.maxWidth / 2 - 26,
            ),
            itemCount: controller.allEvents.length,
            separatorBuilder: (_, _) =>
                const SizedBox(width: MediaThumbnailStrip.gap),
            itemBuilder: (context, i) {
              final event = controller.allEvents[i];
              final current = i == controller.currentIndex;
              final size = current
                  ? MediaThumbnailStrip.currentSize
                  : MediaThumbnailStrip.itemSize;
              return Center(
                child: Semantics(
                  selected: current,
                  button: true,
                  child: GestureDetector(
                    onTap: () => controller.jumpTo(i),
                    child: AnimatedContainer(
                      duration: FluffyThemes.animationDuration,
                      curve: FluffyThemes.animationCurve,
                      width: size,
                      height: size,
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(
                          color: current
                              ? colorScheme.primary
                              : Colors.transparent,
                          width: 2,
                        ),
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Stack(
                        fit: StackFit.expand,
                        children: [
                          if (event.messageType != MessageTypes.Video ||
                              event.hasThumbnail)
                            MxcImage(
                              event: event,
                              width: MediaThumbnailStrip.currentSize,
                              height: MediaThumbnailStrip.currentSize,
                              fit: BoxFit.cover,
                              isThumbnail: true,
                              placeholder: (_) => ColoredBox(
                                color: colorScheme.surfaceContainerHigh,
                              ),
                            )
                          else
                            ColoredBox(color: colorScheme.surfaceContainerHigh),
                          if (event.messageType == MessageTypes.Video)
                            const Center(
                              child: Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// A picture that pinches, double taps and scrolls to zoom, and reports
/// whether it is zoomed in so the viewer stops paging and dismissing.
class ZoomableMedia extends StatefulWidget {
  final Widget child;
  final VoidCallback onTap;
  final ValueChanged<bool> onZoomChanged;

  /// Told the scale against the fitted picture on every change, 1 when it
  /// fits.
  final ValueChanged<double>? onScaleChanged;
  final GestureScaleEndCallback? onInteractionEnd;

  const ZoomableMedia({
    required this.child,
    required this.onTap,
    required this.onZoomChanged,
    this.onScaleChanged,
    this.onInteractionEnd,
    super.key,
  });

  /// How far a double tap zooms in.
  static const doubleTapScale = 2.5;

  static const maxScale = 10.0;

  @override
  State<ZoomableMedia> createState() => ZoomableMediaState();
}

class ZoomableMediaState extends State<ZoomableMedia>
    with SingleTickerProviderStateMixin {
  final transform = TransformationController();
  late final AnimationController _animation = AnimationController(
    vsync: this,
    duration: FluffyThemes.animationDuration,
  );
  Animation<Matrix4>? _tween;
  Offset _doubleTapAt = Offset.zero;
  bool _zoomed = false;

  @override
  void initState() {
    super.initState();
    transform.addListener(_onTransform);
    _animation.addListener(() {
      final tween = _tween;
      if (tween != null) transform.value = tween.value;
    });
  }

  @override
  void dispose() {
    _animation.dispose();
    transform.dispose();
    super.dispose();
  }

  void _onTransform() {
    final scale = transform.value.getMaxScaleOnAxis();
    widget.onScaleChanged?.call(scale);
    final zoomed = scale > 1.01;
    if (zoomed == _zoomed) return;
    _zoomed = zoomed;
    widget.onZoomChanged(zoomed);
  }

  /// Zooms in around the double tap, or back out when zoomed in.
  void _onDoubleTap() => _animateTo(
    _zoomed ? 1 : ZoomableMedia.doubleTapScale,
    about: _doubleTapAt,
  );

  /// Zooms by [factor] about the middle of the view, within 1 and
  /// [ZoomableMedia.maxScale].
  void zoomBy(double factor) {
    final box = context.findRenderObject() as RenderBox?;
    if (box == null) return;
    final scale = (transform.value.getMaxScaleOnAxis() * factor).clamp(
      1.0,
      ZoomableMedia.maxScale,
    );
    // The point of the picture now in the middle stays there.
    final middle = transform.toScene(box.size.center(Offset.zero));
    final target = Matrix4.identity()
      ..translateByDouble(
        box.size.width / 2 - middle.dx * scale,
        box.size.height / 2 - middle.dy * scale,
        0,
        1,
      )
      ..scaleByDouble(scale, scale, 1, 1);
    _animateToMatrix(scale <= 1 ? Matrix4.identity() : target);
  }

  /// Fits the picture to the view again.
  void fit() => _animateToMatrix(Matrix4.identity());

  /// Scales the unzoomed picture by [scale] about [about].
  void _animateTo(double scale, {required Offset about}) {
    // Scales by s about p: x' = s * x - (s - 1) * p.
    _animateToMatrix(
      Matrix4.identity()
        ..translateByDouble(
          -(scale - 1) * about.dx,
          -(scale - 1) * about.dy,
          0,
          1,
        )
        ..scaleByDouble(scale, scale, 1, 1),
    );
  }

  void _animateToMatrix(Matrix4 target) {
    _tween = Matrix4Tween(begin: transform.value, end: target).animate(
      CurvedAnimation(parent: _animation, curve: FluffyThemes.animationCurve),
    );
    _animation.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: widget.onTap,
    onDoubleTapDown: (details) => _doubleTapAt = details.localPosition,
    onDoubleTap: _onDoubleTap,
    child: InteractiveViewer(
      transformationController: transform,
      minScale: 1.0,
      maxScale: ZoomableMedia.maxScale,
      panEnabled: _zoomed,
      onInteractionEnd: widget.onInteractionEnd,
      child: Center(child: widget.child),
    ),
  );
}
