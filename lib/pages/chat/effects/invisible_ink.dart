// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/effect_haptics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/scheduler.dart';
import 'package:material_ui/material_ui.dart';

/// Hides [child], a message bubble, under ink that is rubbed away.
///
/// Hidden, nothing of the bubble's content is painted: the bubble is
/// covered edge to edge in fine, sharp specks that drift slowly and
/// twinkle (see [InkParticles]). A finger (or the mouse pointer) wipes the
/// ink away where it passes, in a soft-edged track reaching [brushRadius]
/// to either side (see [InkMask]): the content shows there and nowhere
/// else, and the specks at the edge of the track thin out and are pushed
/// away from it. A tap clears one patch. What was cleared holds while the
/// finger is down and for [holdAfterRub] after it lifts, then the ink
/// closes in again from the edges of the track over [concealDuration]. A
/// finger that clears fresh ink feels light ticks.
///
/// Once [revealThreshold] of the ink has been rubbed away the rest of it
/// goes by itself, spreading out from what is clear over
/// [completeDuration] with one firmer tick. The bubble then stays
/// readable until it has not been touched for [revealedIdle], and the ink
/// comes back over the whole of it at once.
///
/// A drag that starts on the ink belongs to the ink: it wins against a
/// list scrolling under it or a sheet being dragged, once the finger has
/// moved [rubSlop]. Taps and long presses still reach the widgets around
/// the bubble.
///
/// A finger that came down on one ink bubble rubs every other on the same
/// page it passes over, each with its own share to reach and its own
/// time to come back. Bubbles under one [InvisibleInkGroup] are one
/// surface instead.
class InvisibleInk extends StatefulWidget {
  final Widget child;

  /// Painted behind the hidden content and over the parts of it that are
  /// still covered, so the bubble keeps its shape.
  final Color bubbleColor;

  /// The colour of the specks, the bubble's text colour.
  final Color dustColor;
  final BorderRadius borderRadius;

  /// Whether the specks move, the ink is rubbed away and a swipe ticks.
  /// Off under reduced motion: the specks hold still, a touch reveals the
  /// whole bubble at once and the ink does not claim drags.
  final bool animate;

  const InvisibleInk({
    required this.child,
    required this.bubbleColor,
    required this.dustColor,
    required this.borderRadius,
    this.animate = true,
    super.key,
  });

  /// How long a bubble revealed whole by one touch, under reduced motion,
  /// stays readable after the finger lifts.
  static const concealAfter = Duration(seconds: 5);

  /// How much of the ink is rubbed away before the rest goes by itself,
  /// as a share of the bubble.
  static const revealThreshold = 0.8;

  /// How long the rest of the ink takes to go.
  static const completeDuration = Duration(milliseconds: 350);

  /// How long a bubble rubbed clear stays readable without a touch.
  static const revealedIdle = Duration(seconds: 4);

  /// How strong the tick is when the rest of the ink goes, against 0.5
  /// for a finger landing on the ink.
  static const completeTick = 0.8;

  /// How long rubbed ink stays clear after the finger lifts.
  static const holdAfterRub = Duration(seconds: 2);

  /// How long the ink takes to close in again.
  static const concealDuration = Duration(milliseconds: 2500);

  /// How far from the finger the ink is disturbed. It is clear out to a
  /// little over half of this and thins out over the rest.
  static const brushRadius = 30.0;

  /// How far a finger moves on the ink before the drag is the ink's.
  static const rubSlop = 6.0;

  /// How far a finger moves over the ink between two ticks.
  static const tickDistance = 14.0;

  @override
  State<InvisibleInk> createState() => InvisibleInkState();
}

/// Makes the ink bubbles under it one surface, as over a photo and its
/// caption: [InvisibleInk.revealThreshold] is a share of all of them
/// together, the rest of the ink goes from all of them at once, a touch
/// on any of them keeps all of them as they are, and the ink comes back
/// over all of them together.
class InvisibleInkGroup extends StatefulWidget {
  final Widget child;

  const InvisibleInkGroup({required this.child, super.key});

  @override
  State<InvisibleInkGroup> createState() => _InvisibleInkGroupState();
}

class _InvisibleInkGroupState extends State<InvisibleInkGroup> {
  final members = <InvisibleInkState>[];

  @override
  Widget build(BuildContext context) =>
      _InkGroupScope(group: this, child: widget.child);
}

class _InkGroupScope extends InheritedWidget {
  final _InvisibleInkGroupState group;

  const _InkGroupScope({required this.group, required super.child});

  @override
  bool updateShouldNotify(_InkGroupScope oldWidget) => oldWidget.group != group;
}

class InvisibleInkState extends State<InvisibleInk>
    with TickerProviderStateMixin {
  /// Every ink bubble on screen.
  static final _mounted = <InvisibleInkState>{};

  /// The group this bubble is in, if any, and the bubbles that act as
  /// one with it, itself included.
  _InvisibleInkGroupState? _group;
  late final _alone = [this];
  List<InvisibleInkState> get _members => _group?.members ?? _alone;

  /// The page the bubble is on.
  ModalRoute<Object?>? _route;

  /// The other bubbles the finger that is down on this one has rubbed.
  final _carried = <InvisibleInkState>{};

  late final AnimationController _fade =
      AnimationController(vsync: this, duration: InvisibleInk.concealDuration)
        ..addListener(() {
          _mask.fade = Curves.easeInOut.transform(_fade.value);
          _sync();
        })
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          _mask.clear();
          _fade.value = 0;
          _sync();
        });

  /// Runs while the rest of the ink goes, past [InvisibleInk.revealThreshold].
  late final AnimationController _complete =
      AnimationController(vsync: this, duration: InvisibleInk.completeDuration)
        ..addListener(() {
          _mask.fade = -Curves.easeIn.transform(_complete.value) * _reach;
        })
        ..addStatusListener((status) {
          if (status != AnimationStatus.completed) return;
          _mask.fill();
          _complete.value = 0;
          _sync();
        });

  /// How far [_complete] has to push the mask's edge to clear the point
  /// farthest from what was rubbed.
  double _reach = 0;
  late final Ticker _ticker = createTicker(
    (elapsed) => _time.value = elapsed.inMicroseconds / 1e6,
  );
  final _time = ValueNotifier<double>(0);
  final _particles = InkParticles(math.Random(3));
  final _mask = InkMask();
  Timer? _concealTimer;

  /// Where the finger last was, while it is on the ink.
  Offset? _last;

  /// Where the finger was at the last tick, while it is on the ink.
  Offset? _lastTick;

  /// What the last build showed of [isHidden] and [isRevealed].
  bool _hidden = true;
  bool _revealed = false;

  /// Whether the whole bubble can be read.
  bool get isRevealed => _mask.isFull;

  /// Whether nothing of the bubble can be read.
  bool get isHidden => _mask.isEmpty;

  /// How much of the content shows at [position] in the bubble, from 0
  /// under untouched ink to 1 where it has been rubbed clear.
  double shownAt(Offset position) => _mask.shownAt(position);

  /// How much of the ink is rubbed away, as a share of the bubble.
  double get cleared => _mask.cleared;

  /// Whether the rest of the ink is going by itself.
  bool get isFinishing => _complete.isAnimating;

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final group = context
        .dependOnInheritedWidgetOfExactType<_InkGroupScope>()
        ?.group;
    if (group != _group) {
      _group?.members.remove(this);
      _group = group;
      group?.members.add(this);
    }
    _route = ModalRoute.of(context);
    _syncTicker();
  }

  @override
  void didUpdateWidget(InvisibleInk oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncTicker();
  }

  void _syncTicker() {
    if (widget.animate && !_ticker.isActive) _ticker.start();
    if (!widget.animate && _ticker.isActive) _ticker.stop();
  }

  /// Rebuilds when the bubble has become hidden or wholly readable, or
  /// has stopped being so.
  void _sync() {
    if (!mounted) return;
    if (_hidden == isHidden && _revealed == isRevealed) return;
    setState(() {
      _hidden = isHidden;
      _revealed = isRevealed;
    });
  }

  /// Fits the mask to the bubble. False before the bubble is laid out.
  bool _fitMask() {
    final size = context.size;
    if (size == null || size.isEmpty) return false;
    _mask.resize(size);
    return true;
  }

  /// Stops the ink closing in on this bubble and those it is one with.
  void _wake() {
    for (final member in _members) {
      member._wakeOne();
    }
  }

  /// Stops the ink closing in, keeping what is still clear as it is. Ink
  /// coming back over a bubble that was wholly readable is cleared again.
  void _wakeOne() {
    _concealTimer?.cancel();
    _fade.stop();
    if (_fade.value == 0) return;
    if (!_mask.isFilled) _mask.bake();
    _fade.value = 0;
  }

  /// How much of the ink is rubbed away over this bubble and those it is
  /// one with, as a share of them all.
  double _clearedOverMembers() {
    final members = _members;
    if (members.length == 1) return _mask.cleared;
    var all = 0.0, clear = 0.0;
    for (final member in members) {
      final size = member.context.size;
      if (size == null) continue;
      final area = size.width * size.height;
      all += area;
      clear += area * member._mask.cleared;
    }
    return all == 0 ? 0 : clear / all;
  }

  /// Sends the rest of the ink away, outwards from what is clear, or
  /// evenly from a bubble nothing of which is. Felt with [tick].
  void _finish({required bool tick}) {
    if (isRevealed || _complete.isAnimating || !_fitMask()) return;
    _reach = InkMask.edgeDepth - _mask.spread(InvisibleInk.brushRadius);
    _complete.forward(from: 0);
    _sync();
    if (!tick) return;
    EffectHaptics.instance.play(
      const HapticPattern([
        HapticBeat(
          HapticPrimitive.tick,
          Duration.zero,
          scale: InvisibleInk.completeTick,
        ),
      ]),
    );
  }

  /// Clears the whole bubble at once.
  void revealAll() {
    _wake();
    if (isRevealed || !_fitMask()) return;
    _mask.fill();
    _sync();
  }

  /// Wipes the ink from where the pointer last was to [position]. [down]
  /// starts a new track there. With [tick], clearing fresh ink is felt:
  /// when the finger lands, and again every [InvisibleInk.tickDistance]
  /// it moves.
  void _rub(Offset position, {required bool down, bool tick = true}) {
    if (!widget.animate) {
      revealAll();
      return;
    }
    _wake();
    if (isRevealed || _complete.isAnimating || !_fitMask()) return;
    final cleared = _mask.stroke(
      down ? position : _last ?? position,
      position,
      InvisibleInk.brushRadius,
    );
    _last = position;
    _sync();
    if (_clearedOverMembers() >= InvisibleInk.revealThreshold) {
      for (final member in _members) {
        member._finish(tick: identical(member, this));
      }
      return;
    }
    if (!tick || !cleared) return;
    final lastTick = _lastTick;
    if (!down &&
        lastTick != null &&
        (position - lastTick).distance < InvisibleInk.tickDistance) {
      return;
    }
    _lastTick = position;
    EffectHaptics.instance.play(
      HapticPattern([
        HapticBeat(
          HapticPrimitive.tick,
          Duration.zero,
          scale: down ? 0.5 : 0.3,
        ),
      ]),
    );
  }

  /// Rubs this bubble where the finger of [event] is and, with it, any
  /// other on the page the finger is over or within the brush's reach of.
  void _rubUnder(PointerEvent event, {required bool down}) {
    _rub(event.localPosition, down: down);
    if (!widget.animate) return;
    for (final other in _mounted) {
      if (identical(other, this) ||
          !other.widget.animate ||
          other._route != _route) {
        continue;
      }
      final position = other._near(event.position);
      if (position != null) {
        _carried.add(other);
        other._rub(position, down: other._last == null);
      } else if (_carried.contains(other)) {
        // A new track when the finger comes back.
        other._last = null;
      }
    }
  }

  /// Where the point [global] on the screen is in this bubble, if it is
  /// within the brush's reach of it.
  Offset? _near(Offset global) {
    final box = context.findRenderObject();
    if (box is! RenderBox || !box.attached || !box.hasSize) return null;
    final position = box.globalToLocal(global);
    final reach = (Offset.zero & box.size).inflate(InvisibleInk.brushRadius);
    return reach.contains(position) ? position : null;
  }

  /// The finger has lifted from this bubble and from those it rubbed on
  /// its way.
  void _lift() {
    _release();
    for (final other in _carried) {
      if (other.mounted) other._release();
    }
    _carried.clear();
  }

  /// Starts the wait for the ink to come back, on this bubble and those
  /// it is one with.
  void _release() {
    for (final member in _members) {
      member._releaseOne();
    }
  }

  void _releaseOne() {
    _last = null;
    _lastTick = null;
    _concealTimer?.cancel();
    if (isHidden) return;
    final Duration wait;
    if (!widget.animate) {
      wait = InvisibleInk.concealAfter;
    } else if (isRevealed || _complete.isAnimating) {
      wait = InvisibleInk.revealedIdle;
    } else {
      wait = InvisibleInk.holdAfterRub;
    }
    _concealTimer = Timer(wait, conceal);
  }

  /// Covers the bubble again.
  void conceal() {
    _concealTimer?.cancel();
    if (!mounted || isHidden || _fade.isAnimating) return;
    if (_complete.isAnimating) {
      _complete.stop();
      _mask.fill();
      _complete.value = 0;
    }
    if (widget.animate) {
      _fade.forward(from: 0);
    } else {
      _mask.clear();
      _sync();
    }
  }

  @override
  void dispose() {
    _mounted.remove(this);
    _group?.members.remove(this);
    _concealTimer?.cancel();
    _ticker.dispose();
    _fade.dispose();
    _complete.dispose();
    _time.dispose();
    _mask.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget ink = Listener(
      onPointerDown: (event) => _rubUnder(event, down: true),
      onPointerMove: (event) => _rubUnder(event, down: false),
      onPointerUp: (_) => _lift(),
      onPointerCancel: (_) => _lift(),
      child: Semantics(
        label: _hidden ? L10n.of(context).invisibleInkHidden : null,
        // A screen reader's tap, which cannot rub, shows the whole bubble.
        onTap: _hidden
            ? () {
                revealAll();
                _release();
              }
            : null,
        child: ExcludeSemantics(
          excluding: _hidden,
          child: ClipRRect(
            borderRadius: widget.borderRadius,
            child: Stack(
              children: [
                Positioned.fill(child: ColoredBox(color: widget.bubbleColor)),
                // The content, painted only around what has been rubbed.
                ClipRect(
                  key: const ValueKey('invisible_ink_content'),
                  clipper: _ShownClipper(_mask),
                  child: widget.child,
                ),
                if (!_revealed)
                  Positioned.fill(
                    child: IgnorePointer(
                      child: CustomPaint(
                        key: const ValueKey('invisible_ink_particles'),
                        painter: _InkPainter(
                          _particles,
                          _time,
                          _mask,
                          widget.dustColor,
                          widget.bubbleColor.withValues(alpha: 1),
                          MediaQuery.devicePixelRatioOf(context),
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
    if (widget.animate && !_revealed) {
      ink = RawGestureDetector(
        excludeFromSemantics: true,
        gestures: {
          _RubGestureRecognizer:
              GestureRecognizerFactoryWithHandlers<_RubGestureRecognizer>(
                () => _RubGestureRecognizer(debugOwner: this),
                (_) {},
              ),
        },
        child: ink,
      );
    }
    return MouseRegion(
      onHover: (event) =>
          _rub(event.localPosition, down: _last == null, tick: false),
      onExit: (_) => _release(),
      child: ink,
    );
  }
}

/// Claims a touch on the ink as a rub once it has moved
/// [InvisibleInk.rubSlop] in any direction, so the drag is not taken by a
/// scrolling list or a sheet around the bubble. It reports nothing: the
/// ink follows the pointer by itself. A touch that lifts before moving
/// that far is left to the tap and long press recognizers around it.
class _RubGestureRecognizer extends OneSequenceGestureRecognizer {
  _RubGestureRecognizer({super.debugOwner})
    : super(
        supportedDevices: const {
          PointerDeviceKind.touch,
          PointerDeviceKind.stylus,
          PointerDeviceKind.invertedStylus,
        },
      );

  Offset _origin = Offset.zero;
  bool _resolved = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    super.addAllowedPointer(event);
    _origin = event.position;
    _resolved = false;
  }

  @override
  void handleEvent(PointerEvent event) {
    if (event is PointerMoveEvent) {
      if (!_resolved &&
          (event.position - _origin).distance > InvisibleInk.rubSlop) {
        _resolved = true;
        resolve(GestureDisposition.accepted);
      }
    } else if (event is PointerUpEvent || event is PointerCancelEvent) {
      if (!_resolved) {
        _resolved = true;
        resolve(GestureDisposition.rejected);
      }
      stopTrackingPointer(event.pointer);
    }
  }

  @override
  void acceptGesture(int pointer) => _resolved = true;

  @override
  void rejectGesture(int pointer) {
    _resolved = true;
    stopTrackingPointer(pointer);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {}

  @override
  String get debugDescription => 'ink rub';
}

/// Clips the content to the box around what has been rubbed clear.
class _ShownClipper extends CustomClipper<Rect> {
  final InkMask mask;

  _ShownClipper(this.mask) : super(reclip: mask);

  @override
  Rect getClip(Size size) {
    // A mask fitted to another size says nothing about this one.
    if (mask.isEmpty || mask.size != size) return Rect.zero;
    return mask.bounds.intersect(Offset.zero & size);
  }

  @override
  bool shouldReclip(_ShownClipper oldClipper) => oldClipper.mask != mask;
}

/// Where the ink of one bubble has been rubbed away: a coarse grid of
/// points over the bubble, each holding how deep under the brush it has
/// been, from 0 (untouched) to 1 (on the finger's path).
///
/// [shown] is what is seen of that: 1 where the content is clear, 0 where
/// the ink is whole, and a soft edge between. As [fade] goes from 0 to 1
/// the edge moves in from the outside of every track to its middle, until
/// nothing is shown. A [fade] below 0 moves the edge outwards instead,
/// which after [spread] reaches every point of the bubble. A mask that
/// has been filled shows the whole bubble, and [fade] covers all of it
/// evenly.
///
/// The mask also holds the cover: the bubble's colour over every point
/// in step with [shown], opaque where the ink is whole, drawn over the
/// content as one mesh.
class InkMask extends ChangeNotifier {
  /// How far apart the points are, in pixels, on a bubble small enough
  /// to stay under [maxPoints].
  static const spacing = 6.0;

  /// The most points a bubble is covered with.
  static const maxPoints = 6000;

  /// How steep the edge of a track is: [shown] is 1 wherever the depth,
  /// less [fade], is at least one part in this many.
  static const _edge = 2.5;

  /// The depth from which a point is shown in full.
  static const edgeDepth = 1 / _edge;

  /// The depth [spread] starts a point at that no stroke has reached.
  static const _unreached = -1e6;

  /// The smallest gain in depth that counts as fresh ink cleared.
  static const _fresh = 0.02;

  Size _size = Size.zero;
  int _columns = 0;
  int _rows = 0;
  double _stepX = 1;
  double _stepY = 1;
  Float32List _depth = Float32List(0);
  Float32List _shown = Float32List(0);
  double _fade = 0;
  bool _empty = true;
  bool _filled = false;

  /// The sum of [shown] over every point.
  double _shownSum = 0;

  /// The box around every point a stroke has reached.
  double _left = 0;
  double _top = 0;
  double _right = 0;
  double _bottom = 0;

  Float32List _coverPositions = Float32List(0);
  Int32List _coverColors = Int32List(0);
  Uint16List _coverIndices = Uint16List(0);
  ui.Vertices? _cover;
  int? _coverColor;

  /// The size of the bubble the mask was last fitted to.
  Size get size => _size;

  /// How many points there are across and down.
  int get columns => _columns;
  int get rows => _rows;

  /// How far apart the points are across and down, in pixels.
  double get stepX => _stepX;
  double get stepY => _stepY;

  /// How much of the content shows at each point, row by row.
  Float32List get shown => _shown;

  /// Whether nothing is shown.
  bool get isEmpty => _empty;

  /// Whether the whole bubble is shown.
  bool get isFull => _filled && _fade == 0;

  /// Whether the mask was filled, and has not been cleared since.
  bool get isFilled => _filled;

  /// How much of the content shows, as a share of the bubble.
  double get cleared => _empty ? 0 : _shownSum / _shown.length;

  /// The box around everything that is shown, or has been since the mask
  /// was last empty.
  Rect get bounds =>
      _empty ? Rect.zero : Rect.fromLTRB(_left, _top, _right, _bottom);

  /// How far the ink has closed in again, from 0 to 1.
  double get fade => _fade;

  set fade(double value) {
    if (value == _fade) return;
    _fade = value;
    if (_empty) return;
    if (_filled) {
      final shown = _ease((1 - value) * edgeDepth);
      _shown.fillRange(0, _shown.length, shown);
      _shownSum = shown * _shown.length;
    } else {
      var sum = 0.0;
      for (var i = 0; i < _depth.length; i++) {
        sum += _shown[i] = _ease(_depth[i] - value);
      }
      _shownSum = sum;
    }
    _changed();
  }

  static double _ease(double depth) {
    final t = depth * _edge;
    if (t <= 0) return 0;
    if (t >= 1) return 1;
    return t * t * (3 - 2 * t);
  }

  void _changed() {
    _cover?.dispose();
    _cover = null;
    notifyListeners();
  }

  /// Fits the grid to a bubble of [size]. A bubble that has changed size
  /// starts covered again.
  void resize(Size size) {
    if (size == _size) return;
    _size = size;
    var step = spacing;
    final area = size.width * size.height;
    if (area / (step * step) > maxPoints) step = math.sqrt(area / maxPoints);
    _columns = math.max(2, (size.width / step).ceil() + 1);
    _rows = math.max(2, (size.height / step).ceil() + 1);
    _stepX = size.width / (_columns - 1);
    _stepY = size.height / (_rows - 1);
    final count = _columns * _rows;
    _depth = Float32List(count);
    _shown = Float32List(count);
    _coverColors = Int32List(count);
    _coverPositions = Float32List(count * 2);
    for (var row = 0; row < _rows; row++) {
      for (var column = 0; column < _columns; column++) {
        final p = (row * _columns + column) * 2;
        _coverPositions[p] = column * _stepX;
        _coverPositions[p + 1] = row * _stepY;
      }
    }
    _coverIndices = Uint16List((_columns - 1) * (_rows - 1) * 6);
    var n = 0;
    for (var row = 0; row < _rows - 1; row++) {
      for (var column = 0; column < _columns - 1; column++) {
        final v = row * _columns + column;
        _coverIndices[n++] = v;
        _coverIndices[n++] = v + 1;
        _coverIndices[n++] = v + _columns;
        _coverIndices[n++] = v + 1;
        _coverIndices[n++] = v + _columns + 1;
        _coverIndices[n++] = v + _columns;
      }
    }
    _fade = 0;
    _shownSum = 0;
    _empty = true;
    _filled = false;
    _cover?.dispose();
    _cover = null;
  }

  /// Carries the depths on from the strokes to the rest of the bubble,
  /// falling at the brush's rate with the distance from what was rubbed,
  /// so below 0 past the rim of a brush of [radius]. Returns the lowest
  /// depth, 0 on a mask no stroke has touched. [shown] stays as it is until [fade] goes below 0, and the box
  /// of [bounds] becomes the whole bubble.
  double spread(double radius) {
    _left = 0;
    _top = 0;
    _right = _size.width;
    _bottom = _size.height;
    if (_empty) {
      // Nothing to spread from: every point is as far from showing.
      _empty = _columns == 0;
      return 0;
    }
    for (var i = 0; i < _depth.length; i++) {
      if (_depth[i] <= 0) _depth[i] = _unreached;
    }
    final across = _stepX / radius, down = _stepY / radius;
    final aslant = math.sqrt(across * across + down * down);
    // Each point takes the best of its neighbours less the step between
    // them: those before it on the way down, those after on the way up.
    void take(int i, int column, int row, int sign) {
      var depth = _depth[i];
      final beside = column - sign;
      final other = row - sign;
      if (beside >= 0 && beside < _columns) {
        depth = math.max(depth, _depth[i - sign] - across);
      }
      if (other >= 0 && other < _rows) {
        final o = i - sign * _columns;
        depth = math.max(depth, _depth[o] - down);
        if (column > 0) depth = math.max(depth, _depth[o - 1] - aslant);
        if (column < _columns - 1) {
          depth = math.max(depth, _depth[o + 1] - aslant);
        }
      }
      _depth[i] = depth;
    }

    for (var row = 0; row < _rows; row++) {
      for (var column = 0; column < _columns; column++) {
        take(row * _columns + column, column, row, 1);
      }
    }
    var lowest = 1.0;
    for (var row = _rows - 1; row >= 0; row--) {
      for (var column = _columns - 1; column >= 0; column--) {
        final i = row * _columns + column;
        take(i, column, row, -1);
        if (_depth[i] < lowest) lowest = _depth[i];
      }
    }
    return lowest;
  }

  /// Wipes the ink within [radius] of the line from [from] to [to], most
  /// on the line and less towards the rim. Returns whether fresh ink was
  /// cleared, which going back over a track does not do.
  bool stroke(Offset from, Offset to, double radius) {
    if (_columns == 0 || _filled) return false;
    final reach = radius + math.max(_stepX, _stepY);
    final left = math.min(from.dx, to.dx) - reach;
    final top = math.min(from.dy, to.dy) - reach;
    final right = math.max(from.dx, to.dx) + reach;
    final bottom = math.max(from.dy, to.dy) + reach;
    final firstColumn = math.max(0, (left / _stepX).ceil());
    final lastColumn = math.min(_columns - 1, (right / _stepX).floor());
    final firstRow = math.max(0, (top / _stepY).ceil());
    final lastRow = math.min(_rows - 1, (bottom / _stepY).floor());
    if (firstColumn > lastColumn || firstRow > lastRow) return false;
    final ax = from.dx, ay = from.dy;
    final abx = to.dx - ax, aby = to.dy - ay;
    final length2 = abx * abx + aby * aby;
    var fresh = false;
    var touched = false;
    for (var row = firstRow; row <= lastRow; row++) {
      final y = row * _stepY;
      for (var column = firstColumn; column <= lastColumn; column++) {
        final x = column * _stepX;
        // The nearest point of the line to this one.
        var t = length2 == 0
            ? 0.0
            : ((x - ax) * abx + (y - ay) * aby) / length2;
        if (t < 0) t = 0;
        if (t > 1) t = 1;
        final dx = x - (ax + abx * t), dy = y - (ay + aby * t);
        final depth = 1 - math.sqrt(dx * dx + dy * dy) / radius;
        final i = row * _columns + column;
        final before = _depth[i];
        if (depth <= before) continue;
        _depth[i] = depth;
        final shown = _ease(depth - _fade);
        _shownSum += shown - _shown[i];
        _shown[i] = shown;
        touched = true;
        if (depth > before + _fresh) fresh = true;
      }
    }
    if (!touched) return false;
    final boxLeft = math.max(0.0, left);
    final boxTop = math.max(0.0, top);
    final boxRight = math.min(_size.width, right);
    final boxBottom = math.min(_size.height, bottom);
    if (_empty) {
      _left = boxLeft;
      _top = boxTop;
      _right = boxRight;
      _bottom = boxBottom;
      _empty = false;
    } else {
      _left = math.min(_left, boxLeft);
      _top = math.min(_top, boxTop);
      _right = math.max(_right, boxRight);
      _bottom = math.max(_bottom, boxBottom);
    }
    _changed();
    return fresh;
  }

  /// Shows the whole bubble.
  void fill() {
    if (_columns == 0) return;
    _depth.fillRange(0, _depth.length, 1);
    _shown.fillRange(0, _shown.length, 1);
    _shownSum = _shown.length.toDouble();
    _fade = 0;
    _left = 0;
    _top = 0;
    _right = _size.width;
    _bottom = _size.height;
    _empty = false;
    _filled = true;
    _changed();
  }

  /// Covers the whole bubble.
  void clear() {
    if (_empty) return;
    _depth.fillRange(0, _depth.length, 0);
    _shown.fillRange(0, _shown.length, 0);
    _shownSum = 0;
    _fade = 0;
    _empty = true;
    _filled = false;
    _changed();
  }

  /// Takes what [fade] has closed in out of the depths and sets [fade]
  /// back to 0, leaving [shown] as it is, so a new stroke adds to what
  /// can still be seen.
  void bake() {
    if (_fade == 0) return;
    for (var i = 0; i < _depth.length; i++) {
      _depth[i] = math.max(0, _depth[i] - _fade);
    }
    _fade = 0;
  }

  /// How much of the content shows at [position] in the bubble, between
  /// the points around it.
  double shownAt(Offset position) {
    if (_empty) return 0;
    final fx = (position.dx / _stepX).clamp(0.0, _columns - 1.0);
    final fy = (position.dy / _stepY).clamp(0.0, _rows - 1.0);
    final column = math.min(fx.floor(), _columns - 2);
    final row = math.min(fy.floor(), _rows - 2);
    final tx = fx - column, ty = fy - row;
    final i = row * _columns + column;
    final above = _shown[i] + (_shown[i + 1] - _shown[i]) * tx;
    final below =
        _shown[i + _columns] +
        (_shown[i + _columns + 1] - _shown[i + _columns]) * tx;
    return above + (below - above) * ty;
  }

  /// The cover in [color], built again only after the mask has changed.
  ui.Vertices cover(Color color) {
    final argb = color.toARGB32();
    final built = _cover;
    if (built != null && _coverColor == argb) return built;
    built?.dispose();
    final rgb = argb & 0x00FFFFFF;
    for (var i = 0; i < _shown.length; i++) {
      _coverColors[i] = (((1 - _shown[i]) * 255).round() << 24) | rgb;
    }
    _coverColor = argb;
    return _cover = ui.Vertices.raw(
      ui.VertexMode.triangles,
      _coverPositions,
      colors: _coverColors,
      indices: _coverIndices,
    );
  }

  @override
  void dispose() {
    _cover?.dispose();
    _cover = null;
    super.dispose();
  }
}

/// The ink: a dense field of hard-edged specks, each a square one or one
/// and a half pixels across. Every speck circles its home slowly and
/// flickers at its own rate, some of them going dark between flashes. The
/// field is laid out on a unit square, so it fits a bubble of any size.
///
/// A frame is one `drawVertices` call: two triangles to a speck, coloured
/// at the vertices. Nothing is blurred and no image is built.
class InkParticles {
  /// The most specks a bubble is covered with.
  static const maxCount = 3200;

  /// How many square pixels of bubble there are to each speck.
  static const areaPerParticle = 5.5;

  /// How far a speck strays from its home, in pixels.
  static const drift = 3.5;

  /// How far a speck at the edge of rubbed ink is pushed away from the
  /// clear side, in pixels.
  static const scatter = 8.0;

  /// How much of the content shows at a speck's place before the speck
  /// is left out.
  static const _clear = 0.96;

  /// Home position (x, y), phase and rate of each speck, all 0 to 1.
  final Float32List _specks = Float32List(maxCount * 4);

  /// The corners of every speck's square, four (x, y) pairs each.
  final Float32List positions = Float32List(maxCount * 8);

  /// The colour of each corner, as 0xAARRGGBB.
  final Int32List colors = Int32List(maxCount * 4);

  static final Uint16List _indices = () {
    final indices = Uint16List(maxCount * 6);
    for (var i = 0; i < maxCount; i++) {
      final v = i * 4;
      indices.setAll(i * 6, [v, v + 1, v + 2, v + 1, v + 3, v + 2]);
    }
    return indices;
  }();

  static final Float32List _sine = Float32List.fromList([
    for (var i = 0; i < 256; i++) math.sin(i / 256 * math.pi * 2),
  ]);

  static final _paint = Paint();

  /// The sine of [turns] full turns.
  static double _sin(double turns) => _sine[(turns * 256).floor() & 255];

  InkParticles(math.Random random) {
    for (var i = 0; i < _specks.length; i++) {
      _specks[i] = random.nextDouble();
    }
  }

  /// How many specks cover a bubble of [size].
  static int countFor(Size size) =>
      math.min(maxCount, (size.width * size.height / areaPerParticle).round());

  /// Works out where every speck is over [size] at [time] and how bright,
  /// into [positions] and [colors], and returns how many specks there are.
  ///
  /// Corners are snapped to the pixels of a screen with [devicePixelRatio]
  /// pixels to the logical pixel, so each speck is a sharp square. Specks
  /// where [mask] shows the content are left out; those on the soft edge
  /// of what it shows are dimmed and pushed away from the clear side, up
  /// to [scatter].
  int layout(
    Size size,
    double time,
    Color color, {
    double devicePixelRatio = 1,
    InkMask? mask,
  }) {
    final count = countFor(size);
    final rgb = color.toARGB32() & 0x00FFFFFF;
    final dpr = devicePixelRatio;
    final masked = mask != null && !mask.isEmpty && mask.size == size;
    final shown = masked ? mask.shown : null;
    final columns = masked ? mask.columns : 0;
    final rows = masked ? mask.rows : 0;
    final perStepX = masked ? 1 / mask.stepX : 0.0;
    final perStepY = masked ? 1 / mask.stepY : 0.0;
    var n = 0;
    for (var i = 0; i < count; i++) {
      final phase = _specks[i * 4 + 2];
      final rate = _specks[i * 4 + 3];
      // A slow circle round home: a turn every 3 to 7 seconds.
      final turn = phase + time * (0.14 + rate * 0.2);
      var x = _specks[i * 4] * size.width + _sin(turn + 0.25) * drift;
      var y = _specks[i * 4 + 1] * size.height + _sin(turn) * drift;
      // Flickering two to six times a second; the square of the wave
      // keeps a speck dim most of the time and bright in flashes.
      final wave = 0.5 + 0.5 * _sin(phase * 7 + time * (2 + rate * 4));
      var alpha = 0.22 + 0.78 * wave * wave;
      if (shown != null) {
        // What the mask shows here, between the four points around the
        // speck, and which way that falls off.
        var fx = x * perStepX, fy = y * perStepY;
        if (fx < 0) fx = 0;
        if (fy < 0) fy = 0;
        var column = fx.floor(), row = fy.floor();
        if (column > columns - 2) column = columns - 2;
        if (row > rows - 2) row = rows - 2;
        var tx = fx - column, ty = fy - row;
        if (tx > 1) tx = 1;
        if (ty > 1) ty = 1;
        final o = row * columns + column;
        final s00 = shown[o], s10 = shown[o + 1];
        final s01 = shown[o + columns], s11 = shown[o + columns + 1];
        if (s00 + s10 + s01 + s11 > 0) {
          final above = s00 + (s10 - s00) * tx;
          final below = s01 + (s11 - s01) * tx;
          final clear = above + (below - above) * ty;
          if (clear >= _clear) continue;
          final gx = (s10 - s00) * (1 - ty) + (s11 - s01) * ty;
          final gy = (s01 - s00) * (1 - tx) + (s11 - s10) * tx;
          final slope = math.sqrt(gx * gx + gy * gy);
          if (slope > 1e-4) {
            final push = clear * scatter / slope;
            x -= gx * push;
            y -= gy * push;
          }
          alpha *= 1 - clear;
        }
      }
      // One speck in three is a pixel and a half across, the rest one.
      final side = ((i % 3 == 0 ? 1.5 : 1.0) * dpr).round() / dpr;
      final left = (x * dpr).floor() / dpr;
      final top = (y * dpr).floor() / dpr;
      final p = n * 8;
      positions[p] = left;
      positions[p + 1] = top;
      positions[p + 2] = left + side;
      positions[p + 3] = top;
      positions[p + 4] = left;
      positions[p + 5] = top + side;
      positions[p + 6] = left + side;
      positions[p + 7] = top + side;
      final argb = ((color.a * alpha * 255).round() << 24) | rgb;
      colors.fillRange(n * 4, n * 4 + 4, argb);
      n++;
    }
    return n;
  }

  /// Paints the specks over [size] at [time] in one draw call.
  void paint(
    Canvas canvas,
    Size size,
    double time,
    Color color, {
    double devicePixelRatio = 1,
    InkMask? mask,
  }) {
    final n = layout(
      size,
      time,
      color,
      devicePixelRatio: devicePixelRatio,
      mask: mask,
    );
    if (n == 0) return;
    final vertices = ui.Vertices.raw(
      ui.VertexMode.triangles,
      Float32List.sublistView(positions, 0, n * 8),
      colors: Int32List.sublistView(colors, 0, n * 4),
      indices: Uint16List.sublistView(_indices, 0, n * 6),
    );
    // BlendMode.dst keeps the colours of the vertices as they are.
    canvas.drawVertices(vertices, BlendMode.dst, _paint);
    vertices.dispose();
  }
}

/// Paints the cover over the content that is still hidden, where any
/// of it is shown, and the specks over that.
class _InkPainter extends CustomPainter {
  final InkParticles particles;
  final ValueListenable<double> time;
  final InkMask mask;
  final Color color;
  final Color coverColor;
  final double devicePixelRatio;

  _InkPainter(
    this.particles,
    this.time,
    this.mask,
    this.color,
    this.coverColor,
    this.devicePixelRatio,
  ) : super(repaint: Listenable.merge([time, mask]));

  static final _paint = Paint();

  @override
  void paint(Canvas canvas, Size size) {
    if (!mask.isEmpty && mask.size == size) {
      // BlendMode.dst keeps the colours of the vertices as they are.
      canvas.drawVertices(mask.cover(coverColor), BlendMode.dst, _paint);
    }
    particles.paint(
      canvas,
      size,
      time.value,
      color,
      devicePixelRatio: devicePixelRatio,
      mask: mask,
    );
  }

  @override
  bool shouldRepaint(_InkPainter oldDelegate) =>
      oldDelegate.color != color ||
      oldDelegate.coverColor != coverColor ||
      oldDelegate.devicePixelRatio != devicePixelRatio;
}
