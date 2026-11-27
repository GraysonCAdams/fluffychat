// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:ffi';
import 'dart:io';

import 'package:ffi/ffi.dart';
import 'package:fluffychat/utils/android_spell_check.dart';
import 'package:fluffychat/utils/composer_native_menu.dart';
import 'package:fluffychat/utils/platform_infos.dart';
import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';

/// Spell checking for the message input. Android and iOS use the platform's
/// own service; Flutter has none on Windows, so there it asks the Windows
/// Spell Checking API, which follows the languages set up in Windows. Its
/// suggestions appear in the native right-click menu (composer_native_menu.dart).
/// On both Android and Windows only misspelled words are underlined, not
/// grammar suggestions or repeated words.
///
/// Android has no native correction popup for a Flutter text field (the
/// embedding only reads the spell checker's results), so the keyboard's
/// suggestion strip offers the corrections there: tapping a misspelled word
/// places the caret in it without Flutter's own suggestions toolbar.
SpellCheckConfiguration? messageSpellCheckConfiguration() {
  if (PlatformInfos.isAndroid) return androidSpellCheckConfiguration();
  if (PlatformInfos.isIOS) {
    return const SpellCheckConfiguration();
  }
  if (PlatformInfos.isWindows) {
    return SpellCheckConfiguration(
      spellCheckService: WindowsSpellCheckService.instance,
      misspelledTextStyle: TextField.materialMisspelledTextStyle,
    );
  }
  return null;
}

/// Android's configuration: the system spell checker through
/// [AndroidSpellCheckService], which underlines typos only. [service] stands
/// in for it in tests.
@visibleForTesting
SpellCheckConfiguration androidSpellCheckConfiguration({
  SpellCheckService? service,
}) => SpellCheckConfiguration(
  spellCheckService: service ?? AndroidSpellCheckService.instance,
  // Flutter's toolbar opens with nothing in it; the next tap or long press
  // closes it as usual.
  spellCheckSuggestionsToolbarBuilder: (_, _) => const SizedBox.shrink(),
);

/// Where the message input's "Add to dictionary" and "Ignore" go.
SpellCheckDictionary? messageSpellCheckDictionary() =>
    PlatformInfos.isWindows ? WindowsSpellCheckService.instance : null;

class WindowsSpellCheckService
    implements SpellCheckService, SpellCheckDictionary {
  WindowsSpellCheckService._();

  static final instance = WindowsSpellCheckService._();

  static final _ole32 = DynamicLibrary.open('ole32.dll');
  static final _coInitializeEx = _ole32
      .lookupFunction<
        Int32 Function(Pointer, Uint32),
        int Function(Pointer, int)
      >('CoInitializeEx');
  static final _coCreateInstance = _ole32
      .lookupFunction<
        Int32 Function(
          Pointer<_Guid>,
          Pointer,
          Uint32,
          Pointer<_Guid>,
          Pointer<Pointer>,
        ),
        int Function(
          Pointer<_Guid>,
          Pointer,
          int,
          Pointer<_Guid>,
          Pointer<Pointer>,
        )
      >('CoCreateInstance');
  static final _coTaskMemFree = _ole32
      .lookupFunction<Void Function(Pointer), void Function(Pointer)>(
        'CoTaskMemFree',
      );

  // Vtable slots from spellcheck.h (IUnknown takes 0 to 2).
  static const _release = 2;
  static const _factoryIsSupported = 4;
  static const _factoryCreateSpellChecker = 5;
  static const _checkerCheck = 4;
  static const _checkerSuggest = 5;
  static const _checkerAdd = 6;
  static const _checkerIgnore = 7;
  static const _enumNext = 3;
  static const _errorStartIndex = 3;
  static const _errorLength = 4;
  static const _errorCorrectiveAction = 5;
  static const _errorReplacement = 6;

  // CORRECTIVE_ACTION values.
  static const _getSuggestions = 1;
  static const _replace = 2;

  static const _maxSuggestions = 5;

  Pointer<Pointer<IntPtr>>? _factory;
  final _checkers = <String, Pointer<Pointer<IntPtr>>?>{};

  /// The checker of the latest check, whose language the input is in.
  Pointer<Pointer<IntPtr>>? _lastChecker;

  /// Adds [word] to the Windows user dictionary of the input's language, so
  /// every app stops flagging it.
  @override
  void add(String word) => _callWithWord(_checkerAdd, word);

  /// Stops flagging [word] until the app quits.
  @override
  void ignore(String word) => _callWithWord(_checkerIgnore, word);

  void _callWithWord(int slot, String word) {
    final checker = _lastChecker;
    if (checker == null) return;
    final nativeWord = word.toNativeUtf16();
    try {
      final hr = _call1(checker, slot, nativeWord);
      if (hr < 0) Logs().w('Windows spell checker refused a word: $hr');
    } finally {
      calloc.free(nativeWord);
    }
  }

  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async {
    if (text.trim().isEmpty) return const [];
    final checker = _checkerFor(locale);
    if (checker == null) return null;
    _lastChecker = checker;

    final spans = <SuggestionSpan>[];
    final nativeText = text.toNativeUtf16();
    final errors = calloc<Pointer>();
    try {
      if (_call2(checker, _checkerCheck, nativeText, errors) < 0) return null;
      final enumerator = errors.value.cast<Pointer<IntPtr>>();
      final error = calloc<Pointer>();
      final number = calloc<Uint32>();
      try {
        while (_call1(enumerator, _enumNext, error) == 0) {
          final spellingError = error.value.cast<Pointer<IntPtr>>();
          try {
            _call1(spellingError, _errorStartIndex, number);
            final start = number.value;
            _call1(spellingError, _errorLength, number);
            final end = start + number.value;
            _call1(spellingError, _errorCorrectiveAction, number);
            // Only misspellings: a repeated word ("the the") comes back
            // as CORRECTIVE_ACTION_DELETE and is left alone.
            final suggestions = switch (number.value) {
              _getSuggestions => _suggest(checker, text.substring(start, end)),
              _replace => [?_replacement(spellingError)],
              _ => null,
            };
            if (suggestions != null) {
              spans.add(
                SuggestionSpan(TextRange(start: start, end: end), suggestions),
              );
            }
          } finally {
            _call0(spellingError, _release);
          }
        }
      } finally {
        _call0(enumerator, _release);
        calloc.free(error);
        calloc.free(number);
      }
    } finally {
      calloc.free(nativeText);
      calloc.free(errors);
    }
    return spans;
  }

  Pointer<Pointer<IntPtr>>? _checkerFor(Locale locale) {
    final factory = _factory ??= _createFactory();
    if (factory == null) return null;
    // The app locale often lacks a region ("en"), which the API may not
    // support on its own, so fall back to the Windows display language.
    final tags = {
      locale.toLanguageTag(),
      Platform.localeName.replaceAll('_', '-').split('.').first,
    };
    for (final tag in tags) {
      if (_checkers.containsKey(tag)) {
        final cached = _checkers[tag];
        if (cached != null) return cached;
        continue;
      }
      _checkers[tag] = _createChecker(factory, tag);
      if (_checkers[tag] != null) return _checkers[tag];
    }
    return null;
  }

  Pointer<Pointer<IntPtr>>? _createFactory() {
    // Already initialised on the platform thread; harmless if so.
    _coInitializeEx(nullptr, 2 /* COINIT_APARTMENTTHREADED */);
    final clsid = _Guid.allocate('7AB36653-1796-484B-BDFA-E74F1DB7C1DC');
    final iid = _Guid.allocate('8E018A9D-2415-4677-BF08-794EA61F94BB');
    final out = calloc<Pointer>();
    try {
      final hr = _coCreateInstance(clsid, nullptr, 1 /* INPROC */, iid, out);
      if (hr < 0) {
        Logs().w('Windows spell checking is unavailable: $hr');
        return null;
      }
      return out.value.cast<Pointer<IntPtr>>();
    } finally {
      calloc.free(clsid);
      calloc.free(iid);
      calloc.free(out);
    }
  }

  Pointer<Pointer<IntPtr>>? _createChecker(
    Pointer<Pointer<IntPtr>> factory,
    String tag,
  ) {
    final nativeTag = tag.toNativeUtf16();
    final supported = calloc<Int32>();
    final out = calloc<Pointer>();
    try {
      _call2(factory, _factoryIsSupported, nativeTag, supported);
      if (supported.value == 0) return null;
      if (_call2(factory, _factoryCreateSpellChecker, nativeTag, out) < 0) {
        return null;
      }
      return out.value.cast<Pointer<IntPtr>>();
    } finally {
      calloc.free(nativeTag);
      calloc.free(supported);
      calloc.free(out);
    }
  }

  List<String> _suggest(Pointer<Pointer<IntPtr>> checker, String word) {
    final nativeWord = word.toNativeUtf16();
    final out = calloc<Pointer>();
    final suggestions = <String>[];
    try {
      if (_call2(checker, _checkerSuggest, nativeWord, out) != 0) {
        return suggestions;
      }
      final strings = out.value.cast<Pointer<IntPtr>>();
      final item = calloc<Pointer<Utf16>>();
      final fetched = calloc<Uint32>();
      try {
        final next =
            Pointer<
                  NativeFunction<
                    Int32 Function(
                      Pointer,
                      Uint32,
                      Pointer<Pointer<Utf16>>,
                      Pointer<Uint32>,
                    )
                  >
                >.fromAddress(strings.value[_enumNext])
                .asFunction<
                  int Function(
                    Pointer,
                    int,
                    Pointer<Pointer<Utf16>>,
                    Pointer<Uint32>,
                  )
                >();
        while (suggestions.length < _maxSuggestions &&
            next(strings, 1, item, fetched) == 0 &&
            fetched.value == 1) {
          suggestions.add(item.value.toDartString());
          _coTaskMemFree(item.value);
        }
      } finally {
        _call0(strings, _release);
        calloc.free(item);
        calloc.free(fetched);
      }
    } finally {
      calloc.free(nativeWord);
      calloc.free(out);
    }
    return suggestions;
  }

  String? _replacement(Pointer<Pointer<IntPtr>> spellingError) {
    final out = calloc<Pointer<Utf16>>();
    try {
      if (_call1(spellingError, _errorReplacement, out) != 0) return null;
      final replacement = out.value.toDartString();
      _coTaskMemFree(out.value);
      return replacement;
    } finally {
      calloc.free(out);
    }
  }

  static int _call0(Pointer<Pointer<IntPtr>> object, int slot) =>
      Pointer<NativeFunction<Int32 Function(Pointer)>>.fromAddress(
        object.value[slot],
      ).asFunction<int Function(Pointer)>()(object);

  static int _call1(Pointer<Pointer<IntPtr>> object, int slot, Pointer a) =>
      Pointer<NativeFunction<Int32 Function(Pointer, Pointer)>>.fromAddress(
        object.value[slot],
      ).asFunction<int Function(Pointer, Pointer)>()(object, a);

  static int _call2(
    Pointer<Pointer<IntPtr>> object,
    int slot,
    Pointer a,
    Pointer b,
  ) =>
      Pointer<
            NativeFunction<Int32 Function(Pointer, Pointer, Pointer)>
          >.fromAddress(object.value[slot])
          .asFunction<int Function(Pointer, Pointer, Pointer)>()(object, a, b);
}

final class _Guid extends Struct {
  @Uint32()
  external int data1;
  @Uint16()
  external int data2;
  @Uint16()
  external int data3;
  @Array(8)
  external Array<Uint8> data4;

  static Pointer<_Guid> allocate(String text) {
    final hex = text.replaceAll('-', '');
    final guid = calloc<_Guid>();
    guid.ref
      ..data1 = int.parse(hex.substring(0, 8), radix: 16)
      ..data2 = int.parse(hex.substring(8, 12), radix: 16)
      ..data3 = int.parse(hex.substring(12, 16), radix: 16);
    for (var i = 0; i < 8; i++) {
      guid.ref.data4[i] = int.parse(
        hex.substring(16 + i * 2, 18 + i * 2),
        radix: 16,
      );
    }
    return guid;
  }
}
