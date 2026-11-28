// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'package:fluffychat/utils/data_detectors/data_detector_platform.dart';
import 'package:fluffychat/utils/data_detectors/detection.dart';
import 'package:fluffychat/utils/merged_contacts/phone_number.dart';

/// Seam's own data detector, for platforms without a system one (Windows,
/// Linux, macOS, web). It looks for US street addresses, phone numbers,
/// dates and times, and flight numbers, and is deliberately strict: a
/// missed detection leaves plain text, while a false one puts a wrong
/// action under a message. It offers no system actions.
class DartDataDetector implements DataDetectorPlatform {
  @override
  Future<List<Detection>> detect(
    String text, {
    required DateTime referenceTime,
  }) async => detectSync(text, referenceTime: referenceTime);

  @override
  Future<bool> runSystemAction(Detection detection, int index) async => false;

  /// [detect], without waiting.
  static List<Detection> detectSync(
    String text, {
    required DateTime referenceTime,
  }) {
    if (text.length > maxLength) return const [];
    // Addresses first: their house numbers and ZIP codes must not be read
    // as phone numbers or times.
    final found = <Detection>[
      ..._addresses(text),
      ..._flights(text),
      ..._phones(text),
      ..._dates(text, referenceTime),
    ];
    final kept = <Detection>[];
    for (final detection in found) {
      if (kept.any((k) => k.start < detection.end && detection.start < k.end)) {
        continue;
      }
      if (_insideLinkOrEmail(text, detection.start, detection.end)) continue;
      kept.add(detection);
    }
    kept.sort((a, b) => a.start.compareTo(b.start));
    return kept;
  }

  /// Longer messages are not scanned at all.
  static const maxLength = 4000;

  /// Whether the whitespace-delimited word around [start] to [end] is a
  /// link or an email address, which the renderer links on its own.
  static bool _insideLinkOrEmail(String text, int start, int end) {
    var from = start;
    while (from > 0 && !_space.hasMatch(text[from - 1])) {
      from--;
    }
    var to = end;
    while (to < text.length && !_space.hasMatch(text[to])) {
      to++;
    }
    final word = text.substring(from, to);
    return word.contains('://') ||
        word.contains('www.') ||
        word.contains('@') ||
        (word.contains('/') && !RegExp(r'^\d').hasMatch(word));
  }

  static final _space = RegExp(r'\s');

  // -------------------------------------------------------------------------
  // Addresses: a house number, a street with a suffix, an optional unit, a
  // city and a state, an optional ZIP code and an optional country. Commas
  // and line breaks may separate the parts.

  static const _streetSuffixes = [
    'Street', 'St', 'Road', 'Rd', 'Avenue', 'Ave', 'Boulevard', 'Blvd', //
    'Drive', 'Dr', 'Lane', 'Ln', 'Court', 'Ct', 'Way', 'Parkway', 'Pkwy',
    'Place', 'Pl', 'Circle', 'Cir', 'Terrace', 'Ter', 'Highway', 'Hwy',
    'Trail', 'Trl', 'Square', 'Sq', 'Loop', 'Path', 'Pike', 'Row',
    'Crossing', 'Xing', 'Point', 'Pt', 'Run', 'Walk', 'Commons', 'Plaza',
    'Plz', 'Alley', 'Aly', 'Bend', 'Cove', 'Cv', 'Expressway', 'Expy',
    'Freeway', 'Fwy', 'Ridge', 'Rdg', 'Glen', 'Hollow', 'Landing',
  ];

  static const _states = [
    'AL', 'AK', 'AZ', 'AR', 'CA', 'CO', 'CT', 'DE', 'DC', 'FL', 'GA', 'HI', //
    'ID', 'IL', 'IN', 'IA', 'KS', 'KY', 'LA', 'ME', 'MD', 'MA', 'MI', 'MN',
    'MS', 'MO', 'MT', 'NE', 'NV', 'NH', 'NJ', 'NM', 'NY', 'NC', 'ND', 'OH',
    'OK', 'OR', 'PA', 'RI', 'SC', 'SD', 'TN', 'TX', 'UT', 'VT', 'VA', 'WA',
    'WV', 'WI', 'WY', 'PR',
    'Alabama', 'Alaska', 'Arizona', 'Arkansas', 'California', 'Colorado',
    'Connecticut', 'Delaware', 'Florida', 'Georgia', 'Hawaii', 'Idaho',
    'Illinois', 'Indiana', 'Iowa', 'Kansas', 'Kentucky', 'Louisiana', 'Maine',
    'Maryland', 'Massachusetts', 'Michigan', 'Minnesota', 'Mississippi',
    'Missouri', 'Montana', 'Nebraska', 'Nevada', 'New Hampshire',
    'New Jersey', 'New Mexico', 'New York', 'North Carolina', 'North Dakota',
    'Ohio', 'Oklahoma', 'Oregon', 'Pennsylvania', 'Rhode Island',
    'South Carolina', 'South Dakota', 'Tennessee', 'Texas', 'Utah', 'Vermont',
    'Virginia', 'Washington', 'West Virginia', 'Wisconsin', 'Wyoming',
  ];

  static final RegExp _address = () {
    const word = r"[A-Z0-9][A-Za-z0-9'.-]*";
    const direction = r'(?:[NSEW]|NE|NW|SE|SW|North|South|East|West)\.?';
    final suffix = _streetSuffixes.join('|');
    // Longest names first, so "West Virginia" is not read as "Virginia".
    final states = ([
      ..._states,
    ]..sort((a, b) => b.length - a.length)).join('|');
    // Spaces only within a line; a line break may separate the parts.
    const gap = r'[ \t]*(?:,[ \t]*|\r?\n[ \t]*|[ \t])';
    return RegExp(
      [
        r'(?<![\w-])\d{1,6}[A-Za-z]?',
        '(?:[ \t]+$direction)?',
        '(?:[ \t]+$word){1,5}?',
        '[ \t]+(?:$suffix)\\.?',
        '(?:[ \t]+$direction)?',
        // A unit: "Apt D", "Suite 200", "#4B".
        r'(?:[ \t,]+(?:(?:Apt|Apartment|Suite|Ste|Unit|Bldg|Building|Fl|Floor|Rm|Room)\.?[ \t]*|#[ \t]*)[A-Za-z0-9-]{1,6})?',
        // The city, then the state.
        gap,
        r"(?:[A-Z][A-Za-z.'-]*)(?:[ \t]+[A-Z][A-Za-z.'-]*){0,3}",
        gap,
        '(?:$states)',
        // The ZIP code and the country.
        r'(?:[ \t,]*\s?[ \t]*\d{5}(?:-\d{4})?)?',
        '(?:$gap(?:United States(?: of America)?|USA|U\\.S\\.A\\.|US))?',
        r'(?![\w-])',
      ].join(),
    );
  }();

  static Iterable<Detection> _addresses(String text) sync* {
    for (final match in _address.allMatches(text)) {
      yield Detection(
        type: DetectionType.address,
        start: match.start,
        end: match.end,
        text: match[0]!,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Phone numbers: North American numbers in their usual forms, and
  // international ones written with a leading +. Each must survive
  // [normalizePhone].

  static final _nanp = RegExp(
    r'(?<![\w+(])(?:\+?1[ .-]?)?(?:\(\s?[2-9]\d{2}\s?\)|[2-9]\d{2})[ .-]?[2-9]\d{2}[ .-]?\d{4}(?![\w])',
  );
  static final _international = RegExp(
    r'(?<![\w+])\+(?!1[ .(-]?\d)[1-9]\d{0,2}(?:[ .-]?\(?\d{1,4}\)?){2,5}(?![\w])',
  );

  static Iterable<Detection> _phones(String text) sync* {
    for (final pattern in [_nanp, _international]) {
      for (final match in pattern.allMatches(text)) {
        final number = match[0]!;
        final digits = number.replaceAll(RegExp(r'\D'), '');
        // Ten digits run together with no punctuation could as well be an
        // order or tracking number.
        if (digits.length == number.length) continue;
        if (normalizePhone(number) == null) continue;
        yield Detection(
          type: DetectionType.phone,
          start: match.start,
          end: match.end,
          text: number,
        );
      }
    }
  }

  // -------------------------------------------------------------------------
  // Flight numbers: an airline's IATA code and two to four digits. Only the
  // codes of large airlines count, and none that is also a state or a
  // common word, so "AB 1234" in a part number and "CA 90" do not.

  static const _airlines = [
    'AA', 'AS', 'B6', 'DL', 'F9', 'G4', 'HA', 'NK', 'UA', 'WN', 'SY', 'AC', //
    'WS', 'BA', 'VS', 'AF', 'KL', 'LH', 'LX', 'IB', 'AY', 'TK', 'EK', 'EY',
    'QR', 'QF', 'NZ', 'SQ', 'CX', 'JL', 'NH', 'FR', 'U2',
  ];

  static final _flight = RegExp(
    [r'(?<![\w-])(?:', _airlines.join('|'), r') ?[1-9]\d{1,3}(?![\w-])'].join(),
  );

  static Iterable<Detection> _flights(String text) sync* {
    for (final match in _flight.allMatches(text)) {
      yield Detection(
        type: DetectionType.flight,
        start: match.start,
        end: match.end,
        text: match[0]!,
      );
    }
  }

  // -------------------------------------------------------------------------
  // Dates and times. A day ("today", "tomorrow", "Friday", "Nov 28",
  // "11/28/2026") optionally followed by a time ("at 7pm", "7:30 pm"), or a
  // time with am or pm on its own. A bare number never counts as a time.

  static const _months = {
    'jan': 1, 'january': 1, 'feb': 2, 'february': 2, 'mar': 3, 'march': 3, //
    'apr': 4, 'april': 4, 'may': 5, 'jun': 6, 'june': 6, 'jul': 7,
    'july': 7, 'aug': 8, 'august': 8, 'sep': 9, 'sept': 9, 'september': 9,
    'oct': 10, 'october': 10, 'nov': 11, 'november': 11, 'dec': 12,
    'december': 12,
  };

  static const _weekdays = {
    'mon': 1, 'monday': 1, 'tue': 2, 'tues': 2, 'tuesday': 2, 'wed': 3, //
    'wednesday': 3, 'thu': 4, 'thur': 4, 'thurs': 4, 'thursday': 4,
    'fri': 5, 'friday': 5, 'sat': 6, 'saturday': 6, 'sun': 7, 'sunday': 7,
  };

  static const _time =
      r'(?:(?<h>1[0-2]|0?[1-9])(?::(?<m>[0-5]\d))?\s?(?<ap>[ap]\.?m\.?)(?![a-z])'
      r'|(?<h24>[01]?\d|2[0-3]):(?<m24>[0-5]\d)(?!\d)'
      r'|(?<noon>noon|midnight))';

  static final RegExp _date = () {
    final months = (_months.keys.toList()..sort((a, b) => b.length - a.length))
        .join('|');
    final weekdays =
        (_weekdays.keys.toList()..sort((a, b) => b.length - a.length)).join(
          '|',
        );
    final day = [
      r'(?:(?<rel>today|tonight|tomorrow)',
      r'|(?:(?<next>next|this)\s+)?(?<wd>',
      weekdays,
      r')\.?',
      r'|(?<mon>',
      months,
      r')\.?\s+(?<d>[12]\d|3[01]|0?[1-9])(?:st|nd|rd|th)?(?:,?\s+(?<y>20\d\d))?',
      r'|(?<nm>1[0-2]|0?[1-9])/(?<nd>[12]\d|3[01]|0?[1-9])/(?<ny>20\d\d|\d\d))',
    ].join();
    // The time after a day has its groups named with a leading t, as names
    // must not repeat.
    final timeAfterDay = _time.replaceAll('?<', '?<t');
    return RegExp(
      [
        r'(?<![\w/])(?:',
        day,
        r'(?:(?:,?\s+at|,?\s+@|,)?\s+',
        timeAfterDay,
        r')?|(?:at\s+)?',
        _time,
        r')(?![\w/])',
      ].join(),
      caseSensitive: false,
    );
  }();

  static Iterable<Detection> _dates(String text, DateTime reference) sync* {
    for (final match in _date.allMatches(text)) {
      final read = _read(match, reference);
      if (read == null) continue;
      var start = match.start;
      final whole = match[0]!;
      // A lone time keeps its "at" out of the underline.
      final at = RegExp(r'^at\s+', caseSensitive: false).firstMatch(whole);
      if (at != null) start += at.end;
      yield Detection(
        type: DetectionType.dateTime,
        start: start,
        end: match.end,
        text: text.substring(start, match.end),
        when: read.$1,
        hasTime: read.$2,
      );
    }
  }

  /// The moment [match] names and whether it has a time of day.
  static (DateTime, bool)? _read(RegExpMatch match, DateTime reference) {
    String? group(String name) {
      try {
        return match.namedGroup(name);
      } on ArgumentError {
        return null;
      }
    }

    DateTime? day;
    final rel = group('rel')?.toLowerCase();
    final wd = group('wd')?.toLowerCase();
    final mon = group('mon')?.toLowerCase();
    final nm = group('nm');
    final today = DateTime(reference.year, reference.month, reference.day);
    if (rel != null) {
      day = rel == 'tomorrow' ? today.add(const Duration(days: 1)) : today;
    } else if (wd != null) {
      final target = _weekdays[wd]!;
      var ahead = (target - today.weekday) % 7;
      if (group('next')?.toLowerCase() == 'next' && ahead == 0) ahead = 7;
      day = today.add(Duration(days: ahead));
    } else if (mon != null) {
      final month = _months[mon]!;
      final d = int.parse(group('d')!);
      final y = group('y');
      var year = y == null ? today.year : int.parse(y);
      var candidate = DateTime(year, month, d);
      if (candidate.month != month) return null;
      // A date without a year that has passed means next year's.
      if (y == null && candidate.isBefore(today)) {
        year++;
        candidate = DateTime(year, month, d);
      }
      day = candidate;
    } else if (nm != null) {
      final month = int.parse(nm);
      final d = int.parse(group('nd')!);
      var year = int.parse(group('ny')!);
      if (year < 100) year += 2000;
      day = DateTime(year, month, d);
      if (day.month != month) return null;
    }

    final time =
        _readTime(
          group('th'),
          group('tm'),
          group('tap'),
          group('th24'),
          group('tm24'),
          group('tnoon'),
        ) ??
        _readTime(
          group('h'),
          group('m'),
          group('ap'),
          group('h24'),
          group('m24'),
          group('noon'),
        );
    if (day == null && time == null) return null;
    if (day == null) {
      // A time alone needs am or pm, or an hour past 12: "6:45" alone could
      // be a score or a duration.
      if (time!.$3) return null;
      // A time alone is today's, or tomorrow's once it has passed.
      var at = DateTime(today.year, today.month, today.day, time.$1, time.$2);
      if (at.isBefore(reference)) at = at.add(const Duration(days: 1));
      return (at, true);
    }
    if (time == null) {
      return rel == 'tonight'
          ? (DateTime(day.year, day.month, day.day, 20), false)
          : (day, false);
    }
    var hour = time.$1;
    // "Tonight at 8" and "tomorrow at 6:45" without am or pm: an hour from
    // 1 to 7 is the evening.
    if (time.$3 && hour >= 1 && hour <= 7) hour += 12;
    return (DateTime(day.year, day.month, day.day, hour, time.$2), true);
  }

  /// Hour, minute, and whether the hour was given without am or pm and
  /// under 13, so could be either.
  static (int, int, bool)? _readTime(
    String? h,
    String? m,
    String? ap,
    String? h24,
    String? m24,
    String? noon,
  ) {
    if (noon != null) {
      return (noon.toLowerCase() == 'noon' ? 12 : 0, 0, false);
    }
    if (h != null && ap != null) {
      var hour = int.parse(h) % 12;
      if (ap.toLowerCase().startsWith('p')) hour += 12;
      return (hour, int.parse(m ?? '0'), false);
    }
    if (h24 != null && m24 != null) {
      final hour = int.parse(h24);
      return (hour, int.parse(m24), hour <= 12);
    }
    return null;
  }
}
