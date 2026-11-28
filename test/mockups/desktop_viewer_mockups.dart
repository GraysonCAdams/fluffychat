// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: deprecated_member_use

// Mockups of a desktop media viewer, three layouts of the same parts, drawn
// with the app's dark theme and Material widgets. Nothing here is wired to
// a player or a timeline: [MockViewerState] holds what a frame shows, and
// desktop_viewer_sheet_test.dart renders frames of it to PNG.

import 'dart:math' as math;

import 'package:material_ui/material_ui.dart';

/// The three layouts on the sheet.
enum ViewerVariant {
  /// Everything floats over the picture on scrims and hides when the mouse
  /// rests, as Google Photos on the web and Quick Look do.
  overlay,

  /// Solid bars above and below; the picture only ever gets the space
  /// between them, as Windows Photos and Telegram Desktop do.
  docked,

  /// The chat's media as a rail of thumbnails down the right side, grouped
  /// by day, as the sidebar of macOS Preview does.
  rail,
}

/// One item of the chat's media.
class MockMedia {
  final ImageProvider image;
  final Size size;
  final bool video;
  final String label;

  const MockMedia(this.image, this.size, {this.video = false, this.label = ''});
}

/// What one frame of the viewer shows.
class MockViewerState {
  List<MockMedia> media;
  int index;

  /// Whether the bars, arrows and controls are on screen. They hide after
  /// the mouse rests for 2.5 s.
  bool chrome;
  bool filmstrip;

  /// Null fits the picture to the window; otherwise the scale against its
  /// pixels, shown as a percentage.
  double? zoom;

  /// How far through the video, 0 to 1.
  double position;
  bool playing;
  bool hoverVolume;

  /// The arrow the mouse is over, -1 left, 1 right, 0 neither.
  int hoverArrow;

  MockViewerState({
    required this.media,
    this.index = 0,
    this.chrome = true,
    this.filmstrip = false,
    this.zoom,
    this.position = 0.3,
    this.playing = true,
    this.hoverVolume = false,
    this.hoverArrow = 0,
  });

  MockMedia get current => media[index];
}

const _videoSeconds = 16;

/// Emphasized decelerate, md.sys.motion.easing.emphasized.decelerate.
const _enter = Cubic(0.05, 0.7, 0.1, 1);
const _short = Duration(milliseconds: 200); // md.sys.motion.duration.short4
const _medium = Duration(milliseconds: 300); // md.sys.motion.duration.medium2

class MockDesktopViewer extends StatelessWidget {
  final ViewerVariant variant;
  final MockViewerState state;

  const MockDesktopViewer({
    required this.variant,
    required this.state,
    super.key,
  });

  static const barHeight = 48.0;
  static const controlsHeight = 64.0;
  static const stripHeight = 76.0;
  static const railWidth = 120.0;

  @override
  Widget build(BuildContext context) => switch (variant) {
    ViewerVariant.overlay => _overlay(context),
    ViewerVariant.docked => _docked(context),
    ViewerVariant.rail => _rail(context),
  };

  Widget _fade(bool visible, Widget child) => IgnorePointer(
    ignoring: !visible,
    child: AnimatedOpacity(
      opacity: visible ? 1 : 0,
      duration: _short,
      curve: Curves.easeOut,
      child: child,
    ),
  );

  Widget _overlay(BuildContext context) {
    final video = state.current.video;
    final bottomStack =
        (video ? controlsHeight + 16 : 0.0) +
        (state.filmstrip ? stripHeight + 8 : 0.0);
    return ColoredBox(
      color: Colors.black,
      child: Stack(
        children: [
          Positioned.fill(child: _Media(state: state)),
          // Scrims under the bars, only as tall as the bars need.
          Positioned(
            left: 0,
            right: 0,
            top: 0,
            height: 128,
            child: _fade(state.chrome, const _Scrim(top: true)),
          ),
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _fade(
              state.chrome && bottomStack > 0,
              SizedBox(
                height: bottomStack + 64,
                child: const _Scrim(top: false),
              ),
            ),
          ),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: _fade(state.chrome, _TopBar(state: state, solid: false)),
          ),
          ..._arrows(context, inset: 16, bottomReserve: bottomStack),
          // One column at the bottom: the video controls above the strip,
          // so the two can never share a pixel.
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: _fade(
              state.chrome,
              Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (video)
                    Padding(
                      padding: const EdgeInsets.only(bottom: 16),
                      child: _VideoControls(state: state, floating: true),
                    ),
                  AnimatedSize(
                    duration: _medium,
                    curve: _enter,
                    child: state.filmstrip
                        ? Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: _Filmstrip(state: state),
                          )
                        : const SizedBox(width: double.infinity),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _docked(BuildContext context) {
    final theme = Theme.of(context);
    final video = state.current.video;
    return ColoredBox(
      color: Colors.black,
      child: Column(
        children: [
          _TopBar(state: state, solid: true),
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(child: _Media(state: state)),
                ..._arrows(context, inset: 16, bottomReserve: 0),
              ],
            ),
          ),
          if (video)
            ColoredBox(
              color: theme.colorScheme.surfaceContainerLowest,
              child: _VideoControls(state: state, floating: false),
            ),
          AnimatedSize(
            duration: _medium,
            curve: _enter,
            alignment: Alignment.topCenter,
            child: state.filmstrip
                ? ColoredBox(
                    color: theme.colorScheme.surfaceContainerLowest,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: 4),
                      child: _Filmstrip(state: state),
                    ),
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _rail(BuildContext context) {
    final theme = Theme.of(context);
    final video = state.current.video;
    return ColoredBox(
      color: Colors.black,
      child: Column(
        children: [
          _TopBar(state: state, solid: true),
          Expanded(
            child: Row(
              children: [
                Expanded(
                  child: Stack(
                    children: [
                      Positioned.fill(child: _Media(state: state)),
                      if (video)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 0,
                          height: controlsHeight + 72,
                          child: _fade(state.chrome, const _Scrim(top: false)),
                        ),
                      ..._arrows(
                        context,
                        inset: 16,
                        bottomReserve: video ? controlsHeight + 24 : 0,
                      ),
                      if (video)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: 24,
                          child: _fade(
                            state.chrome,
                            _VideoControls(state: state, floating: true),
                          ),
                        ),
                    ],
                  ),
                ),
                AnimatedContainer(
                  duration: _medium,
                  curve: _enter,
                  width: state.filmstrip ? railWidth : 0,
                  color: theme.colorScheme.surfaceContainerLowest,
                  child: ClipRect(
                    child: OverflowBox(
                      alignment: Alignment.centerLeft,
                      minWidth: railWidth,
                      maxWidth: railWidth,
                      child: _Rail(state: state),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _arrows(
    BuildContext context, {
    required double inset,
    required double bottomReserve,
  }) => [
    for (final side in [-1, 1])
      if (side < 0 ? state.index > 0 : state.index < state.media.length - 1)
        Positioned(
          left: side < 0 ? inset : null,
          right: side > 0 ? inset : null,
          top: 0,
          bottom: bottomReserve,
          child: Center(
            child: _fade(
              state.chrome,
              _Arrow(left: side < 0, hovered: state.hoverArrow == side),
            ),
          ),
        ),
  ];
}

class _Scrim extends StatelessWidget {
  final bool top;

  const _Scrim({required this.top});

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      gradient: LinearGradient(
        begin: top ? Alignment.topCenter : Alignment.bottomCenter,
        end: top ? Alignment.bottomCenter : Alignment.topCenter,
        // md.sys.color.scrim is black; eased so the edge never shows.
        colors: const [Color(0xCC000000), Color(0x80000000), Color(0x00000000)],
        stops: const [0, 0.45, 1],
      ),
    ),
  );
}

/// The picture or video frame, fitted to its box with letterboxing, or
/// scaled about its centre when zoomed.
class _Media extends StatelessWidget {
  final MockViewerState state;

  const _Media({required this.state});

  @override
  Widget build(BuildContext context) => LayoutBuilder(
    builder: (context, constraints) {
      final item = state.current;
      final box = constraints.biggest;
      final fit = math.min(
        box.width / item.size.width,
        box.height / item.size.height,
      );
      final scale = (state.zoom ?? fit) / fit;
      return AnimatedSwitcher(
        duration: _medium,
        switchInCurve: _enter,
        transitionBuilder: (child, animation) =>
            FadeTransition(opacity: animation, child: child),
        child: ClipRect(
          key: ValueKey(state.index),
          child: AnimatedScale(
            scale: scale,
            duration: _short,
            curve: _enter,
            child: Center(
              child: SizedBox(
                width: item.size.width * fit,
                height: item.size.height * fit,
                child: Image(image: item.image, fit: BoxFit.fill),
              ),
            ),
          ),
        ),
      );
    },
  );
}

/// The top bar: close, the sender and time, then the zoom and the actions,
/// then the window's own buttons, which the viewer keeps working.
class _TopBar extends StatelessWidget {
  final MockViewerState state;
  final bool solid;

  const _TopBar({required this.state, required this.solid});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final item = state.current;
    return Container(
      height: MockDesktopViewer.barHeight,
      color: solid ? theme.colorScheme.surfaceContainerLowest : null,
      child: Row(
        children: [
          const SizedBox(width: 4),
          const _BarButton(Icons.close, 'Close (Esc)'),
          const SizedBox(width: 4),
          CircleAvatar(
            radius: 14,
            backgroundColor: theme.colorScheme.primaryContainer,
            child: Text(
              'M',
              style: theme.textTheme.labelLarge?.copyWith(
                color: theme.colorScheme.onPrimaryContainer,
              ),
            ),
          ),
          const SizedBox(width: 10),
          Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Mia Chen', style: theme.textTheme.titleSmall),
              Text(
                'Nov 27, 2026 at 9:4${state.index} AM',
                style: theme.textTheme.bodySmall?.copyWith(
                  color: theme.colorScheme.onSurfaceVariant,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ],
          ),
          const SizedBox(width: 16),
          Text(
            '${state.index + 1} of ${state.media.length}',
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
          // Drags the window and double clicks maximise, as the app's own
          // title bar does.
          const Spacer(),
          if (!item.video) ...[
            _ZoomControl(zoom: state.zoom),
            const SizedBox(width: 8),
          ],
          _BarButton(
            Icons.view_carousel_outlined,
            state.filmstrip ? 'Hide filmstrip (F)' : 'Show filmstrip (F)',
            selected: state.filmstrip,
          ),
          const _BarDivider(),
          const _BarButton(Icons.download_outlined, 'Save as… (Ctrl+S)'),
          const _BarButton(Icons.shortcut_outlined, 'Forward'),
          const _BarButton(Icons.reply_outlined, 'Reply (R)'),
          const _BarButton(Icons.chat_outlined, 'Show in chat'),
          const _BarButton(Icons.more_vert, 'More'),
          const SizedBox(width: 8),
          const _CaptionButtons(),
        ],
      ),
    );
  }
}

class _BarDivider extends StatelessWidget {
  const _BarDivider();

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(horizontal: 6),
    child: SizedBox(
      height: 24,
      child: VerticalDivider(
        width: 1,
        color: Theme.of(context).colorScheme.outlineVariant,
      ),
    ),
  );
}

/// A 40 dp icon button (md.comp.icon-button.small), in a 44 dp pointer
/// target.
class _BarButton extends StatelessWidget {
  final IconData icon;
  final String tooltip;
  final bool selected;

  const _BarButton(this.icon, this.tooltip, {this.selected = false});

  @override
  Widget build(BuildContext context) => SizedBox(
    width: 44,
    height: 44,
    child: Center(
      child: IconButton(
        tooltip: tooltip,
        isSelected: selected,
        style: IconButton.styleFrom(
          minimumSize: const Size(40, 40),
          maximumSize: const Size(40, 40),
          padding: EdgeInsets.zero,
          backgroundColor: selected
              ? Theme.of(context).colorScheme.secondaryContainer
              : null,
        ),
        onPressed: () {},
        icon: Icon(icon, size: 22),
      ),
    ),
  );
}

/// Zoom out, the scale as a percentage (a click fits it again), zoom in.
class _ZoomControl extends StatelessWidget {
  final double? zoom;

  const _ZoomControl({required this.zoom});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final zoom = this.zoom;
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
            tooltip: 'Zoom out (Ctrl+−)',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: () {},
            icon: const Icon(Icons.remove),
          ),
          Tooltip(
            message: 'Fit to window (0)',
            child: SizedBox(
              width: 52,
              child: Text(
                zoom == null ? 'Fit' : '${(zoom * 100).round()}%',
                textAlign: TextAlign.center,
                style: theme.textTheme.labelLarge?.copyWith(
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
            ),
          ),
          IconButton(
            tooltip: 'Zoom in (Ctrl++)',
            iconSize: 20,
            visualDensity: VisualDensity.compact,
            onPressed: () {},
            icon: const Icon(Icons.add),
          ),
        ],
      ),
    );
  }
}

/// The window buttons as the app's title bar draws them: 46 wide, the bar's
/// height, thin 10 by 10 glyphs.
class _CaptionButtons extends StatelessWidget {
  const _CaptionButtons();

  @override
  Widget build(BuildContext context) {
    final color = Theme.of(context).colorScheme.onSurface;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final glyph in [0, 1, 2])
          SizedBox(
            width: 46,
            height: MockDesktopViewer.barHeight,
            child: CustomPaint(painter: _GlyphPainter(glyph, color)),
          ),
      ],
    );
  }
}

class _GlyphPainter extends CustomPainter {
  final int glyph;
  final Color color;

  _GlyphPainter(this.glyph, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = 1
      ..style = PaintingStyle.stroke;
    final c = size.center(Offset.zero);
    final r = Rect.fromCenter(center: c, width: 10, height: 10);
    switch (glyph) {
      case 0:
        canvas.drawLine(r.centerLeft, r.centerRight, paint);
      case 1:
        canvas.drawRect(r, paint);
      default:
        canvas.drawLine(r.topLeft, r.bottomRight, paint);
        canvas.drawLine(r.topRight, r.bottomLeft, paint);
    }
  }

  @override
  bool shouldRepaint(_GlyphPainter old) => old.color != color;
}

/// A 48 dp tonal circle beside the picture, larger under the mouse.
class _Arrow extends StatelessWidget {
  final bool left;
  final bool hovered;

  const _Arrow({required this.left, required this.hovered});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedScale(
      scale: hovered ? 1.08 : 1,
      duration: _short,
      child: Tooltip(
        message: left ? 'Previous (←)' : 'Next (→)',
        child: Container(
          width: 48,
          height: 48,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: theme.colorScheme.surfaceContainerHigh.withValues(
              alpha: hovered ? 0.95 : 0.75,
            ),
          ),
          child: Icon(
            left ? Icons.chevron_left : Icons.chevron_right,
            size: 28,
            color: theme.colorScheme.onSurface,
          ),
        ),
      ),
    );
  }
}

/// Play, the scrubber with the time either side, volume, speed and full
/// screen: one row, 64 high, as a floating pill
/// (md.comp.toolbar.floating) or docked across the window.
class _VideoControls extends StatelessWidget {
  final MockViewerState state;
  final bool floating;

  const _VideoControls({required this.state, required this.floating});

  String _time(double seconds) {
    final s = seconds.round();
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final tabular = theme.textTheme.labelMedium?.copyWith(
      fontFeatures: const [FontFeature.tabularFigures()],
      color: theme.colorScheme.onSurfaceVariant,
    );
    final row = SizedBox(
      height: MockDesktopViewer.controlsHeight,
      child: Row(
        children: [
          const SizedBox(width: 8),
          IconButton.filled(
            tooltip: state.playing ? 'Pause (Space)' : 'Play (Space)',
            onPressed: () {},
            icon: Icon(state.playing ? Icons.pause : Icons.play_arrow),
          ),
          const SizedBox(width: 12),
          Text(_time(state.position * _videoSeconds), style: tabular),
          Expanded(
            child: SliderTheme(
              data: SliderTheme.of(
                context,
              ).copyWith(overlayShape: SliderComponentShape.noOverlay),
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12),
                child: Slider(
                  year2023: false,
                  value: state.position,
                  secondaryTrackValue: math.min(1, state.position + 0.35),
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
          Text(_time(_videoSeconds.toDouble()), style: tabular),
          const SizedBox(width: 8),
          IconButton(
            tooltip: 'Mute (M)',
            onPressed: () {},
            icon: const Icon(Icons.volume_up_outlined),
          ),
          AnimatedContainer(
            duration: _short,
            curve: _enter,
            width: state.hoverVolume ? 96 : 0,
            child: ClipRect(
              child: OverflowBox(
                minWidth: 96,
                maxWidth: 96,
                alignment: Alignment.centerLeft,
                child: SliderTheme(
                  data: SliderTheme.of(
                    context,
                  ).copyWith(overlayShape: SliderComponentShape.noOverlay),
                  child: Slider(year2023: false, value: 0.8, onChanged: (_) {}),
                ),
              ),
            ),
          ),
          TextButton(
            onPressed: () {},
            style: TextButton.styleFrom(
              minimumSize: const Size(48, 40),
              foregroundColor: theme.colorScheme.onSurface,
            ),
            child: const Text('1×'),
          ),
          IconButton(
            tooltip: 'Full screen (F11)',
            onPressed: () {},
            icon: const Icon(Icons.fullscreen),
          ),
          const SizedBox(width: 8),
        ],
      ),
    );
    if (!floating) return row;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 760),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Material(
            color: theme.colorScheme.surfaceContainer.withValues(alpha: 0.92),
            shape: const StadiumBorder(),
            elevation: 3,
            child: row,
          ),
        ),
      ),
    );
  }
}

/// A thumbnail of one item; the one shown gets the primary outline.
class _Thumb extends StatelessWidget {
  final MockMedia item;
  final bool current;
  final double size;

  const _Thumb({required this.item, required this.current, this.size = 56});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AnimatedContainer(
      duration: _short,
      width: size,
      height: size,
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
              child: Image(image: item.image, fit: BoxFit.cover),
            ),
            if (item.video)
              Positioned(
                right: 4,
                bottom: 4,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 4,
                    vertical: 1,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(4),
                  ),
                  child: Text(
                    item.label,
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: Colors.white,
                      fontFeatures: const [FontFeature.tabularFigures()],
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// The chat's media in a row, centred on the one shown.
class _Filmstrip extends StatelessWidget {
  final MockViewerState state;

  const _Filmstrip({required this.state});

  @override
  Widget build(BuildContext context) => SizedBox(
    height: MockDesktopViewer.stripHeight,
    child: LayoutBuilder(
      builder: (context, constraints) {
        const step = 60.0;
        final shift = constraints.maxWidth / 2 - 28 - state.index * step;
        return ClipRect(
          child: Stack(
            children: [
              AnimatedPositioned(
                duration: _medium,
                curve: _enter,
                left: shift,
                top: 10,
                child: Row(
                  children: [
                    for (var i = 0; i < state.media.length; i++)
                      Padding(
                        padding: const EdgeInsets.only(right: 4),
                        child: _Thumb(
                          item: state.media[i],
                          current: i == state.index,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    ),
  );
}

/// The chat's media down the right side, grouped by day.
class _Rail extends StatelessWidget {
  final MockViewerState state;

  const _Rail({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final label = theme.textTheme.labelSmall?.copyWith(
      color: theme.colorScheme.onSurfaceVariant,
    );
    final days = {0: 'Wed, Nov 26', 4: 'Today'};
    return ListView(
      padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
      children: [
        for (var i = 0; i < state.media.length; i++) ...[
          if (days[i] case final day?)
            Padding(
              padding: const EdgeInsets.fromLTRB(4, 8, 0, 6),
              child: Text(day, style: label),
            ),
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: _Thumb(
              item: state.media[i],
              current: i == state.index,
              size: 96,
            ),
          ),
        ],
      ],
    );
  }
}
