// SPDX-FileCopyrightText: 2019-Present Christian Kußowski
// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

import 'dart:async';

import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/utils/composer_native_menu.dart';
import 'package:fluffychat/utils/native_context_menu.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

const _text = 'Ths is a smple tset';

/// Flags "Ths", "smple" and "tset", like the Windows checker does.
class _FakeSpellCheckService implements SpellCheckService {
  @override
  Future<List<SuggestionSpan>?> fetchSpellCheckSuggestions(
    Locale locale,
    String text,
  ) async => [
    for (final (word, suggestions) in [
      ('Ths', ['This', 'The']),
      ('smple', ['simple', 'sample']),
      ('tset', <String>[]),
    ])
      if (text.contains(word))
        SuggestionSpan(
          TextRange(
            start: text.indexOf(word),
            end: text.indexOf(word) + word.length,
          ),
          suggestions,
        ),
  ];
}

class _FakeDictionary implements SpellCheckDictionary {
  final added = <String>[];
  final ignored = <String>[];

  @override
  void add(String word) => added.add(word);

  @override
  void ignore(String word) => ignored.add(word);
}

void main() {
  late TextEditingController controller;
  late FocusNode focusNode;
  late _FakeDictionary dictionary;
  late BuildContext appContext;

  setUp(() {
    controller = TextEditingController();
    focusNode = FocusNode();
    dictionary = _FakeDictionary();
  });

  Future<EditableTextState> pumpField(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Builder(
            builder: (context) {
              appContext = context;
              return NativeComposerMenuShortcuts(
                focusNode: focusNode,
                dictionary: dictionary,
                extraItems: () => [
                  ContextMenuButtonItem(label: 'Bold & co', onPressed: () {}),
                ],
                child: TextField(
                  controller: controller,
                  focusNode: focusNode,
                  spellCheckConfiguration: SpellCheckConfiguration(
                    spellCheckService: _FakeSpellCheckService(),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
    // L10n loads its messages deferred, so the first frame is empty.
    await tester.pumpAndSettle();
    // Flutter checks the spelling of what the user types.
    await tester.enterText(find.byType(TextField), _text);
    await tester.pumpAndSettle();
    final state = tester.state<EditableTextState>(find.byType(EditableText));
    expect(state.spellCheckResults?.suggestionSpans, hasLength(3));
    return state;
  }

  List<NativeMenuEntry> entriesAt(EditableTextState state, int index) =>
      composerMenuEntries(
        appContext,
        editableTextState: state,
        span: state.findSuggestionSpanAtCursorIndex(index),
        dictionary: dictionary,
      );

  String describe(NativeMenuEntry entry) => switch (entry) {
    NativeMenuSeparator() => '---',
    NativeMenuItem(:final label, :final onSelected) =>
      onSelected == null ? '($label)' : label,
  };

  NativeMenuItem item(List<NativeMenuEntry> entries, String label) => entries
      .whereType<NativeMenuItem>()
      .singleWhere((item) => item.label == label);

  group('composerMenuEntries', () {
    testWidgets('puts the suggestions for the word first, as Notepad does', (
      tester,
    ) async {
      final state = await pumpField(tester);
      controller.selection = const TextSelection.collapsed(offset: 11);
      await tester.pump();

      expect(entriesAt(state, 11).map(describe), [
        'simple',
        'sample',
        '---',
        'Add to dictionary',
        'Ignore',
        '---',
        '(Cut)',
        '(Copy)',
        // The test clipboard never reports text.
        '(Paste)',
        'Select all',
      ]);
    });

    testWidgets('greys out an empty suggestion list', (tester) async {
      final state = await pumpField(tester);
      expect(entriesAt(state, 16).take(2).map(describe), [
        '((No spelling suggestions))',
        '---',
      ]);
    });

    testWidgets('has only the editing items away from a misspelling', (
      tester,
    ) async {
      final state = await pumpField(tester);
      expect(
        entriesAt(state, 5).map(describe).first,
        isNot('Add to dictionary'),
      );
      expect(entriesAt(state, 5).first, isA<NativeMenuItem>());
      expect(describe(entriesAt(state, 5).first), '(Cut)');
    });

    testWidgets('a suggestion replaces only its own word', (tester) async {
      final state = await pumpField(tester);
      item(entriesAt(state, 11), 'simple').onSelected!();
      await tester.pump();
      expect(controller.text, 'Ths is a simple tset');
    });

    testWidgets('Add to dictionary teaches the dictionary and clears the '
        'underline at once', (tester) async {
      final state = await pumpField(tester);
      item(entriesAt(state, 11), 'Add to dictionary').onSelected!();
      expect(dictionary.added, ['smple']);
      expect(dictionary.ignored, isEmpty);
      expect(
        state.spellCheckResults!.suggestionSpans.map(
          (span) => span.range.textInside(_text),
        ),
        ['Ths', 'tset'],
      );
      expect(state.renderEditable.text!.toPlainText(), _text);
    });

    testWidgets('Ignore tells the dictionary to ignore the word', (
      tester,
    ) async {
      final state = await pumpField(tester);
      item(entriesAt(state, 1), 'Ignore').onSelected!();
      expect(dictionary.ignored, ['Ths']);
      expect(dictionary.added, isEmpty);
      expect(state.findSuggestionSpanAtCursorIndex(1), isNull);
    });
  });

  group('NativeContextMenu', () {
    test('numbers items from one and escapes access key ampersands', () {
      final encoded = NativeContextMenu.encode(
        [
          NativeMenuItem(label: 'A & B', onSelected: () {}),
          const NativeMenuSeparator(),
          NativeMenuItem(label: 'Copy', ctrlKey: 'C', onSelected: () {}),
          const NativeMenuItem(label: 'Off'),
        ],
        position: const Offset(10, 20),
        dark: true,
      );
      expect(encoded, {
        'x': 10.0,
        'y': 20.0,
        'dark': true,
        'items': [
          {'id': 1, 'label': 'A && B', 'enabled': true},
          {'separator': true},
          {'id': 3, 'label': 'Copy', 'enabled': true, 'ctrlKey': 'C'},
          {'id': 4, 'label': 'Off', 'enabled': false},
        ],
      });
    });

    test('runs only the chosen item', () {
      final chosen = <String>[];
      final entries = [
        NativeMenuItem(label: 'a', onSelected: () => chosen.add('a')),
        const NativeMenuSeparator(),
        NativeMenuItem(label: 'b', onSelected: () => chosen.add('b')),
      ];
      expect(NativeContextMenu.dispatch(entries, null), isFalse);
      expect(NativeContextMenu.dispatch(entries, 2), isFalse);
      expect(NativeContextMenu.dispatch(entries, 4), isFalse);
      expect(NativeContextMenu.dispatch(entries, 3), isTrue);
      expect(chosen, ['b']);
    });
  });

  group('showComposerNativeMenu', () {
    late List<Map<Object?, Object?>> shown;
    late Object? Function(List<Object?> items) answer;

    setUp(() {
      shown = [];
      answer = (_) => null;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeContextMenu.channel, (call) async {
            final arguments = call.arguments as Map<Object?, Object?>;
            shown.add(arguments);
            return answer(arguments['items'] as List<Object?>);
          });
      // The menu asks whether the clipboard holds text before it opens.
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, (call) async {
            if (call.method == 'Clipboard.hasStrings') return {'value': true};
            return null;
          });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(NativeContextMenu.channel, null);
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(SystemChannels.platform, null);
    });

    int idOf(List<Object?> items, String label) =>
        (items.cast<Map<Object?, Object?>>().singleWhere(
              (item) => item['label'] == label,
            )['id'])
            as int;

    testWidgets('a right-click offers the word under the pointer', (
      tester,
    ) async {
      final state = await pumpField(tester);
      // The caret sits at the end, in "tset"; the click is on "Ths".
      final renderEditable = state.renderEditable;
      final click = renderEditable.localToGlobal(
        renderEditable
            .getLocalRectForCaret(const TextPosition(offset: 1))
            .center,
      );
      answer = (items) => idOf(items, 'The');
      unawaited(
        showComposerNativeMenu(
          appContext,
          editableTextState: state,
          dictionary: dictionary,
          clickPosition: click,
        ),
      );
      await tester.pumpAndSettle();
      expect(shown, hasLength(1));
      expect(controller.text, 'The is a smple tset');
      final items = (shown.single['items'] as List<Object?>)
          .cast<Map<Object?, Object?>>();
      expect(
        items.singleWhere((item) => item['label'] == 'Paste')['enabled'],
        isTrue,
        reason: 'the clipboard holds text',
      );
      final position = Offset(
        (shown.single['x'] as num).toDouble(),
        (shown.single['y'] as num).toDouble(),
      );
      final ratio = tester.view.devicePixelRatio;
      expect(position, click * ratio);
    });

    testWidgets('Shift+F10 and the Menu key open it at the caret', (
      tester,
    ) async {
      await pumpField(tester);
      controller.selection = const TextSelection.collapsed(offset: 11);
      await tester.pump();

      answer = (items) => idOf(items, 'sample');
      await tester.sendKeyDownEvent(LogicalKeyboardKey.shift);
      await tester.sendKeyEvent(LogicalKeyboardKey.f10);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.shift);
      await tester.pumpAndSettle();
      expect(shown, hasLength(1));
      expect(controller.text, 'Ths is a sample tset');

      answer = (_) => null;
      await tester.sendKeyEvent(LogicalKeyboardKey.contextMenu);
      await tester.pumpAndSettle();
      expect(shown, hasLength(2));
      expect(controller.text, 'Ths is a sample tset');
    });
  });
}
