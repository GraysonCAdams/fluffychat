// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/config/themes.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/image_viewer/video_player.dart';
import 'package:fluffychat/utils/date_time_extension.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:fluffychat/utils/windows_shell.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:fluffychat/widgets/mxc_image.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:video_player/video_player.dart';

import 'image_viewer.dart';
import 'image_viewer_view.dart';

/// The media viewer's layout on the desktop, after Google Photos on the web:
/// the picture fitted to the whole window with letterboxing, and over it, on
/// scrims, a top bar (close, sender and time, zoom, the actions and the
/// window buttons), arrows either side, and at the bottom the video controls
/// above the strip of the chat's media, both centred. The bars fade while the
/// mouse rests.
class DesktopImageViewerView extends StatelessWidget {
  final ImageViewerController controller;

  const DesktopImageViewerView(this.controller, {super.key});

  /// The top bar's height, the app's own title bar's.
  static const barHeight = 48.0;

  @override
  Widget build(BuildContext context) {
    final theme = FluffyThemes.buildTheme(context, Brightness.dark);
    final chrome = controller.chromeVisible;
    final event = controller.currentEvent;
    final video = event.messageType == MessageTypes.Video
        ? controller.currentVideo
        : null;
    final filmstrip =
        controller.filmstripVisible && controller.allEvents.length > 1;
    return Theme(
      data: theme,
      child: KeyboardListener(
        focusNode: controller.focusNode,
        autofocus: true,
        onKeyEvent: controller.onKeyEvent,
        // The window has no insets of its own; the title bar's padding is
        // the title bar's, which the viewer covers.
        child: MediaQuery.removePadding(
          context: context,
          removeTop: true,
          child: MouseRegion(
            onHover: (_) => controller.onPointerActivity(),
            cursor: chrome ? MouseCursor.defer : SystemMouseCursors.none,
            child: Scaffold(
              backgroundColor: Colors.black,
              body: Stack(
                children: [
                  Positioned.fill(child: _pages(context)),
                  const Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    height: 128,
                    child: _Scrim(top: true),
                  ).fadeWith(chrome),
                  if (video != null || filmstrip)
                    const Positioned(
                      bottom: 0,
                      left: 0,
                      right: 0,
                      height: 192,
                      child: _Scrim(top: false),
                    ).fadeWith(chrome),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: _onChrome(_TopBar(controller)).fadeWith(chrome),
                  ),
                  for (final next in [false, true])
                    if (next ? controller.canGoNext : controller.canGoBack)
                      Align(
                        alignment: next
                            ? Alignment.centerRight
                            : Alignment.centerLeft,
                        child: Padding(
                          padding: const EdgeInsets.all(16),
                          child: _onChrome(
                            _Arrow(next: next, controller: controller),
                          ),
                        ),
                      ).fadeWith(chrome),
                  // The controls and the strip share one column, so they
                  // stack and never meet.
                  Positioned(
                    left: 0,
                    right: 0,
                    bottom: 0,
                    child: _onChrome(
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (video != null)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 16),
                              child: ViewerVideoControls(
                                video,
                                fullScreen: controller.fullScreen,
                                onFullScreen: PlatformInfos.isWindows
                                    ? controller.toggleFullScreen
                                    : null,
                              ),
                            ),
                          if (filmstrip)
                            Padding(
                              padding: const EdgeInsets.only(bottom: 8),
                              child: ViewerFilmstrip(controller),
                            ),
                        ],
                      ),
                    ).fadeWith(chrome),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  /// Keeps the bars up while the mouse is on [child].
  Widget _onChrome(Widget child) => MouseRegion(
    onEnter: (_) => controller.onPointerOnChrome(true),
    onExit: (_) => controller.onPointerOnChrome(false),
    child: child,
  );

  Widget _pages(BuildContext context) => PageView.builder(
    physics: controller.zoomed
        ? const NeverScrollableScrollPhysics()
        : const PageScrollPhysics(),
    controller: controller.pageController,
    onPageChanged: controller.onPageChanged,
    itemCount: controller.allEvents.length,
    itemBuilder: (context, i) {
      final event = controller.allEvents[i];
      if (event.messageType == MessageTypes.Video) {
        // A click plays or pauses, as in a browser's video.
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTap: controller.togglePlay,
          child: EventVideoPlayer(
            event,
            desktop: true,
            startAt: event.eventId == controller.widget.event.eventId
                ? controller.widget.videoStartPosition
                : null,
            onController: (video) => controller.onVideoController(event, video),
          ),
        );
      }
      return ZoomableMedia(
        key: controller.zoomKey(event),
        onTap: controller.onPointerActivity,
        onZoomChanged: controller.onZoomChanged,
        onScaleChanged: (scale) => controller.onScaleChanged(event, scale),
        child: Hero(
          tag: event.eventId,
          child: MxcImage(
            key: ValueKey(event.eventId),
            event: event,
            fit: BoxFit.contain,
            isThumbnail: false,
            animated: true,
            // Keeps a 12 MP photo from becoming a 48 MB texture; 4096 px
            // still leaves headroom for zoom.
            maxDecodeDimension: 4096,
          ),
        ),
      );
    },
  );
}

extension on Widget {
  /// Fades this in and out with the bars, taking no pointer while hidden.
  Widget fadeWith(bool visible) => _Fade(visible: visible, child: this);
}

class _Fade extends StatelessWidget {
  final bool visible;
  final Widget child;

  const _Fade({required this.visible, required this.child});

  @override
  Widget build(BuildContext context) {
    final child = this.child;
    final faded = IgnorePointer(
      ignoring: !visible,
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: FluffyThemes.animationDuration,
        curve: FluffyThemes.animationCurve,
        child: child is Positioned ? child.child : child,
      ),
    );
    // A Positioned has to stay the Stack's direct child.
    if (child is Positioned) {
      return Positioned(
        left: child.left,
        top: child.top,
        right: child.right,
        bottom: child.bottom,
        width: child.width,
        height: child.height,
        child: faded,
      );
    }
    return faded;
  }
}

/// Black shading behind the bars that keeps them readable on a bright
/// picture (md.sys.color.scrim is black).
class _Scrim extends StatelessWidget {
  final bool top;

  const _Scrim({required this.top});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: top ? Alignment.topCenter : Alignment.bottomCenter,
        end: top ? Alignment.bottomCenter : Alignment.topCenter,
        colors: const [
          Color(0xCC000000),
          Color(0x80000000),
          Colors.transparent,
        ],
        stops: const [0, 0.45, 1],
      ),
    ),
  );
}

/// The top bar, as high as the app's title bar: close, the sender and time,
/// which of the chat's media this is, then the zoom, the actions and the
/// window buttons. Its empty middle moves the window.
class _TopBar extends StatelessWidget {
  final ImageViewerController controller;

  const _TopBar(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final event = controller.currentEvent;
    final sender = event.senderFromMemoryOrFallback;
    final name = sender.calcDisplayname();
    final sent = event.originServerTs;
    final subtle = theme.textTheme.bodySmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    final count = controller.allEvents.length;
    return SizedBox(
      height: DesktopImageViewerView.barHeight,
      child: Row(
        children: [
          const SizedBox(width: 4),
          _BarButton(
            icon: Icons.close,
            tooltip: l10n.close,
            onPressed: controller.close,
          ),
          const SizedBox(width: 4),
          Avatar(mxContent: sender.avatarUrl, name: name, size: 28),
          const SizedBox(width: 10),
          // Capped, not flexible, so the move area alone takes the free
          // space and the actions sit at the right edge.
          ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: (MediaQuery.sizeOf(context).width - 760).clamp(80, 320),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
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
                  style: subtle,
                ),
              ],
            ),
          ),
          if (count > 1) ...[
            const SizedBox(width: 16),
            Text(
              l10n.mediaPosition(controller.currentIndex + 1, count),
              style: subtle,
            ),
          ],
          const Expanded(child: WindowMoveArea(child: SizedBox.expand())),
          if (event.messageType != MessageTypes.Video) ...[
            _ZoomControl(controller),
            const SizedBox(width: 8),
          ],
          if (count > 1)
            _BarButton(
              icon: Icons.view_carousel_outlined,
              tooltip: controller.filmstripVisible
                  ? l10n.hideThumbnails
                  : l10n.showThumbnails,
              selected: controller.filmstripVisible,
              onPressed: controller.toggleFilmstrip,
            ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 6),
            child: SizedBox(
              height: 24,
              child: VerticalDivider(
                width: 1,
                color: theme.colorScheme.outlineVariant,
              ),
            ),
          ),
          Builder(
            builder: (context) => _BarButton(
              icon: Icons.download_outlined,
              tooltip: l10n.downloadFile,
              onPressed: () => controller.saveFileAction(context),
            ),
          ),
          _BarButton(
            icon: Icons.shortcut_outlined,
            tooltip: l10n.forward,
            onPressed: controller.forwardAction,
          ),
          if (controller.widget.onReply != null)
            _BarButton(
              icon: Icons.reply_outlined,
              tooltip: l10n.reply,
              onPressed: controller.replyAction,
            ),
          if (controller.widget.onShowInChat != null)
            _BarButton(
              icon: Icons.chat_outlined,
              tooltip: l10n.showInChat,
              onPressed: controller.showInChatAction,
            ),
          if (PlatformInfos.isWindows)
            PopupMenuButton<void>(
              tooltip: l10n.more,
              icon: const Icon(Icons.more_vert, size: 22),
              itemBuilder: (context) => [
                PopupMenuItem(
                  onTap: controller.toggleFullScreen,
                  child: ListTile(
                    leading: Icon(
                      controller.fullScreen
                          ? Icons.fullscreen_exit
                          : Icons.fullscreen,
                    ),
                    title: Text(
                      controller.fullScreen
                          ? l10n.exitFullScreen
                          : l10n.fullScreen,
                    ),
                  ),
                ),
              ],
            ),
          const SizedBox(width: 8),
          // The window's own buttons, which the viewer covers.
          const WindowButtons(),
        ],
      ),
    );
  }
}

/// A 40 dp icon button (md.comp.icon-button.small) in a 44 dp pointer
/// target.
class _BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final VoidCallback onPressed;
  final bool selected;

  const _BarButton({
    required this.icon,
    required this.tooltip,
    required this.onPressed,
    this.selected = false,
  });

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: 44,
    child: Center(
      child: IconButton(
        tooltip: tooltip,
        isSelected: selected,
        style: IconButton.styleFrom(
          fixedSize: const Size.square(40),
          padding: EdgeInsets.zero,
          backgroundColor: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
        ),
        onPressed: onPressed,
        icon: Icon(icon, size: 22),
      ),
    ),
  );
}

/// Zoom out, the zoom as a percentage of the fitted picture (a click fits
/// it again), zoom in.
class _ZoomControl extends StatelessWidget {
  final ImageViewerController controller;

  const _ZoomControl(this.controller);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final scale = controller.zoomScale;
    return Container(
      height: 36,
      decoration: ShapeDecoration(
        shape: const StadiumBorder(),
        color: theme.colorScheme.surfaceContainerHigh.withValues(alpha: 0.9),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: l10n.zoomOut,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: scale > 1.01 ? controller.zoomOut : null,
            icon: const Icon(Icons.remove),
          ),
          Tooltip(
            message: l10n.fitToWindow,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: controller.zoomFit,
              child: SizedBox(
                width: 52,
                height: 36,
                child: Center(
                  child: Text(
                    scale <= 1.01 ? l10n.fitShort : '${(scale * 100).round()}%',
                    style: theme.textTheme.labelLarge?.copyWith(
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: l10n.zoomIn,
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: scale < ZoomableMedia.maxScale - 0.01
                ? controller.zoomIn
                : null,
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// A 48 dp tonal circle beside the picture that pages to the previous or
/// next one.
class _Arrow extends StatelessWidget {
  final bool next;
  final ImageViewerController controller;

  const _Arrow({required this.next, required this.controller});

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return IconButton.filledTonal(
      tooltip: next ? l10n.next : l10n.previous,
      style: IconButton.styleFrom(fixedSize: const Size.square(48)),
      onPressed: next ? controller.nextImage : controller.prevImage,
      icon: Icon(next ? Icons.chevron_right : Icons.chevron_left, size: 28),
    );
  }
}

/// The video's controls in one 64 dp pill (md.comp.toolbar.floating),
/// centred: play, the time, the scrubber, the length, volume, speed and
/// full screen.
class ViewerVideoControls extends StatefulWidget {
  final VideoPlayerController video;
  final bool fullScreen;

  /// Turns full screen on or off; without it the button is left out.
  final VoidCallback? onFullScreen;

  const ViewerVideoControls(
    this.video, {
    required this.fullScreen,
    this.onFullScreen,
    super.key,
  });

  static const height = 64.0;
  static const maxWidth = 760.0;
  static const speeds = [0.5, 0.75, 1.0, 1.25, 1.5, 2.0];

  @override
  State<ViewerVideoControls> createState() => _ViewerVideoControlsState();
}

class _ViewerVideoControlsState extends State<ViewerVideoControls> {
  bool _volumeHovered = false;
  double _volumeBeforeMute = 1;

  static String _time(Duration d) {
    final s = d.inSeconds;
    final minutes = (s ~/ 60).toString();
    final seconds = (s % 60).toString().padLeft(2, '0');
    if (s >= 3600) {
      return '${s ~/ 3600}:${(s ~/ 60 % 60).toString().padLeft(2, '0')}:'
          '$seconds';
    }
    return '$minutes:$seconds';
  }

  void _toggleMute() {
    final video = widget.video;
    if (video.value.volume > 0) {
      _volumeBeforeMute = video.value.volume;
      video.setVolume(0);
    } else {
      video.setVolume(_volumeBeforeMute);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final tabular = theme.textTheme.labelMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: theme.colorScheme.onSurfaceVariant,
    );
    final sliderTheme = SliderTheme.of(
      context,
    ).copyWith(overlayShape: SliderComponentShape.noOverlay);
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(
          maxWidth: ViewerVideoControls.maxWidth,
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            key: const ValueKey('viewer-video-controls'),
            color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.92),
            shape: const StadiumBorder(),
            elevation: 3,
            child: SizedBox(
              height: ViewerVideoControls.height,
              child: ValueListenableBuilder(
                valueListenable: widget.video,
                builder: (context, value, _) {
                  final duration = value.duration;
                  final total = duration.inMilliseconds;
                  final position = total == 0
                      ? 0.0
                      : (value.position.inMilliseconds / total).clamp(0.0, 1.0);
                  final buffered = total == 0 || value.buffered.isEmpty
                      ? null
                      : (value.buffered.last.end.inMilliseconds / total).clamp(
                          position,
                          1.0,
                        );
                  final speed = value.playbackSpeed;
                  return Row(
                    children: [
                      const SizedBox(width: 8),
                      IconButton.filled(
                        tooltip: value.isPlaying
                            ? l10n.pauseVideo
                            : l10n.playVideo,
                        onPressed: value.isPlaying
                            ? widget.video.pause
                            : widget.video.play,
                        icon: Icon(
                          value.isPlaying ? Icons.pause : Icons.play_arrow,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Text(_time(value.position), style: tabular),
                      Expanded(
                        child: Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 12),
                          child: SliderTheme(
                            data: sliderTheme,
                            child: Slider(
                              key: const ValueKey('viewer-scrubber'),
                              // Flutter's opt-in to the 2024 slider (md.comp.slider).
                              // ignore: deprecated_member_use
                              year2023: false,
                              value: position,
                              secondaryTrackValue: buffered,
                              onChanged: total == 0
                                  ? null
                                  : (v) => widget.video.seekTo(
                                      Duration(
                                        milliseconds: (v * total).round(),
                                      ),
                                    ),
                            ),
                          ),
                        ),
                      ),
                      Text(_time(duration), style: tabular),
                      const SizedBox(width: 8),
                      MouseRegion(
                        onEnter: (_) => setState(() => _volumeHovered = true),
                        onExit: (_) => setState(() => _volumeHovered = false),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              tooltip: value.volume > 0
                                  ? l10n.mute
                                  : l10n.unmute,
                              onPressed: _toggleMute,
                              icon: Icon(
                                value.volume > 0
                                    ? Icons.volume_up_outlined
                                    : Icons.volume_off_outlined,
                              ),
                            ),
                            AnimatedContainer(
                              duration: FluffyThemes.animationDuration,
                              curve: FluffyThemes.animationCurve,
                              width: _volumeHovered ? 96 : 0,
                              child: ClipRect(
                                child: OverflowBox(
                                  minWidth: 96,
                                  maxWidth: 96,
                                  alignment: Alignment.centerLeft,
                                  child: SliderTheme(
                                    data: sliderTheme,
                                    child: Slider(
                                      // Flutter's opt-in to the 2024 slider (md.comp.slider).
                                      // ignore: deprecated_member_use
                                      year2023: false,
                                      value: value.volume.clamp(0.0, 1.0),
                                      onChanged: widget.video.setVolume,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                      PopupMenuButton<double>(
                        tooltip: l10n.playbackSpeed,
                        initialValue: speed,
                        onSelected: widget.video.setPlaybackSpeed,
                        itemBuilder: (context) => [
                          for (final s in ViewerVideoControls.speeds)
                            PopupMenuItem(value: s, child: Text(_speed(s))),
                        ],
                        child: SizedBox(
                          width: 48,
                          height: 40,
                          child: Center(
                            child: Text(
                              _speed(speed),
                              style: theme.textTheme.labelLarge,
                            ),
                          ),
                        ),
                      ),
                      if (widget.onFullScreen != null)
                        IconButton(
                          tooltip: widget.fullScreen
                              ? l10n.exitFullScreen
                              : l10n.fullScreen,
                          onPressed: widget.onFullScreen,
                          icon: Icon(
                            widget.fullScreen
                                ? Icons.fullscreen_exit
                                : Icons.fullscreen,
                          ),
                        ),
                      const SizedBox(width: 8),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _speed(double speed) =>
      '${speed == speed.roundToDouble() ? speed.toInt() : speed}×';
}

/// The chat's media in a row of thumbnails, the one shown outlined. The row
/// is centred in the window while it fits; a longer one scrolls, keeping
/// the one shown in view. A click shows that one.
class ViewerFilmstrip extends StatefulWidget {
  final ImageViewerController controller;

  const ViewerFilmstrip(this.controller, {super.key});

  static const size = 56.0;
  static const gap = 4.0;
  static const height = 76.0;

  @override
  State<ViewerFilmstrip> createState() => _ViewerFilmstripState();
}

class _ViewerFilmstripState extends State<ViewerFilmstrip> {
  final _scroll = ScrollController();
  int? _shown;

  @override
  void dispose() {
    _scroll.dispose();
    super.dispose();
  }

  /// Scrolls a row too long for the window to the one shown.
  void _follow(double viewport) {
    final index = widget.controller.currentIndex;
    if (_shown == index) return;
    _shown = index;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scroll.hasClients) return;
      const step = ViewerFilmstrip.size + ViewerFilmstrip.gap;
      final target = (index * step + ViewerFilmstrip.size / 2 - viewport / 2)
          .clamp(0.0, _scroll.position.maxScrollExtent);
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
    final count = controller.allEvents.length;
    final thumbs = [
      for (var i = 0; i < count; i++)
        Padding(
          padding: EdgeInsets.only(
            right: i < count - 1 ? ViewerFilmstrip.gap : 0,
          ),
          child: _Thumb(
            event: controller.allEvents[i],
            current: i == controller.currentIndex,
            onTap: () => controller.jumpTo(i),
          ),
        ),
    ];
    return SizedBox(
      key: const ValueKey('viewer-filmstrip'),
      height: ViewerFilmstrip.height,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const margin = 16.0;
          final width =
              count * ViewerFilmstrip.size + (count - 1) * ViewerFilmstrip.gap;
          if (width <= constraints.maxWidth - 2 * margin) {
            return Center(
              child: Row(
                key: const ValueKey('viewer-filmstrip-row'),
                mainAxisSize: MainAxisSize.min,
                children: thumbs,
              ),
            );
          }
          _follow(constraints.maxWidth);
          return ListView(
            controller: _scroll,
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
              horizontal: margin,
              vertical: (ViewerFilmstrip.height - ViewerFilmstrip.size) / 2,
            ),
            children: thumbs,
          );
        },
      ),
    );
  }
}

/// One thumbnail of the filmstrip, a video's with its length.
class _Thumb extends StatelessWidget {
  final Event event;
  final bool current;
  final VoidCallback onTap;

  const _Thumb({
    required this.event,
    required this.current,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final video = event.messageType == MessageTypes.Video;
    // The event states a video's length in milliseconds.
    final millis = (event.infoMap['duration'] as num?)?.round();
    final length = millis == null ? null : millis ~/ 1000;
    return Semantics(
      selected: current,
      button: true,
      child: GestureDetector(
        onTap: onTap,
        child: MouseRegion(
          cursor: SystemMouseCursors.click,
          child: AnimatedContainer(
            duration: FluffyThemes.animationDuration,
            curve: FluffyThemes.animationCurve,
            width: ViewerFilmstrip.size,
            height: ViewerFilmstrip.size,
            padding: const EdgeInsets.all(3),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(12),
              border: Border.all(
                color: current ? theme.colorScheme.primary : Colors.transparent,
                width: 2,
              ),
            ),
            child: ClipRRect(
              // 12 outside less the 3 inset keeps the corners concentric.
              borderRadius: BorderRadius.circular(9),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  Opacity(
                    opacity: current ? 1 : 0.72,
                    child: !video || event.hasThumbnail
                        ? MxcImage(
                            event: event,
                            width: ViewerFilmstrip.size,
                            height: ViewerFilmstrip.size,
                            fit: BoxFit.cover,
                            isThumbnail: true,
                            placeholder: (_) => ColoredBox(
                              color: theme.colorScheme.surfaceContainerHigh,
                            ),
                          )
                        : ColoredBox(
                            color: theme.colorScheme.surfaceContainerHigh,
                          ),
                  ),
                  if (video)
                    Positioned(
                      right: 3,
                      bottom: 3,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 1,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.black.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(4),
                        ),
                        child: length == null
                            ? const Icon(
                                Icons.play_arrow_rounded,
                                color: Colors.white,
                                size: 14,
                              )
                            : Text(
                                '${length ~/ 60}:'
                                '${(length % 60).toString().padLeft(2, '0')}',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  color: Colors.white,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
