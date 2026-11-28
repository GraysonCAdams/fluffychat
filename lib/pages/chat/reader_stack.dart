// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:math' as math;

import 'package:fluffychat/pages/chat/status_mark.dart';
import 'package:fluffychat/widgets/avatar.dart';
import 'package:material_ui/material_ui.dart';

/// One face in a [ReaderStack].
@immutable
class StackedReader {
  /// Tells the face apart from the others, so it keeps its place in the
  /// stack as readers come.
  final String id;
  final String name;
  final Uri? avatar;

  const StackedReader({required this.id, required this.name, this.avatar});
}

/// The faces of who has read a message, as an overlapping avatar stack.
///
/// The newest reader is in front at the start; each face behind overlaps
/// the one before it by 6dp of its 16dp (38%), with a 1.5dp knockout
/// cutout ring between them, as the group collage and [StatusMark] cut
/// theirs. Past [maxFaces] faces a "+N" disc closes the stack.
///
/// A live change animates: a new face scales and fades in at the front
/// while the others slide back, a face pushed into "+N" fades out as it
/// slides there, and "+N" counts up. The first build, and every change with
/// reduced motion, shows the stack as it is.
class ReaderStack extends StatefulWidget {
  /// Newest first.
  final List<StackedReader> readers;

  /// The colour of the "+N" count.
  final Color color;

  const ReaderStack({super.key, required this.readers, required this.color});

  static const int maxFaces = 3;
  static const double size = 16;

  /// How far each face sits from the one in front of it.
  static const double step = 10;

  /// The gap cut out of a face around the one in front of it.
  static const double cutout = 1.5;

  /// The space between the stack and the check after it.
  static const double gap = 4;

  static const String _moreId = '+';

  @override
  State<ReaderStack> createState() => _ReaderStackState();
}

class _Slot {
  final AnimationController position;
  final AnimationController shown;
  StackedReader? reader;
  bool leaving = false;

  _Slot(this.position, this.shown, this.reader);

  void dispose() {
    position.dispose();
    shown.dispose();
  }
}

class _ReaderStackState extends State<ReaderStack>
    with TickerProviderStateMixin {
  final Map<String, _Slot> _slots = {};

  static const _duration = Duration(milliseconds: 250);

  int get _extra => widget.readers.length - ReaderStack.maxFaces;

  /// The ids at the stack's places, front first, "+N" last.
  List<String> _ids() => [
    for (final reader in widget.readers.take(ReaderStack.maxFaces)) reader.id,
    if (_extra > 0) ReaderStack._moreId,
  ];

  StackedReader? _readerOf(String id) =>
      widget.readers.where((reader) => reader.id == id).firstOrNull;

  void _sync({required bool animate}) {
    final ids = _ids();
    for (final MapEntry(key: id, value: slot) in _slots.entries.toList()) {
      if (ids.contains(id)) continue;
      if (!animate) {
        _slots.remove(id)!.dispose();
        continue;
      }
      // A face pushed out of the stack slides to the "+N" place as it fades.
      slot.leaving = true;
      slot.position.animateTo(
        ReaderStack.maxFaces.toDouble(),
        duration: _duration,
        curve: emphasizedDecelerate,
      );
      slot.shown.reverse().whenComplete(() {
        if (!mounted || _slots[id] != slot || !slot.leaving) return;
        setState(() => _slots.remove(id)!.dispose());
      });
    }
    for (var place = 0; place < ids.length; place++) {
      final id = ids[place];
      final slot = _slots[id];
      if (slot == null) {
        _slots[id] = _Slot(
          AnimationController(
            vsync: this,
            upperBound: ReaderStack.maxFaces + 1,
            value: place.toDouble(),
          ),
          AnimationController(
            vsync: this,
            duration: _duration,
            value: animate ? 0 : 1,
          )..forward(),
          _readerOf(id),
        );
        continue;
      }
      slot
        ..reader = _readerOf(id)
        ..leaving = false;
      if (animate) {
        slot.position.animateTo(
          place.toDouble(),
          duration: _duration,
          curve: emphasizedDecelerate,
        );
        slot.shown.forward();
      } else {
        slot.position.value = place.toDouble();
        slot.shown.value = 1;
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _sync(animate: false);
  }

  @override
  void didUpdateWidget(ReaderStack old) {
    super.didUpdateWidget(old);
    _sync(animate: !MediaQuery.disableAnimationsOf(context));
  }

  @override
  void dispose() {
    for (final slot in _slots.values) {
      slot.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return AnimatedBuilder(
      animation: Listenable.merge([
        for (final slot in _slots.values) ...[slot.position, slot.shown],
      ]),
      builder: (context, _) {
        // Painted back to front: the face furthest along first.
        final slots = _slots.entries.toList()
          ..sort(
            (a, b) => b.value.position.value.compareTo(a.value.position.value),
          );
        double scaleOf(_Slot slot) =>
            emphasizedDecelerate.transform(slot.shown.value);
        // The stack's width follows its faces as they grow and slide, and
        // the gap before the check opens with the first face.
        final width = slots
            .where((entry) => !entry.value.leaving)
            .map(
              (entry) =>
                  entry.value.position.value * ReaderStack.step +
                  ReaderStack.size * scaleOf(entry.value),
            )
            .fold<double>(0, math.max);
        return SizedBox(
          width:
              width + ReaderStack.gap * math.min(1, width / ReaderStack.size),
          height: ReaderStack.size,
          child: Stack(
            clipBehavior: Clip.none,
            children: [
              for (var i = 0; i < slots.length; i++)
                PositionedDirectional(
                  key: ValueKey(slots[i].key),
                  start: slots[i].value.position.value * ReaderStack.step,
                  top: 0,
                  child: ClipPath(
                    // Cut out the face painted next, in front of this one.
                    clipper: i + 1 < slots.length
                        ? ReaderCutout(
                            dx:
                                (slots[i + 1].value.position.value -
                                    slots[i].value.position.value) *
                                ReaderStack.step *
                                (rtl ? -1 : 1),
                            radius:
                                ReaderStack.size /
                                    2 *
                                    scaleOf(slots[i + 1].value) +
                                ReaderStack.cutout,
                          )
                        : null,
                    child: Opacity(
                      opacity: slots[i].value.shown.value,
                      child: Transform.scale(
                        scale: scaleOf(slots[i].value),
                        child: slots[i].key == ReaderStack._moreId
                            ? _More(
                                count: math.max(_extra, 1),
                                fill: scheme.surfaceContainerHighest,
                                color: widget.color,
                              )
                            : Avatar(
                                mxContent: slots[i].value.reader?.avatar,
                                name: slots[i].value.reader?.name,
                                size: ReaderStack.size,
                              ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

/// The "+N" disc at the back of the stack, counting up to [count].
class _More extends StatelessWidget {
  final int count;
  final Color fill;
  final Color color;

  const _More({required this.count, required this.fill, required this.color});

  @override
  Widget build(BuildContext context) => Container(
    width: ReaderStack.size,
    height: ReaderStack.size,
    alignment: Alignment.center,
    decoration: BoxDecoration(color: fill, shape: BoxShape.circle),
    child: TweenAnimationBuilder<double>(
      tween: Tween(end: count.toDouble()),
      duration: MediaQuery.disableAnimationsOf(context)
          ? Duration.zero
          : const Duration(milliseconds: 300),
      builder: (context, value, _) => Text(
        '+${value.round()}',
        style: TextStyle(
          fontSize: 8,
          height: 1,
          fontWeight: FontWeight.w600,
          color: color,
        ),
      ),
    ),
  );
}

/// A face's box less the circle of the face in front of it, [dx] along
/// from its own centre, grown by the cutout ring.
class ReaderCutout extends CustomClipper<Path> {
  final double dx;
  final double radius;

  const ReaderCutout({required this.dx, required this.radius});

  @override
  Path getClip(Size size) => Path.combine(
    PathOperation.difference,
    Path()..addRect((Offset.zero & size).inflate(2)),
    Path()..addOval(
      Rect.fromCircle(
        center: Offset(size.width / 2 + dx, size.height / 2),
        radius: radius,
      ),
    ),
  );

  @override
  bool shouldReclip(ReaderCutout old) => old.dx != dx || old.radius != radius;
}
