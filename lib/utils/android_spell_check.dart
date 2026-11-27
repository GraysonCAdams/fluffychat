// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ui';

import 'package:flutter/services.dart';

/// Android's system spell checker for the message input, underlining typos
/// only.
///
/// Flutter's [DefaultSpellCheckService] underlines every span the checker
/// reports, and on Android 12 and later that includes grammar suggestions,
/// which then look like misspelled words. The app's own channel
/// (android/.../SpellCheckBridge.kt) passes on each span's SuggestionsInfo
/// attributes, and only spans marked as a likely typo are kept.
class AndroidSpellCheckService implements SpellCheckService {
  AndroidSpellCheckService({MethodChannel? channel})
    : channel = channel ?? const MethodChannel(channelName);

  static const channelName = 'chat.fluffy.fluffychat/spell_check';

  /// The one the message input uses.
  static final instance = AndroidSpellCheckService();

  // SuggestionsInfo.RESULT_ATTR_* flags.
  static const inTheDictionary = 0x1;
  static const looksLikeTypo = 0x2;
  static const looksLikeGrammarError = 0x8;

  final MethodChannel channel;

  /// Whether a span with these SuggestionsInfo [attributes] is a typo.
  static bool isTypo(int attributes) =>
      attributes & looksLikeTypo != 0 && attributes & inTheDictionary == 0;

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    final List<Object?> raw;
    try {
      raw =
          await channel.invokeMethod<List<Object?>>('check', [
            locale.toLanguageTag(),
            text,
          ]) ??
          const [];
    } on PlatformException {
      // Another check is still running; Flutter keeps the old results.
      return null;
    }

    return [
      for (final span in raw.cast<Map<Object?, Object?>>())
        if (isTypo(span['attributes'] as int))
          SuggestionSpan(
            TextRange(
              start: span['startIndex'] as int,
              end: span['endIndex'] as int,
            ),
            (span['suggestions'] as List<Object?>).cast<String>(),
          ),
    ];
  }
}
