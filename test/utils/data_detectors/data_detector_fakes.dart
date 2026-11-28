// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

import 'package:fluffychat/utils/data_detectors/dart_data_detector.dart';
import 'package:fluffychat/utils/data_detectors/data_detector_platform.dart';
import 'package:fluffychat/utils/data_detectors/detection.dart';
import 'package:fluffychat/utils/data_detectors/detection_actions.dart';
import 'package:material_ui/material_ui.dart';

/// Seam's own detector, with Android's actions added when [android] is
/// set: their titles and order as the stock TextClassifier gives them.
class FakeDetector implements DataDetectorPlatform {
  FakeDetector({required this.android, this.icons = const {}});

  final bool android;

  /// App icons (PNG) by action title, standing in for the ones Android
  /// supplies.
  final Map<String, Uint8List> icons;
  final List<(String, int)> ran = [];

  static const _system = {
    DetectionType.address: ['Map'],
    DetectionType.phone: ['Call', 'Add', 'Message'],
    DetectionType.dateTime: ['View', 'Schedule'],
    DetectionType.flight: ['Track'],
  };

  @override
  Future<List<Detection>> detect(
    String text, {
    required DateTime referenceTime,
  }) async => [
    for (final d in DartDataDetector.detectSync(
      text,
      referenceTime: referenceTime,
    ))
      Detection(
        type: d.type,
        start: d.start,
        end: d.end,
        text: d.text,
        when: d.when,
        hasTime: d.hasTime,
        token: android ? d.text : null,
        systemActions: android
            ? [
                for (final t in _system[d.type]!)
                  SystemAction(title: t, icon: icons[t]),
              ]
            : const [],
      ),
  ];

  @override
  Future<bool> runSystemAction(Detection detection, int index) async {
    ran.add((detection.text, index));
    return true;
  }
}

class FakeLauncher extends DetectionLauncher {
  final List<Object> calls = [];

  @override
  Future<bool> openUri(Uri uri) async {
    calls.add(uri);
    return true;
  }

  @override
  Future<void> copy(String text) async => calls.add('copy $text');

  @override
  Future<bool> runSystemAction(Detection detection, int index) =>
      DataDetectorPlatform.instance.runSystemAction(detection, index);

  @override
  void openRoom(BuildContext context, String roomId) =>
      calls.add('room $roomId');

  @override
  Future<bool> openCalendarFile(String ics) async {
    calls.add(ics);
    return true;
  }
}
