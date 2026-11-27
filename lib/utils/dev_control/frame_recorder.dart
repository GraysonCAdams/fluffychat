// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:developer' show Timeline;
import 'dart:math' as math;
import 'dart:ui' show FramePhase, FrameTiming;

import 'package:flutter/scheduler.dart';

/// One frame as the engine reported it, times in microseconds.
class RecordedFrame {
  final int number;

  /// When the frame's vsync arrived, on the engine's monotonic clock.
  final int vsyncStart;
  final int rasterFinish;
  final int build;
  final int raster;
  final int vsyncOverhead;

  /// From vsync to the end of raster ([FrameTiming.totalSpan]).
  final int total;

  const RecordedFrame({
    required this.number,
    required this.vsyncStart,
    required this.rasterFinish,
    required this.build,
    required this.raster,
    required this.vsyncOverhead,
    required this.total,
  });

  factory RecordedFrame.fromTiming(FrameTiming t) => RecordedFrame(
    number: t.frameNumber,
    vsyncStart: t.timestampInMicroseconds(FramePhase.vsyncStart),
    rasterFinish: t.timestampInMicroseconds(FramePhase.rasterFinish),
    build: t.buildDuration.inMicroseconds,
    raster: t.rasterDuration.inMicroseconds,
    vsyncOverhead: t.vsyncOverhead.inMicroseconds,
    total: t.totalSpan.inMicroseconds,
  );

  /// The longer of build and raster: the thread that set the frame's pace.
  int get worst => math.max(build, raster);

  Map<String, Object> toJson() => {
    'number': number,
    'vsyncStartUs': vsyncStart,
    'buildMs': _ms(build),
    'rasterMs': _ms(raster),
    'vsyncOverheadMs': _ms(vsyncOverhead),
    'totalMs': _ms(total),
  };
}

double _ms(num us) => (us / 10).round() / 100;

/// Keeps the engine's per-frame timings ([SchedulerBinding.addTimingsCallback])
/// and summarises the frames since a named mark.
///
/// The engine hands timings over in batches, in profile and release builds
/// about once a second, so a summary read straight after an interaction can
/// miss its last frames; [DevControl] waits before it reads.
class FrameRecorder {
  /// How many frames are kept; older ones are dropped.
  final int capacity;

  FrameRecorder({this.capacity = 20000});

  final List<RecordedFrame> _frames = [];
  final Map<String, int> _marks = {};
  bool _listening = false;

  /// The last observed gap between [Timeline.now] and a frame's raster
  /// finish. Marks are times on [Timeline.now]'s clock and are compared with
  /// frame times, which only works while both read the same monotonic clock;
  /// a gap this large means they do not, and marks fall back to frame
  /// numbers.
  int? clockSkewUs;
  static const int _maxSkewUs = 5 * 1000 * 1000;

  final Map<String, int> _markFrameNumbers = {};

  Iterable<RecordedFrame> get frames => _frames;

  void start() {
    if (_listening) return;
    _listening = true;
    SchedulerBinding.instance.addTimingsCallback(_onTimings);
  }

  void stop() {
    if (!_listening) return;
    _listening = false;
    SchedulerBinding.instance.removeTimingsCallback(_onTimings);
  }

  void _onTimings(List<FrameTiming> timings) =>
      addAll(timings.map(RecordedFrame.fromTiming), now: Timeline.now);

  /// Adds [frames]; [now] is [Timeline.now] when they arrived.
  void addAll(Iterable<RecordedFrame> frames, {required int now}) {
    _frames.addAll(frames);
    if (_frames.isNotEmpty) clockSkewUs = now - _frames.last.rasterFinish;
    final excess = _frames.length - capacity;
    if (excess > 0) _frames.removeRange(0, excess);
  }

  bool get _clocksAgree =>
      clockSkewUs == null || clockSkewUs!.abs() < _maxSkewUs;

  /// Starts a span called [name] now, replacing an earlier one of that name.
  void mark(String name, {int? now}) {
    _marks[name] = now ?? Timeline.now;
    _markFrameNumbers[name] = _frames.isEmpty ? -1 : _frames.last.number;
  }

  bool hasMark(String name) => _marks.containsKey(name);

  void clear() {
    _frames.clear();
    _marks.clear();
    _markFrameNumbers.clear();
  }

  /// The frames after mark [since] (all kept frames when null) and up to
  /// mark [until] (the newest frame when null).
  List<RecordedFrame> between({String? since, String? until}) {
    bool after(RecordedFrame f, String name) => _clocksAgree
        ? f.vsyncStart >= _marks[name]!
        : f.number > _markFrameNumbers[name]!;
    return [
      for (final f in _frames)
        if ((since == null || after(f, since)) &&
            (until == null || !after(f, until)))
          f,
    ];
  }

  /// A summary of [frames] against a frame budget of [budgetMs] (one vsync
  /// at the display's refresh rate).
  static Map<String, Object?> summarise(
    List<RecordedFrame> frames, {
    required double budgetMs,
    bool detail = false,
  }) {
    final budgetUs = budgetMs * 1000;
    Map<String, double> spread(int Function(RecordedFrame) of) {
      if (frames.isEmpty) return const {};
      final values = frames.map(of).toList()..sort();
      double pct(double p) => _ms(
        values[((values.length - 1) * p).round().clamp(0, values.length - 1)],
      );
      return {
        'avg': _ms(values.reduce((a, b) => a + b) / values.length),
        'p50': pct(0.5),
        'p90': pct(0.9),
        'p99': pct(0.99),
        'max': _ms(values.last),
      };
    }

    // Vsyncs that passed without a frame while frames kept coming. Flutter
    // draws nothing while nothing changes, so this only means dropped frames
    // across a span that animates the whole time.
    var missed = 0;
    var longestGap = 0;
    for (var i = 1; i < frames.length; i++) {
      final gap = frames[i].vsyncStart - frames[i - 1].vsyncStart;
      longestGap = math.max(longestGap, gap);
      missed += math.max(0, (gap / budgetUs).round() - 1);
    }
    final spanUs = frames.isEmpty
        ? 0
        : frames.last.rasterFinish - frames.first.vsyncStart;
    final worst = [...frames]..sort((a, b) => b.worst.compareTo(a.worst));
    return {
      'frames': frames.length,
      'spanMs': _ms(spanUs),
      'fps': spanUs <= 0
          ? null
          : (frames.length / (spanUs / 1e6) * 10).round() / 10,
      'budgetMs': (budgetMs * 100).round() / 100,
      'overBudget': frames.where((f) => f.worst > budgetUs).length,
      'over16ms': frames.where((f) => f.worst > 16667).length,
      'over8ms': frames.where((f) => f.worst > 8333).length,
      'buildOverBudget': frames.where((f) => f.build > budgetUs).length,
      'rasterOverBudget': frames.where((f) => f.raster > budgetUs).length,
      'missedVsyncs': missed,
      'longestGapMs': _ms(longestGap),
      'buildMs': spread((f) => f.build),
      'rasterMs': spread((f) => f.raster),
      'totalMs': spread((f) => f.total),
      'worst': [for (final f in worst.take(5)) f.toJson()],
      if (detail) 'all': [for (final f in frames) f.toJson()],
    };
  }
}
