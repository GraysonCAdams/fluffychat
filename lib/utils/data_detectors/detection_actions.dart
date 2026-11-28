// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:io';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/data_detectors/data_detector_platform.dart';
import 'package:fluffychat/utils/data_detectors/detection.dart';
import 'package:fluffychat/utils/merged_contacts/phone_number.dart';
import 'package:fluffychat/utils/merged_contacts/suggestion_service.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart' as launcher;

/// Seam's own actions for a detection. On Android and iOS the system's
/// actions come first and Seam adds [messageInSeam] and [copy]; elsewhere
/// these are all there is.
enum SeamActionKind {
  map,
  call,
  addToCalendar,
  trackFlight,
  messageInSeam,
  copy,
}

/// One entry of a detection's menu or assist chip: either the platform's
/// action number [systemIndex], shown with the handling app's [appIcon], or
/// one of Seam's, shown with a Material [icon].
class DetectionAction {
  final String title;
  final IconData icon;
  final Uint8List? appIcon;
  final int? systemIndex;
  final SeamActionKind? kind;

  /// The chat [SeamActionKind.messageInSeam] opens.
  final String? roomId;

  const DetectionAction({
    required this.title,
    required this.icon,
    this.appIcon,
    this.systemIndex,
    this.kind,
    this.roomId,
  });

  @override
  String toString() => 'DetectionAction($title)';
}

/// The menu of [detection]: the platform's actions, then Seam's. A phone
/// number gets "Message in Seam" when [contactRoomId] names the direct chat
/// of a contact with that number.
({List<DetectionAction> system, List<DetectionAction> seam}) actionsFor(
  Detection detection,
  L10n l10n, {
  String? contactRoomId,
}) {
  final system = [
    for (final (i, action) in detection.systemActions.indexed)
      DetectionAction(
        title: action.title,
        icon: _iconOf(detection.type),
        appIcon: action.icon,
        systemIndex: i,
      ),
  ];
  return (
    system: system,
    seam: [
      // Without the platform's actions, Seam offers its own for the type.
      if (system.isEmpty) _primary(detection.type, l10n),
      if (detection.type == DetectionType.phone && contactRoomId != null)
        DetectionAction(
          title: l10n.messageInSeam,
          icon: Icons.forum_outlined,
          kind: SeamActionKind.messageInSeam,
          roomId: contactRoomId,
        ),
      DetectionAction(
        title: l10n.copy,
        icon: Icons.content_copy_outlined,
        kind: SeamActionKind.copy,
      ),
    ],
  );
}

/// The action the assist chip of [detection] offers: the platform's first,
/// else Seam's own for the type.
DetectionAction chipActionFor(Detection detection, L10n l10n) =>
    detection.systemActions.isEmpty
    ? _primary(detection.type, l10n)
    : DetectionAction(
        title: detection.systemActions.first.title,
        icon: _iconOf(detection.type),
        appIcon: detection.systemActions.first.icon,
        systemIndex: 0,
      );

IconData _iconOf(DetectionType type) => switch (type) {
  DetectionType.address => Icons.map_outlined,
  DetectionType.phone => Icons.call_outlined,
  DetectionType.dateTime => Icons.event_outlined,
  DetectionType.flight => Icons.flight_outlined,
};

DetectionAction _primary(DetectionType type, L10n l10n) => switch (type) {
  DetectionType.address => DetectionAction(
    title: l10n.dataDetectorMap,
    icon: _iconOf(type),
    kind: SeamActionKind.map,
  ),
  DetectionType.phone => DetectionAction(
    title: l10n.dataDetectorCall,
    icon: _iconOf(type),
    kind: SeamActionKind.call,
  ),
  DetectionType.dateTime => DetectionAction(
    title: l10n.dataDetectorAddToCalendar,
    icon: _iconOf(type),
    kind: SeamActionKind.addToCalendar,
  ),
  DetectionType.flight => DetectionAction(
    title: l10n.dataDetectorTrackFlight,
    icon: _iconOf(type),
    kind: SeamActionKind.trackFlight,
  ),
};

/// The direct chat of a contact whose phone number is [number], or null.
String? contactRoomForPhone(Client client, String number) {
  final wanted = normalizePhone(
    number,
    defaultRegion: MergeSuggestionService.defaultPhoneRegion(),
  );
  if (wanted == null) return null;
  final service = MergeSuggestionService.forClient(client);
  for (final room in client.rooms) {
    if (room.membership != Membership.join || !room.isDirectChat) continue;
    if (service.phoneOf(room)?.value == wanted) return room.id;
  }
  return null;
}

/// What running an action does to the outside world, kept apart so that
/// tests can watch it.
class DetectionLauncher {
  const DetectionLauncher();

  Future<bool> openUri(Uri uri) =>
      launcher.launchUrl(uri, mode: launcher.LaunchMode.externalApplication);

  Future<void> copy(String text) =>
      Clipboard.setData(ClipboardData(text: text));

  Future<bool> runSystemAction(Detection detection, int index) =>
      DataDetectorPlatform.instance.runSystemAction(detection, index);

  void openRoom(BuildContext context, String roomId) =>
      context.go('/rooms/$roomId');

  /// Writes [ics] to a file and opens it in the default calendar app.
  Future<bool> openCalendarFile(String ics) async {
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}${Platform.pathSeparator}seam-event-'
      '${DateTime.now().millisecondsSinceEpoch}.ics',
    );
    await file.writeAsString(ics);
    return launcher.launchUrl(Uri.file(file.path));
  }
}

/// Runs data detector actions.
abstract class DetectionActions {
  @visibleForTesting
  static DetectionLauncher launcher = const DetectionLauncher();

  /// Runs [action] for [detection], found in a message reading
  /// [messageText].
  static Future<void> run(
    BuildContext context,
    Detection detection,
    DetectionAction action, {
    required String messageText,
  }) async {
    final systemIndex = action.systemIndex;
    if (systemIndex != null) {
      await launcher.runSystemAction(detection, systemIndex);
      return;
    }
    switch (action.kind) {
      case null:
        return;
      case SeamActionKind.copy:
        await launcher.copy(detection.text);
        if (!context.mounted) return;
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(content: Text(L10n.of(context).copiedToClipboard)),
        );
      case SeamActionKind.messageInSeam:
        final roomId = action.roomId;
        if (roomId != null) launcher.openRoom(context, roomId);
      case SeamActionKind.call:
        final number =
            normalizePhone(
              detection.text,
              defaultRegion: MergeSuggestionService.defaultPhoneRegion(),
            ) ??
            detection.text.replaceAll(RegExp(r'[^\d+]'), '');
        await launcher.openUri(Uri(scheme: 'tel', path: number));
      case SeamActionKind.map:
        final opened = await launcher.openUri(mapUri(detection.text));
        if (!opened) await launcher.openUri(webMapUri(detection.text));
      case SeamActionKind.trackFlight:
        await launcher.openUri(
          Uri.https('www.google.com', '/search', {
            'q': 'flight ${detection.text}',
          }),
        );
      case SeamActionKind.addToCalendar:
        final when = detection.when;
        if (when == null) return;
        if (kIsWeb || Platform.isAndroid || Platform.isIOS) {
          await launcher.openUri(webCalendarUri(detection, messageText));
        } else {
          await launcher.openCalendarFile(icsFor(detection, messageText));
        }
    }
  }

  /// The address in the platform's own maps app: the Maps app on Windows,
  /// Apple Maps on macOS and iOS, any `geo:` handler on Android, else
  /// Google Maps on the web.
  static Uri mapUri(String address) {
    final oneLine = address.replaceAll(RegExp(r'\s*\n\s*'), ', ');
    if (kIsWeb) return webMapUri(address);
    if (Platform.isWindows) {
      return Uri.parse('bingmaps:?where=${Uri.encodeQueryComponent(oneLine)}');
    }
    if (Platform.isMacOS || Platform.isIOS) {
      return Uri.parse('maps://?q=${Uri.encodeQueryComponent(oneLine)}');
    }
    if (Platform.isAndroid) {
      return Uri.parse('geo:0,0?q=${Uri.encodeQueryComponent(oneLine)}');
    }
    return webMapUri(address);
  }

  static Uri webMapUri(String address) => Uri.https(
    'www.google.com',
    '/maps/search/',
    {'api': '1', 'query': address.replaceAll(RegExp(r'\s*\n\s*'), ', ')},
  );

  /// An event an hour long at [detection]'s time, or all day on its date,
  /// titled and described with the message.
  static String icsFor(Detection detection, String messageText) {
    final when = detection.when!;
    String utc(DateTime t) {
      final u = t.toUtc();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${u.year}${two(u.month)}${two(u.day)}T'
          '${two(u.hour)}${two(u.minute)}${two(u.second)}Z';
    }

    String date(DateTime t) =>
        '${t.year}${t.month.toString().padLeft(2, '0')}'
        '${t.day.toString().padLeft(2, '0')}';
    String escape(String s) => s
        .replaceAll(r'\', r'\\')
        .replaceAll(';', r'\;')
        .replaceAll(',', r'\,')
        .replaceAll(RegExp(r'\r?\n'), r'\n');
    final start = detection.hasTime
        ? 'DTSTART:${utc(when)}'
        : 'DTSTART;VALUE=DATE:${date(when)}';
    final end = detection.hasTime
        ? 'DTEND:${utc(when.add(const Duration(hours: 1)))}'
        : 'DTEND;VALUE=DATE:${date(when.add(const Duration(days: 1)))}';
    return [
      'BEGIN:VCALENDAR',
      'VERSION:2.0',
      'PRODID:-//Seam//Data detectors//EN',
      'BEGIN:VEVENT',
      'UID:${when.millisecondsSinceEpoch}-${messageText.hashCode}@seam',
      'DTSTAMP:${utc(DateTime.now())}',
      start,
      end,
      'SUMMARY:${escape(_title(messageText))}',
      'DESCRIPTION:${escape(messageText)}',
      'END:VEVENT',
      'END:VCALENDAR',
      '',
    ].join('\r\n');
  }

  /// A new Google Calendar event with [detection]'s time, for a phone whose
  /// system offered no calendar action.
  static Uri webCalendarUri(Detection detection, String messageText) {
    final when = detection.when!;
    String stamp(DateTime t) {
      final u = t.toUtc();
      String two(int n) => n.toString().padLeft(2, '0');
      return '${u.year}${two(u.month)}${two(u.day)}T'
          '${two(u.hour)}${two(u.minute)}00Z';
    }

    return Uri.https('calendar.google.com', '/calendar/render', {
      'action': 'TEMPLATE',
      'text': _title(messageText),
      'details': messageText,
      'dates':
          '${stamp(when)}/${stamp(when.add(Duration(hours: detection.hasTime ? 1 : 24)))}',
    });
  }

  static String _title(String messageText) {
    final line = messageText.trim().split('\n').first;
    return line.length <= 60 ? line : '${line.substring(0, 57)}...';
  }
}
