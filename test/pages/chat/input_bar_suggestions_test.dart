// SPDX-FileCopyrightText: 2019-Present Contributors to FluffyChat
//
// SPDX-License-Identifier: AGPL-3.0-or-later

// ignore_for_file: depend_on_referenced_packages

import 'package:emoji_picker_flutter/locales/default_emoji_set_locale.dart';
import 'package:fluffychat/config/setting_keys.dart';
import 'package:fluffychat/l10n/l10n.dart';
import 'package:fluffychat/pages/chat/input_bar.dart';
import 'package:fluffychat/utils/emoticons.dart';
import 'package:fluffychat/widgets/matrix.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';
import 'package:matrix/matrix.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../chat_list/chat_list_fakes.dart';

/// When the composer suggests emoji after a colon: only with the setting
/// on, which it is not by default, and never for an emoticon. And how the
/// suggestions look and are picked: a compact list of at most six rows,
/// moved through with the arrow keys.
void main() {
  late FakeChatListClient client;
  late InputBar bar;
  late Room room;

  setUp(() async {
    client = await setUpFakeChatList('input bar suggestions');
    room = addFakeChat(client, '!a:x', 'Drew', partner: '@drew:x');
    bar = InputBar(
      room: room,
      decoration: const InputDecoration(),
      suggestionEmojis: [
        for (final category in getDefaultEmojiLocale(const Locale('en')))
          ...category.emoji,
      ],
    );
  });

  tearDown(() => tearDownFakeChatList(client));

  List<Map<String, String?>> suggest(String text) => bar.getSuggestions(
    TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    ),
  );

  Iterable<String?> emoji(String text) =>
      suggest(text).where((s) => s['type'] == 'emoji').map((s) => s['emoji']);

  test('emoji suggestions are off by default', () {
    expect(AppSettings.emojiSuggestions.value, isFalse);
    expect(emoji('hi :smi'), isEmpty);
  });

  group('with emoji suggestions on', () {
    setUp(() => AppSettings.emojiSuggestions.setItem(true));
    tearDown(() => AppSettings.emojiSuggestions.setItem(false));

    test('two letters after the colon list emoji', () {
      expect(emoji('hi :smi'), isNotEmpty);
      expect(emoji(':dr'), contains('🤤'));
    });

    test('an emoticon or a single letter lists nothing', () {
      for (final text in [
        ':D',
        ':d',
        ':P',
        ':p',
        ':-P',
        ':-p',
        ':-D',
        ':o',
        'XD',
        'xD',
        ':s',
        'hi :x',
      ]) {
        expect(emoji(text), isEmpty, reason: text);
      }
    });

    test('links, times and code list nothing', () {
      for (final text in [
        'see https://exa',
        'at 10:30',
        'use `:smi',
        '```\n:smi',
      ]) {
        expect(emoji(text), isEmpty, reason: text);
      }
    });
  });

  test('mentions are suggested whatever the emoji setting', () {
    expect(suggest('hey @dr').where((s) => s['type'] == 'user'), isNotEmpty);
  });
  test('names starting with the query come first, faces before things', () {
    final hits = rankEmojiSuggestions([
      for (final category in getDefaultEmojiLocale(const Locale('en')))
        ...category.emoji,
    ], 'dro');
    expect(hits.first.emoji.emoji, '🤤');
    expect(hits.first.keyword, 'drooling');
    // Keywords that start with the query before those that only contain it.
    final contains = hits.indexWhere((hit) => !hit.keyword.startsWith('dro'));
    if (contains >= 0) {
      expect(
        hits.skip(contains).every((h) => !h.keyword.startsWith('dro')),
        isTrue,
      );
    }
  });

  group('the suggestion list', () {
    setUp(() => AppSettings.emojiSuggestions.setItem(true));
    tearDown(() => AppSettings.emojiSuggestions.setItem(false));

    Future<(TextEditingController, ComposerSuggestions)> pumpBar(
      WidgetTester tester,
    ) async {
      tester.view.devicePixelRatio = 1;
      tester.view.physicalSize = const Size(900, 600);
      addTearDown(tester.view.reset);
      final prefs = await SharedPreferences.getInstance();
      final controller = TextEditingController();
      final focus = FocusNode();
      final suggestions = ComposerSuggestions();
      addTearDown(controller.dispose);
      addTearDown(focus.dispose);
      await tester.pumpWidget(
        Provider<MatrixState>.value(
          value: FakeMatrix(client, prefs),
          child: MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            home: Scaffold(
              body: Column(
                children: [
                  const Spacer(),
                  InputBar(
                    room: room,
                    autofocus: false,
                    focusNode: focus,
                    controller: controller,
                    decoration: const InputDecoration(),
                    onChanged: (_) {},
                    onSubmitted: (_) {},
                    suggestions: suggestions,
                    emoticonFormatter: EmoticonFormatter(),
                    suggestionEmojis: [
                      for (final category in getDefaultEmojiLocale(
                        const Locale('en'),
                      ))
                        ...category.emoji,
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byType(TextField));
      await tester.pump();
      return (controller, suggestions);
    }

    Finder rows() => find.byWidgetPredicate(
      (widget) => widget is InkWell && widget.onTap != null,
      skipOffstage: true,
    );

    testWidgets('shows at most six compact rows, by name', (tester) async {
      final (_, suggestions) = await pumpBar(tester);
      await tester.enterText(find.byType(TextField), 'hi :do');
      await tester.pumpAndSettle();

      expect(suggestions.open, isTrue);
      final shown = rows().hitTestable().evaluate().toList();
      expect(shown.length, inInclusiveRange(1, 6));
      for (final row in shown) {
        expect(tester.getSize(find.byWidget(row.widget)).height, 44);
      }
      // A name, not a list of keywords split by bars.
      expect(find.textContaining('|', findRichText: true), findsNothing);
      expect(find.textContaining(':do', findRichText: true), findsWidgets);
    });

    testWidgets('an emoticon opens nothing and becomes an emoji on space', (
      tester,
    ) async {
      final (controller, suggestions) = await pumpBar(tester);
      await tester.enterText(find.byType(TextField), 'nice :D');
      await tester.pumpAndSettle();
      expect(suggestions.open, isFalse);
      expect(rows().hitTestable(), findsNothing);
      await tester.enterText(find.byType(TextField), 'nice :D ');
      await tester.pumpAndSettle();
      expect(controller.text, 'nice 😄 ');
    });

    testWidgets('Down moves the highlight, and picking inserts that emoji', (
      tester,
    ) async {
      final (controller, suggestions) = await pumpBar(tester);
      await tester.enterText(find.byType(TextField), 'brb :dro');
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final second = rankEmojiSuggestions([
        for (final category in getDefaultEmojiLocale(const Locale('en')))
          ...category.emoji,
      ], 'dro')[1].emoji.emoji;

      expect(suggestions.pickHighlighted(), isTrue);
      await tester.pumpAndSettle();
      expect(controller.text, 'brb $second ');
      expect(suggestions.open, isFalse);
    });

    testWidgets('Escape closes the list', (tester) async {
      final (_, suggestions) = await pumpBar(tester);
      await tester.enterText(find.byType(TextField), 'brb :dro');
      await tester.pumpAndSettle();
      expect(suggestions.open, isTrue);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(suggestions.open, isFalse);
    });
  });
}
