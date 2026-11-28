// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:typed_data';

/// What a data detector found in a message: the kinds of text Messages on
/// iPhone and Android's Smart Linkify underline and offer actions for.
/// Links and email addresses are not among them; the message renderer
/// links those itself.
enum DetectionType {
  address,
  phone,

  /// A date, with or without a time of day.
  dateTime,

  /// A flight number in IATA form, such as `DL 1234`.
  flight;

  /// The name used on the platform channel.
  String get wireName => switch (this) {
    address => 'address',
    phone => 'phone',
    dateTime => 'datetime',
    flight => 'flight',
  };

  static DetectionType? fromWire(Object? name) => switch (name) {
    'address' => address,
    'phone' => phone,
    'date' || 'datetime' => dateTime,
    'flight' => flight,
    _ => null,
  };
}

/// An action the platform offers for a detection, such as Android's
/// TextClassifier `RemoteAction`s: its title, a description for screen
/// readers, and the icon of the app that handles it (PNG bytes), or no icon
/// when the platform gives none worth showing.
class SystemAction {
  final String title;
  final String? description;
  final Uint8List? icon;

  const SystemAction({required this.title, this.description, this.icon});
}

/// One detection in a message's plain text, which runs from [start] to
/// [end] (UTF-16 offsets) and reads [text].
class Detection {
  final DetectionType type;
  final int start;
  final int end;
  final String text;

  /// The moment a [DetectionType.dateTime] detection names, as read by
  /// Seam's own detector; null where the platform keeps it to itself.
  final DateTime? when;

  /// Whether [when] names a time of day as well as a date.
  final bool hasTime;

  /// The platform's actions, in the platform's order. Empty where Seam
  /// offers its own actions instead (see `seamActionsFor`).
  final List<SystemAction> systemActions;

  /// The platform's handle on this detection, passed back to run one of
  /// [systemActions]. Null when there are none.
  final String? token;

  const Detection({
    required this.type,
    required this.start,
    required this.end,
    required this.text,
    this.when,
    this.hasTime = false,
    this.systemActions = const [],
    this.token,
  });

  /// The detected text split at line breaks, each part trimmed: an address
  /// written over three lines is rendered as three runs of text.
  List<String> get pieces => [
    for (final line in text.split('\n'))
      if (line.trim().isNotEmpty) line.trim(),
  ];

  @override
  String toString() => 'Detection($type, $start-$end, "$text")';
}
